# 02 - Private EC2 pulling a container image from ECR via VPC endpoints

A small, self-contained lab that demonstrates running a container on an EC2
instance that lives in a **private subnet with no internet egress**, pulling its
image from **ECR** and shipping logs to **CloudWatch Logs** — all through
**VPC endpoints**.

## Architecture

```
                         +---------------------------------------------+
                         |                  VPC 10.10.0.0/16            |
                         |                                               |
                         |   public-subnet-a        private-subnet-a     |
                         |   10.10.11.0/24          10.10.1.0/24         |
                         |   (no resources yet)     +---------------+    |
                         |                          |  EC2 app      |    |
                         |                          |  server       |    |
                         |                          +-------+-------+    |
                         |                                  |            |
                         |      +---------------------------+-----------+|
                         |      |   Interface endpoints (443)           ||
                         |      |   ecr.api, ecr.dkr, logs,             ||
                         |      |   ssm, ssmmessages, ec2messages       ||
                         |      +---------------------------+-----------+|
                         |                                  |            |
                         |      +---------------------------+-----------+|
                         |      |  Gateway endpoint (S3, via route tbl) ||
                         |      +---------------------------------------+|
                         +---------------------------------------------+

  External AWS services reached only through endpoints:
   - ECR             -> pull the container image
   - CloudWatch Logs -> ship container stdout/stderr (awslogs driver)
   - SSM             -> Session Manager shell-in (no inbound SG rules)
   - S3              -> image layers / dnf repositories
```

A heartbeat container (`docker_setup/`) is built and pushed to ECR during
`terraform apply`, then pulled and run on boot by the instance's `user_data`.

## What gets created

| File | Resources |
|------|-----------|
| `network.tf` | VPC, one public + one private subnet (single AZ), private route table, VPC endpoints (ECR, Logs, SSM interface; S3 gateway) |
| `security_groups.tf` | `app-server-sg` (egress to endpoints only) and `vpc-endpoint-sg` (443 from app server) |
| `iam.tf` | EC2 instance role + instance profile, with ECR read, SSM core, and CloudWatch Logs write policies |
| `compute.tf` | `aws_instance` (Amazon Linux 2023) and the SSM parameter lookup for the AMI |
| `ecr.tf` | ECR repository, CloudWatch log group, and the `terraform_data` build-and-push step |
| `templates/user_data.sh.tpl` | Boot script: install Docker, pull the image, run it with the `awslogs` driver |
| `locals.tf` | VPC CIDR, AZ, and subnet CIDRs |
| `data.tf` | Current AWS region lookup |

### Networking model

- **Single AZ / single private subnet** (`eu-central-1a`). Endpoints and the
  instance all sit in `private-subnet-a`. Extending to multiple AZs means
  adding subnets and passing their IDs (`[...]`) to the endpoints.
- The **private route table** has no internet route — only the implicit
  `local` route plus the S3 gateway endpoint association.
- **Interface endpoints** (ECR/Logs/SSM) have private DNS enabled and use the
  shared `vpc-endpoint-sg`. The **S3 gateway endpoint** is associated with the
  private route table.

### Instance bootstrap (`templates/user_data.sh.tpl`)

Rendered with `templatefile()` from `compute.tf`. It:

1. Installs and starts Docker.
2. Authenticates to ECR (`aws ecr get-login-password`).
3. Pulls `:v1` of the image, retrying up to 10 times (endpoint DNS can take a
   moment right after creation).
4. Runs the container with `--log-driver=awslogs`, streaming to the shared log
   group — no CloudWatch agent required.
5. Fails loudly if the container falls back to `json-file` logging.

> The `awslogs-create-stream` log option is intentionally **not** used: it is
> missing on the AL2023 Docker package and would abort `docker run`.

## Prerequisites

- Terraform >= 1.2, AWS provider ~> 5.92 (see `versions.tf`).
- AWS credentials for the target account/region (`eu-central-1`), configured on
  the machine running `terraform apply` (e.g. via `AWS_PROFILE`).
- **A local Docker daemon** and the **AWS CLI** on the machine running `apply`:
  the `terraform_data.image_push` provisioner runs `docker build`/`push`
  locally. This is a lab convenience, not a production pattern.

## Usage

```bash
cd 02-vpc-endpoint-to-db-and-ecr

terraform init
terraform plan
terraform apply
```

`terraform apply` will:
1. Build `docker_setup/` and push it to ECR as `:v1`.
2. Create the network, endpoints, IAM, and the EC2 instance.
3. Boot the instance, which pulls and runs the image without internet access.

The image is rebuilt and pushed **only when files under `docker_setup/` change**
(tracked by `terraform_data.image_push`). A rebuild also replaces the instance
(`replace_triggered_by`), so it re-pulls the new image.

### Configuration

Set in `terraform.tfvars` / variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `instance_type` | `c5.large` | EC2 instance type |

Networking values (VPC CIDR, AZ, subnet CIDRs) live in `locals.tf`.

## Outputs

| Output | Description |
|--------|-------------|
| `instance_id` | The application EC2 instance ID |
| `ecr_repository_url` | The ECR repository URL |
| `log_group_name` | CloudWatch log group the container writes to |

## Operating the instance

The instance has **no inbound access**; use SSM Session Manager (via the SSM
endpoints) to get a shell:

```bash
aws ssm start-session --target "$(terraform output -raw instance_id)"
```

Watch container logs:

```bash
aws logs tail "$(terraform output -raw log_group_name)" --follow
```

## Notes & limitations

- Single AZ, single subnet, no DB — despite the folder name `...-to-db-and-ecr`.
- No load balancer / public ingress yet; the app server SG has egress only.
