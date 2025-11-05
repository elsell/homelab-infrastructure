#!/bin/bash
# GitHub repository mirror sync
# Runs every 6 hours via cron

MIRROR_DIR="/opt/homelab-dr/mirrors"
LOGFILE="/var/log/homelab-sync.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

# Create mirror directory if it doesn't exist
mkdir -p "$MIRROR_DIR"

# Mirror homelab-infrastructure from GitHub
log "Syncing homelab-infrastructure from GitHub..."
if [ -d "$MIRROR_DIR/homelab-infrastructure.git" ]; then
  cd "$MIRROR_DIR/homelab-infrastructure.git"
  git fetch --all --prune >> "$LOGFILE" 2>&1
  if [ $? -eq 0 ]; then
    log "✓ homelab-infrastructure synced successfully"
  else
    log "✗ Failed to sync homelab-infrastructure"
  fi
else
  git clone --mirror https://github.com/elsell/homelab-infrastructure.git \
    "$MIRROR_DIR/homelab-infrastructure.git" >> "$LOGFILE" 2>&1
  if [ $? -eq 0 ]; then
    log "✓ homelab-infrastructure cloned successfully"
  else
    log "✗ Failed to clone homelab-infrastructure"
  fi
fi

# Mirror local Gitea infra repo (if accessible)
log "Syncing infra from local Gitea..."
if [ -d "$MIRROR_DIR/infra.git" ]; then
  cd "$MIRROR_DIR/infra.git"
  git remote update --prune >> "$LOGFILE" 2>&1
  if [ $? -eq 0 ]; then
    log "✓ infra synced successfully"
  else
    log "✗ Failed to sync infra (Gitea may be unreachable)"
  fi
else
  # Try to clone from Gitea (may fail if not set up yet)
  git clone --mirror ssh://git@git.jsk:2222/local-k8s/infra.git \
    "$MIRROR_DIR/infra.git" >> "$LOGFILE" 2>&1
  if [ $? -eq 0 ]; then
    log "✓ infra cloned successfully"
  else
    log "✗ Failed to clone infra (Gitea may not be configured yet)"
  fi
fi

log "Sync complete"
