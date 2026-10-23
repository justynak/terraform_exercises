#!/bin/sh
# Prints a heartbeat every 5s so CloudWatch Logs shows the container is alive.
set -eu

echo "hello-container: starting up (host=$(hostname))"
i=0
while true; do
  i=$((i + 1))
  echo "hello-container: heartbeat #$i at $(date -u +%FT%TZ)"
  sleep 5
done
