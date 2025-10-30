# Mini PC Configuration

This directory contains all configuration for the mini PC bootstrap node.

## Files

- **bootstrap.sh**: Automated setup script (run once)
- **docker-compose.yml**: Service definitions (Gitea, Vaultwarden, Prometheus, Grafana, Alertmanager)
- **prometheus.yml**: Prometheus scrape configuration
- **alert-rules.yml**: Alert definitions (disk, CPU, memory, host down)
- **alertmanager.yml**: Alert routing (Discord, Home Assistant)

## Quick Start

```bash
# From a fresh Ubuntu 22.04 install:
bash <(curl -fsSL https://raw.githubusercontent.com/elsell/homelab-infrastructure/main/mini-pc/bootstrap.sh)
```

## Services

After bootstrap, the following services will be running with HTTPS:

| Service | Port | URL | Purpose |
|---------|------|-----|---------|
| Gitea | 3000, 2222 | https://lenny:3000 | Infrastructure code mirror |
| Vaultwarden | 8080 | https://lenny:8080 | Secrets management (Bitwarden compatible) |
| Prometheus | 9090 | https://lenny:9090 | Metrics collection |
| Grafana | 3001 | https://lenny:3001 | Dashboards (login: admin/changeme) |
| Alertmanager | 9093 | https://lenny:9093 | Alert routing |
| nginx | - | - | Reverse proxy with self-signed SSL |

**Note**: All services use self-signed certificates. Your browser will show a security warning - this is expected.

## Post-Bootstrap

1. **Trust the self-signed certificate** (optional but recommended):
   ```bash
   # On macOS:
   sudo security add-trusted-cert -d -r trustRoot \
     -k /Library/Keychains/System.keychain \
     /opt/homelab/certs/nginx-selfsigned.crt

   # On Linux:
   sudo cp /opt/homelab/certs/nginx-selfsigned.crt \
     /usr/local/share/ca-certificates/lenny.crt
   sudo update-ca-certificates

   # Or just accept the browser warning each time
   ```

2. **Configure Grafana**:
   - Access https://lenny:3001 (accept certificate warning)
   - Login: admin / changeme
   - Add Prometheus datasource: `http://prometheus:9090`
   - Import dashboards: 1860 (Node Exporter), 7249 (K8s)

3. **Set up Vaultwarden**:
   - Access https://lenny:8080 (accept certificate warning)
   - Create admin account
   - Set `SIGNUPS_ALLOWED=false` in docker-compose.yml
   - Restart: `docker compose restart vaultwarden`

4. **Update Alert URLs**:
   - Edit `alertmanager.yml` with your Discord webhook URL
   - Add `DISCORD_WEBHOOK` to crontab for disk-alert.sh

## Maintenance

Automated cron jobs:
- **Every 6 hours**: Sync repos from GitHub (`/opt/homelab-dr/scripts/sync-repos.sh`)
- **Daily at 2 AM**: Cleanup old Docker images/logs (`/opt/homelab/scripts/disk-cleanup.sh`)
- **Hourly**: Check disk usage and alert if >90% (`/opt/homelab/scripts/disk-alert.sh`)

## Adding Scrape Targets

Edit `prometheus.yml` and add targets to the appropriate job:

```yaml
- job_name: 'node-exporter'
  static_configs:
    - targets:
      - '192.168.2.XX:9100'  # New host
```

Then reload Prometheus:
```bash
docker compose restart prometheus
```

## Troubleshooting

**Services won't start**:
```bash
cd /opt/homelab/mini-pc
docker compose logs
```

**Disk full**:
```bash
# Manual cleanup
docker system prune -af
/opt/homelab/scripts/disk-cleanup.sh
```

**Prometheus not scraping**:
- Verify node-exporter is running on target: `ssh target 'systemctl status prometheus-node-exporter'`
- Check Prometheus targets: http://192.168.2.228:9090/targets
