#!/bin/bash
# Disk usage monitoring and alerting
# Runs hourly via cron
#
# Required environment variable:
#   DISCORD_WEBHOOK - Discord webhook URL for alerts

THRESHOLD=90  # Alert if disk usage exceeds this percentage
HOSTNAME=$(hostname)
USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

if [ "$USAGE" -gt "$THRESHOLD" ]; then
  MESSAGE="🚨 **CRITICAL**: Disk usage on $HOSTNAME is at ${USAGE}%"

  # Send to Discord if webhook is configured
  if [ -n "$DISCORD_WEBHOOK" ]; then
    # Use printf and jq for proper JSON encoding
    PAYLOAD=$(printf '{"text":"%s"}' "$MESSAGE")
    curl -X POST -H 'Content-type: application/json' \
      --data "$PAYLOAD" \
      "$DISCORD_WEBHOOK" 2>/dev/null
  fi

  # Log the alert
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ALERT: $MESSAGE" >> /var/log/homelab-alert.log

  # Also try to send to Home Assistant if available
  curl -X POST -H 'Content-type: application/json' \
    --data "{\"message\":\"$MESSAGE\"}" \
    http://home.jsk:8123/api/webhook/disk_alert 2>/dev/null
fi
