# Mini PC Bootstrap Guide

## Quick Start

### 1. Install Ubuntu Server 22.04 LTS

During installation:
- Hostname: `lenny`
- Username: `john` (or your preferred user)
- Enable OpenSSH server
- **Network**: Set static IP `192.168.2.228` or configure via DHCP reservation on UDM Pro

### 2. One-Command Bootstrap

```bash
# SSH into mini PC
ssh john@192.168.2.228

# Run bootstrap
bash <(curl -fsSL https://raw.githubusercontent.com/elsell/homelab-infrastructure/main/mini-pc/bootstrap.sh)
```

That's it. The script will:
- Install Docker, node-exporter, git
- Configure log rotation
- Clone your infrastructure repo
- Deploy all services (Gitea, Infisical, Prometheus, Grafana, Alertmanager)
- Set up cron jobs (repo sync, disk cleanup)
- Create necessary directories

### 3. Post-Bootstrap Configuration

**Grafana** (https://lenny:3001)
```bash
# Login: admin / changeme
# Add Prometheus datasource: http://prometheus:9090
# Import dashboards:
#   - Node Exporter Full (ID: 1860)
#   - Kubernetes Cluster Monitoring (ID: 7249)
```

**Infisical** (https://lenny:8080)
```bash
# Generate encryption keys:
openssl rand -hex 16  # Copy for ENCRYPTION_KEY
openssl rand -hex 32  # Copy for AUTH_SECRET

# Update docker-compose.yml with generated keys
cd /opt/homelab/mini-pc
nano docker-compose.yml
# Replace CHANGE_ME_32_CHAR_HEX with your generated keys

# Restart Infisical
docker compose restart infisical

# Access https://lenny:8080 and create admin account
```

**Set Discord Webhook for Alerts**
```bash
# 1. Get webhook from Discord
#    Server Settings → Integrations → Webhooks → New Webhook
#    Copy the webhook URL

# 2. Add to crontab (for disk-alert.sh)
crontab -e
# Uncomment and update this line:
# DISCORD_WEBHOOK=https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN/slack

# 3. Update alertmanager.yml
cd /opt/homelab/mini-pc
nano alertmanager.yml
# Replace REPLACE_WITH_YOUR_WEBHOOK_ID and REPLACE_WITH_YOUR_WEBHOOK_TOKEN
docker compose restart alertmanager
```

**Verify Services**
```bash
ssh john@192.168.2.228
cd /opt/homelab/mini-pc
docker-compose ps  # All should be "Up"

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].health'
```

---

## Manual Bootstrap (If Script Fails)

<details>
<summary>Expand for manual steps</summary>

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in

# Configure log rotation
sudo tee /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {"max-size": "10m", "max-file": "3"}
}
EOF
sudo systemctl restart docker

# Install dependencies
sudo apt update
sudo apt install -y git prometheus-node-exporter

# Clone repo
git clone https://github.com/elsell/homelab-infrastructure.git /opt/homelab

# Create directories
mkdir -p /opt/homelab-dr/{mirrors,scripts}
mkdir -p /opt/homelab/gitea

# Deploy services
cd /opt/homelab/mini-pc
docker-compose up -d

# Set up cron jobs
crontab -e
# Add:
# 0 */6 * * * /opt/homelab-dr/scripts/sync-repos.sh
# 0 2 * * * /opt/homelab/scripts/disk-cleanup.sh
# 0 * * * * /opt/homelab/scripts/disk-alert.sh
```

</details>

---

## Troubleshooting

**Docker permission denied**
```bash
sudo usermod -aG docker $USER
# Log out and back in
```

**Services won't start**
```bash
cd /opt/homelab/mini-pc
docker-compose logs
# Check for errors
```

**Disk full during bootstrap**
```bash
# Clean Docker
docker system prune -af

# Check space
df -h
```

**Can't reach GitHub**
```bash
# Use local Git clone instead
git clone /path/to/usb/homelab-infrastructure /opt/homelab
cd /opt/homelab/mini-pc
./bootstrap.sh
```
