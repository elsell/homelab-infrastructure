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

After bootstrap, the following services will be running:

| Service | Port | Purpose |
|---------|------|---------|
| Gitea | 3000, 2222 | Infrastructure code mirror |
| Vaultwarden | 8080 | Secrets management (Bitwarden compatible) |
| Prometheus | 9090 | Metrics collection |
| Grafana | 3001 | Dashboards (login: admin/changeme) |
| Alertmanager | 9093 | Alert routing |

## Post-Bootstrap

1. **Configure Grafana**:
   - Add Prometheus datasource: `http://prometheus:9090`
   - Import dashboards: 1860 (Node Exporter), 7249 (K8s)

2. **Set up Vaultwarden**:
   - Create admin account at http://192.168.2.228:8080
   - Set `SIGNUPS_ALLOWED=false` in docker-compose.yml
   - Restart: `docker compose restart vaultwarden`

3. **Update Alert URLs**:
   - Edit `alertmanager.yml` with your Discord webhook URL
   - Edit `../scripts/disk-alert.sh` with your Discord webhook URL

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
