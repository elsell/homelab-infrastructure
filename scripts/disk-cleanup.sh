#!/bin/bash
# Automated disk cleanup
# Runs daily at 2 AM via cron

LOGFILE="/var/log/homelab-cleanup.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

log "=== Starting disk cleanup ==="

# Get disk usage before cleanup
BEFORE=$(df / | tail -1 | awk '{print $5}')
log "Disk usage before cleanup: $BEFORE"

# Clean up old Docker images (older than 1 week)
log "Cleaning Docker images..."
docker image prune -af --filter "until=168h" >> "$LOGFILE" 2>&1

# Clean up old Git pack files (older than 30 days)
log "Cleaning old Git pack files..."
find /opt/homelab-dr/mirrors -name "*.pack" -mtime +30 -delete 2>> "$LOGFILE"

# Clean up system journal logs (keep only 7 days)
log "Cleaning system logs..."
journalctl --vacuum-time=7d >> "$LOGFILE" 2>&1

# Clean up old log files
log "Cleaning old log files..."
find /var/log -name "*.log.*" -mtime +7 -delete 2>> "$LOGFILE"
find /var/log -name "*.gz" -mtime +7 -delete 2>> "$LOGFILE"

# Get disk usage after cleanup
AFTER=$(df / | tail -1 | awk '{print $5}')
log "Disk usage after cleanup: $AFTER"

log "=== Cleanup complete ==="
