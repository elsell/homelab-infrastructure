#!/bin/bash
set -e

echo "========================================="
echo "Homelab Mini PC Bootstrap"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [ "$EUID" -eq 0 ]; then
  log_error "Do not run as root. Run as your normal user (will use sudo when needed)"
  exit 1
fi

# Install Docker if not present
if ! command -v docker &> /dev/null; then
  log_info "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker $USER
  log_warn "Docker installed. You may need to log out and back in for group changes."
  log_warn "Re-run this script after logging back in."
  exit 0
fi

# Verify docker group membership
if ! groups | grep -q docker; then
  log_error "User not in docker group. Run: sudo usermod -aG docker $USER"
  log_error "Then log out and back in, and re-run this script."
  exit 1
fi

# Configure Docker log rotation
log_info "Configuring Docker log rotation..."
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
sudo systemctl restart docker
sleep 2

# Install system packages
log_info "Installing system packages..."
sudo apt update
sudo apt install -y git prometheus-node-exporter curl jq ufw

# Configure UFW firewall
log_info "Configuring firewall..."
sudo ufw --force enable
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 3000/tcp  # Gitea HTTP
sudo ufw allow 2222/tcp  # Gitea SSH
sudo ufw allow 8080/tcp  # Vaultwarden
sudo ufw allow 9090/tcp  # Prometheus
sudo ufw allow 3001/tcp  # Grafana
sudo ufw allow 9093/tcp  # Alertmanager
sudo ufw allow 9100/tcp  # node-exporter
log_info "Firewall configured and enabled"

# Ensure node-exporter is running
sudo systemctl enable prometheus-node-exporter
sudo systemctl start prometheus-node-exporter

# Clone repo if not already present
if [ ! -d "/opt/homelab/.git" ]; then
  log_info "Cloning infrastructure repository..."
  if [ -d "/opt/homelab" ]; then
    log_warn "/opt/homelab exists but is not a git repo. Moving to /opt/homelab.bak"
    sudo mv /opt/homelab /opt/homelab.bak
  fi

  # Clone
  sudo git clone https://github.com/elsell/homelab-infrastructure.git /opt/homelab
  sudo chown -R $USER:$USER /opt/homelab
else
  log_info "Repository already cloned at /opt/homelab"
  cd /opt/homelab
  git pull origin main || git pull origin master
fi

# Create directory structure
log_info "Creating directory structure..."
sudo mkdir -p /opt/homelab-dr/mirrors
sudo mkdir -p /opt/homelab-dr/scripts
sudo mkdir -p /opt/homelab/vaultwarden
sudo mkdir -p /opt/homelab/gitea
sudo chown -R $USER:$USER /opt/homelab /opt/homelab-dr

# Copy scripts to DR location
cp /opt/homelab/scripts/*.sh /opt/homelab-dr/scripts/ 2>/dev/null || true
cp /opt/homelab/scripts/*.sh /opt/homelab/scripts/ 2>/dev/null || true

# Make scripts executable
chmod +x /opt/homelab/scripts/*.sh 2>/dev/null || true
chmod +x /opt/homelab-dr/scripts/*.sh 2>/dev/null || true
chmod +x /opt/homelab/mini-pc/generate-certs.sh 2>/dev/null || true

# Generate self-signed certificates for nginx
if [ ! -f "/opt/homelab/certs/nginx-selfsigned.crt" ]; then
  log_info "Generating self-signed SSL certificates..."
  sudo mkdir -p /opt/homelab/certs
  sudo /opt/homelab/mini-pc/generate-certs.sh
  sudo chown -R $USER:$USER /opt/homelab/certs
else
  log_info "SSL certificates already exist, skipping generation"
fi

# Deploy Docker services
log_info "Deploying Docker services..."
cd /opt/homelab/mini-pc
docker compose pull
docker compose up -d

# Wait for services to start
log_info "Waiting for services to start..."
sleep 10

# Verify services
log_info "Verifying services..."
docker compose ps

# Set up cron jobs
log_info "Setting up cron jobs..."
CRON_TEMP=$(mktemp)
crontab -l > "$CRON_TEMP" 2>/dev/null || true

# Add environment variable for Discord webhook (if not already present)
if ! grep -q "DISCORD_WEBHOOK=" "$CRON_TEMP"; then
  cat >> "$CRON_TEMP" <<'EOF'
# Discord webhook for alerts (replace with your actual webhook URL)
# DISCORD_WEBHOOK=https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN/slack

EOF
fi

# Add cron jobs if not already present
grep -q "sync-repos.sh" "$CRON_TEMP" || echo "0 */6 * * * /opt/homelab-dr/scripts/sync-repos.sh >> /var/log/homelab-sync.log 2>&1" >> "$CRON_TEMP"
grep -q "disk-cleanup.sh" "$CRON_TEMP" || echo "0 2 * * * /opt/homelab/scripts/disk-cleanup.sh >> /var/log/homelab-cleanup.log 2>&1" >> "$CRON_TEMP"
grep -q "disk-alert.sh" "$CRON_TEMP" || echo "0 * * * * /opt/homelab/scripts/disk-alert.sh >> /var/log/homelab-alert.log 2>&1" >> "$CRON_TEMP"

crontab "$CRON_TEMP"
rm "$CRON_TEMP"

# Display status
echo ""
echo "========================================="
echo "Bootstrap Complete!"
echo "========================================="
echo ""
echo "Services:"
echo "  Prometheus:   http://$(hostname -I | awk '{print $1}'):9090"
echo "  Grafana:      http://$(hostname -I | awk '{print $1}'):3001 (admin/changeme)"
echo "  Gitea:        http://$(hostname -I | awk '{print $1}'):3000"
echo "  Vaultwarden:  http://$(hostname -I | awk '{print $1}'):8080"
echo ""
echo "Next steps:"
echo "  1. Configure Grafana: Add Prometheus datasource, import dashboards (1860, 7249)"
echo "  2. Set up Vaultwarden: Create admin account, then disable signups in docker-compose.yml"
echo "  3. Set Discord webhook: crontab -e and uncomment/update DISCORD_WEBHOOK line"
echo "  4. Update alertmanager.yml with your Discord webhook URL"
echo "  5. Test: curl http://localhost:9090/api/v1/targets"
echo ""
