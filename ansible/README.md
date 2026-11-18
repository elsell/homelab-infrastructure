# Ansible Automation for Homelab

This directory contains Ansible playbooks and inventory for managing homelab infrastructure.

## Directory Structure

```
ansible/
├── inventory/
│   └── hosts.yml          # Single source of truth for all hosts
├── playbooks/
│   ├── install-node-exporter.yml       # Install node-exporter + monitoring
│   └── update-prometheus-config.yml    # Update Prometheus from inventory
└── templates/
    └── prometheus.yml.j2               # Prometheus config template
```

## Inventory (Single Source of Truth)

`inventory/hosts.yml` contains all infrastructure metadata:
- IP addresses (ansible_host)
- Port numbers (node_exporter_port, prometheus_port, etc.)
- Connection details (ansible_user, ansible_connection)
- Service-specific config (prometheus_path, bearer tokens)

**Important**: This inventory is the canonical source for all host definitions. Other configs (prometheus.yml, terraform, etc.) should be generated from or reference this inventory.

## Terraform Integration

Ansible inventory can generate Terraform configs to eliminate duplication. See [TERRAFORM-INTEGRATION.md](TERRAFORM-INTEGRATION.md) for full details.

**Quick start:**
```bash
# Generate Terraform files from inventory
ansible-playbook playbooks/generate-terraform-configs.yml
```

This generates:
- `terraform/networking/locals.tf` - UniFi DHCP reservations
- `terraform/xcp-ng/cloud-configs/*.yml` - Cloud-init configs

## Available Playbooks

### install-node-exporter.yml

Installs and configures monitoring on Linux hosts:
- Installs node-exporter, ufw firewall, ncdu
- Configures journald log rotation (500MB max, 7-day retention)
- Sets up firewall (SSH + node-exporter from mini PC only: 192.168.2.228)
- Enables and starts node-exporter service

**Usage:**
```bash
# Test connectivity first
ansible all -i inventory/hosts.yml -m ping

# Run playbook (prompts for sudo password)
ansible-playbook -i inventory/hosts.yml playbooks/install-node-exporter.yml -K

# Run for specific group
ansible-playbook -i inventory/hosts.yml playbooks/install-node-exporter.yml -K --limit ubuntu_vms
```

**When to use:**
- Configuring existing VMs that weren't created by Terraform
- Updating configuration on existing VMs
- Repairing config drift

**Note:** VMs created via Terraform get this same configuration automatically via cloud-init. This playbook is for existing/legacy VMs or config updates.

**Idempotent**: Safe to run multiple times, only makes changes if needed.

### update-prometheus-config.yml

Generates prometheus.yml from Ansible inventory and deploys to mini PC:
- Uses templates/prometheus.yml.j2 to generate config
- Deploys to /opt/homelab/mini-pc/prometheus.yml on mini PC
- Creates backup of previous config (.yml.backup)
- Restarts Prometheus container if config changed

**Usage:**
```bash
# With SSH keys (recommended)
ansible-playbook -i inventory/hosts.yml playbooks/update-prometheus-config.yml

# With SSH password (if no keys set up)
ansible-playbook -i inventory/hosts.yml playbooks/update-prometheus-config.yml -k
```

**Note**: This playbook does NOT require sudo (`-K`) since it runs as the user to access their home directory and docker group.

**When to run:**
- After adding/removing hosts from inventory
- After changing ports or connection details
- After updating Home Assistant bearer token

**Idempotent**: Safe to run multiple times, only restarts Prometheus if config actually changed.

### generate-terraform-configs.yml

Generates Terraform configuration files from Ansible inventory:
- Creates `terraform/networking/locals.tf` with UniFi DHCP reservations
- Generates cloud-init configs in `terraform/xcp-ng/cloud-configs/` for each VM
- Uses inventory metadata: IPs, MACs, memory, CPU, usernames, ports

**Usage:**
```bash
# Runs on localhost, no SSH needed
ansible-playbook playbooks/generate-terraform-configs.yml
```

**Prerequisites:**
- Add Terraform metadata to inventory (MAC addresses, vm_memory_gb, vm_cpus, vm_disk_gb)
- See [TERRAFORM-INTEGRATION.md](TERRAFORM-INTEGRATION.md) for details

**When to run:**
- After adding new VMs to inventory with Terraform metadata
- After changing VM specs (memory, CPU, disk)
- After changing mini PC IP or firewall rules

**Idempotent**: Safe to run multiple times, creates backups of previous files.

## Workflow Examples

### Adding a New Host (Monitoring Only)

1. Add to `inventory/hosts.yml`:
```yaml
ubuntu_vms:
  hosts:
    new-host:
      ansible_host: 192.168.2.100
      node_exporter_port: 9100
```

2. Install monitoring:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/install-node-exporter.yml -K --limit new-host
```

3. Update Prometheus config:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/update-prometheus-config.yml
```

4. Verify in Prometheus UI: http://lenny:9090/targets

### Adding a New VM (Full Infrastructure-as-Code)

**Single source of truth approach - define VM once, generate everything:**

1. Add to `inventory/hosts.yml` with full metadata:
```yaml
ubuntu_vms:
  hosts:
    new-service:
      ansible_host: 192.168.2.100
      node_exporter_port: 9100
      # Terraform metadata:
      mac_address: "52:54:00:AA:BB:CC"
      vm_memory_gb: 4
      vm_cpus: 2
      vm_disk_gb: 50
```

2. Generate all configs from inventory:
```bash
# Generate Prometheus config
ansible-playbook -i inventory/hosts.yml playbooks/update-prometheus-config.yml

# Generate Terraform configs (DHCP + cloud-init)
ansible-playbook playbooks/generate-terraform-configs.yml
```

3. Apply infrastructure:
```bash
# Apply DHCP reservation
cd ../../terraform/networking
terraform plan && terraform apply

# Create VM with Terraform (if using Terraform for VMs)
cd ../xcp-ng
terraform plan && terraform apply
```

4. Verify:
```bash
# Check Prometheus: http://lenny:9090/targets
# SSH to new VM: ssh john@192.168.2.100
```

**Result**: VM defined once in inventory, everything else auto-generated!

### Updating Home Assistant Bearer Token

1. Edit `inventory/hosts.yml`:
```yaml
home_assistant:
  hosts:
    home:
      prometheus_bearer_token: "NEW_TOKEN_HERE"
```

2. Update Prometheus:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/update-prometheus-config.yml
```

### Applying Changes to All Hosts

```bash
# Example: Update journald config on all hosts
ansible-playbook -i inventory/hosts.yml playbooks/install-node-exporter.yml -K
```

## Password Management

The playbooks require sudo/become privileges. Options:

**Option 1: Interactive prompt (-K flag)**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/install-node-exporter.yml -K
# Enter sudo password when prompted
```

**Option 2: NOPASSWD sudo (Recommended for homelab)**
```bash
# On each target host:
echo "john ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/ansible
sudo chmod 0440 /etc/sudoers.d/ansible

# Then run without -K:
ansible-playbook -i inventory/hosts.yml playbooks/install-node-exporter.yml
```

**Option 3: Ansible Vault** (if different passwords per host)
See: https://docs.ansible.com/ansible/latest/vault_guide/index.html

## Testing

```bash
# Test connectivity to all hosts
ansible all -i inventory/hosts.yml -m ping

# Test connectivity to specific group
ansible ubuntu_vms -i inventory/hosts.yml -m ping

# Run ad-hoc command
ansible all -i inventory/hosts.yml -a "uptime"

# Check ansible version
ansible --version
```

## Requirements

- Ansible 2.9+
- SSH access to target hosts
- Sudo/become privileges on target hosts
- Docker installed on mini PC (for update-prometheus-config.yml)

## Notes

- All playbooks are idempotent - safe to run multiple times
- Backups are created automatically (check .backup files)
- Firewall rules allow only mini PC (192.168.2.228) to access metrics
- Journald logs limited to 500MB / 7 days to prevent disk fill
