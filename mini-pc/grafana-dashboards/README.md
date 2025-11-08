# Grafana Dashboards

Custom dashboards for homelab monitoring. Import these via Grafana UI: **Dashboards → Import → Upload JSON file**

## Available Dashboards

### 🌐 infrastructure-overview.json
**Single Pane of Glass for ALL Infrastructure**

Shows all node-exporter hosts AND TrueNAS in one view. Perfect for at-a-glance health monitoring.

**Features**:
- **Status Cards**: Total hosts, hosts down, low disk/memory/CPU warnings, **TrueNAS status**
  - **Click-through support**: Click any warning stat to see which specific hosts have issues
  - Opens Grafana Explore with pre-filtered query showing problem hosts
  - Click TrueNAS stat to open dedicated storage dashboard
- **TrueNAS ZFS Pool Bar**: Visual bar gauge showing ZFS pool usage with color warnings
- **Status Table**: All hosts with current status, CPU, memory, disk, load average
  - Color-coded gradient bars for quick visual scanning
  - Sorted by status (down hosts first)
- **Time Series Graphs**: CPU, memory, disk, load for ALL hosts on same chart
- **Auto-refresh**: 30 seconds

**How to use click-through**:
1. See "⚠️ Low Disk Hosts: 2" in the dashboard
2. Click the stat panel
3. Select "View low disk hosts"
4. Opens Explore view showing exactly which 2 hosts have low disk

**Use this when**: You want to quickly see if anything is wrong across your entire infrastructure

---

### 💾 truenas-storage.json
**Dedicated TrueNAS/ZFS Monitoring Dashboard**

Detailed monitoring for your TrueNAS storage system.

**Features**:
- **TrueNAS Status**: UP/DOWN indicator
- **ZFS Pool Usage**: Bar gauge showing all pools with color-coded warnings (>70% yellow, >85% orange, >95% red)
- **Disk I/O**: Read/write rates per disk device
- **Network Traffic**: RX/TX rates per interface
- **CPU Usage**: Per-core CPU utilization
- **Memory & ARC**: Memory usage with ZFS ARC cache size
- **ZFS Pool Table**: Detailed table with total size, used, available, and percentage for each pool

**Prerequisites**: TrueNAS must be configured to send Graphite metrics to mini PC (see BOOTSTRAP.md)

**Use this when**: You need detailed visibility into storage performance, pool health, or disk activity

---

### 🏠 home-assistant.json
**Home Assistant Action Dashboard**

Action-oriented dashboard showing critical Home Assistant metrics and IoT sensors.

**Features**:
- **HA Health**: Uptime and memory usage
- **Low Batteries**: Table of devices <70%, sorted lowest first
- **Power Consumption**: Real-time power usage across devices
- **Temperatures**: Environment (°F) and computer/chip (°C) temps
- **All Sensors**: Battery history, humidity

**Use this when**: You want to know what needs attention in your smart home (low batteries, device issues, etc.)

---

## Import Instructions

1. Open Grafana: https://lenny:3001
2. Login (admin / changeme)
3. **Add Prometheus datasource** (one-time setup):
   - Configuration → Data Sources → Add data source → Prometheus
   - URL: `http://prometheus:9090`
   - Save & Test

4. **Import dashboard**:
   - Dashboards → Import → Upload JSON file
   - Select dashboard file from this directory
   - Choose "Prometheus" as datasource
   - Click Import

## Recommended Setup

**For daily monitoring**, pin these dashboards in this order:
1. `infrastructure-overview.json` - Check overall infrastructure health
2. `home-assistant.json` - Check smart home status

**For troubleshooting a specific host**, use:
- Community dashboard "Node Exporter Full" (ID: 1860) - Detailed single-host metrics

## Auto-Discovery

Both dashboards use **auto-discovery queries**:
- Add a new host to `prometheus.yml` scrape targets
- Restart Prometheus
- New host automatically appears in dashboards!
- No need to edit dashboard JSON

Example:
```yaml
# prometheus.yml
- job_name: "node-exporter"
  static_configs:
    - targets:
        - "lenny:9100"
        - "don.jsk:9100"
        - "new-host:9100"  # <-- Add here, appears in dashboards automatically
```
