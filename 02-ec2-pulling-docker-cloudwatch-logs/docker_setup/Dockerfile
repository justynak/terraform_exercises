FROM alpine:3.20

# BusyBox `sh` + `wget` are built in; no extra libs strictly needed.
# Copy the heartbeat entrypoint.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
