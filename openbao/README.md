# OpenBao (secrets.jsksell.com)

Secrets for the 910 team's Kubernetes namespace and anything else that moves off Infisical.
Runs on lenny (mini-pc, 192.168.2.228), outside the cluster it serves, so the cluster can be
rebuilt from it and a cluster compromise doesn't hand over its storage.

| | |
| --- | --- |
| URL | `https://secrets.jsksell.com` (lenny port 443). Router DNS only; tailnet clients use split DNS and a route to 192.168.2.228:443 (infra repo `tailscale/policy.hujson`) |
| Image | `quay.io/openbao/openbao:2.7.2`, pinned by digest; read-only root, no capabilities |
| Storage | Integrated (raft), volume `openbao_openbao-data` |
| Unseal | Static key auto-unseal: volume `openbao_openbao-unseal` (`unseal.key`, uid 100, 0400). A copy is in John's keyring (`service openbao host secrets.jsksell.com purpose unseal-key`); without it a data backup can't be opened |
| Recovery keys | 5 shares, any 3 regenerate a root token. In John's keyring (`purpose recovery-key-N`) |
| TLS | Let's Encrypt via the cluster's cert-manager (infra repo `flux/.../apps/openbao`). `cert-sync` fetches the Secret every 12 h with an account that can read only it, then SIGHUPs OpenBao. If the cluster is down the current certificate stays in use (renewal starts 30 days before expiry) |
| Sign-in | OIDC through tsidp (Tailscale identity), with userpass as a fallback for IdP outages |

## First setup

```bash
cd /opt/homelab/openbao
# Unseal key, created once inside the volume (never printed):
docker run --rm -v openbao_openbao-unseal:/u alpine:3.22 sh -c \
  'umask 077; head -c 32 /dev/urandom > /u/unseal.key; chown 100:1000 /u/unseal.key; chmod 400 /u/unseal.key'
# Cluster credential for cert-sync: token + CA of openbao/lenny-cert-reader-token, written over stdin.
docker compose up -d
docker compose exec openbao bao operator init -recovery-shares=5 -recovery-threshold=3   # output goes to the keyring only
```

## Operate

```bash
docker compose ps; docker compose logs -f openbao cert-sync
docker compose exec openbao bao status -address=https://127.0.0.1:8200 -tls-server-name=secrets.jsksell.com
```

Update OpenBao by changing the digest in `docker-compose.yml` (read the release notes; raft
upgrades are one-way) and `docker compose up -d`.
