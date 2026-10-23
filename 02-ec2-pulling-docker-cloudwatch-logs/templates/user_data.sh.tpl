#!/bin/bash
set -uxo pipefail

# Log everything so it survives even if a step fails.
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

dnf install -y docker
systemctl enable --now docker

# --- Pull image from ECR via the interface endpoints ---
REPO_URL="${repository_url}"
REGISTRY="$${REPO_URL%%/*}"

aws ecr get-login-password --region "${region}" \
  | docker login --username AWS --password-stdin "$REGISTRY"

# Retry: interface endpoints may take a moment to resolve DNS.
pulled=false
for i in $(seq 1 10); do
  if docker pull "$REPO_URL:${image_tag}"; then pulled=true; break; fi
  echo "pull retry $i..."
  sleep 15
done
if [ "$pulled" != true ]; then
  echo "ERROR: could not pull $REPO_URL:${image_tag} after retries" >&2
  exit 1
fi

# --- Run it, streaming stdout/stderr straight to CloudWatch Logs ---
# The awslogs driver uses the instance role + the `logs` VPC endpoint;
# no CloudWatch agent needed. Do NOT add `awslogs-create-stream`: that
# log-opt is missing on the AL2023 docker package and `docker run` aborts
# with "unknown log opt" before the container is created.
REGION="${region}"
GROUP="${log_group_name}"
STREAM="$(hostname)"

if ! RUN_ERR="$(docker run -d --name hello-container --restart unless-stopped \
  --log-driver=awslogs \
  --log-opt awslogs-region="$REGION" \
  --log-opt awslogs-group="$GROUP" \
  --log-opt awslogs-stream="$STREAM" \
  --log-opt awslogs-create-group=true \
  "$REPO_URL:${image_tag}" 2>&1)"; then
  echo "ERROR: docker run failed: $RUN_ERR" >&2
  exit 1
fi

# Guard against the awslogs driver silently falling back to json-file
# (container runs, but nothing reaches CloudWatch).
driver="$(docker inspect -f '{{.HostConfig.LogConfig.Type}}' hello-container)"
if [ "$driver" != "awslogs" ]; then
  echo "ERROR: container is using '$driver' logging, not awslogs" >&2
  exit 1
fi
