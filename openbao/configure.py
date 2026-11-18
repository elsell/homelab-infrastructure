#!/usr/bin/env python3
"""Configure OpenBao at secrets.jsksell.com (idempotent; safe to re-run).

Runs on John's workstation. The admin token comes from the desktop keyring
(service openbao host secrets.jsksell.com purpose infra-token, else root-token); the tsidp client
secret from service openclaw-sso purpose openbao-client-secret. Nothing secret is printed.

  openbao/configure.py                      # apply
  openbao/configure.py --issue-infra-token  # also mint the long-lived admin token for automation
"""
import json
import os
import secrets
import subprocess
import sys
import urllib.error
import urllib.request

ADDR = "https://secrets.jsksell.com"
ISSUER = "https://homelab-idp.sawfish-balance.ts.net"
REDIRECTS = ["https://secrets.jsksell.com/ui/vault/auth/oidc/oidc/callback", "http://localhost:8250/oidc/callback"]
# person -> (email, userpass name, groups)
PEOPLE = {
    "John": ("contactjohnsell@gmail.com", "john", ["admins"]),
    "Jared": ("jared4robertson@gmail.com", "jared", ["team-910"]),
    "Austin": ("aredenbaugh1@gmail.com", "austin", ["team-910"]),
}


def keyring(*attrs):
    return subprocess.run(["secret-tool", "lookup", *attrs], capture_output=True, text=True).stdout.strip()


TOKEN = keyring("service", "openbao", "host", "secrets.jsksell.com", "purpose", "infra-token") or \
    keyring("service", "openbao", "host", "secrets.jsksell.com", "purpose", "root-token")


def api(method, path, body=None, ok404=False):
    req = urllib.request.Request(f"{ADDR}/v1/{path}", method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"X-Vault-Token": TOKEN, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        if ok404 and e.code == 404:
            return None
        raise SystemExit(f"{method} {path}: HTTP {e.code} {e.read()[:400].decode(errors='replace')}")


POLICIES = {
    "admin": 'path "*" { capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"] }\n',
    # The 910 team: their KV mount (no permanent destroy), and their own userpass password.
    "team-910": """
path "910/data/*"     { capabilities = ["create", "read", "update", "patch", "delete", "list"] }
path "910/metadata/*" { capabilities = ["read", "list", "delete"] }
path "910/metadata"   { capabilities = ["list"] }
path "910/delete/*"   { capabilities = ["update"] }
path "910/undelete/*" { capabilities = ["update"] }
""",
    # Everyone may set their own fallback password (userpass alias name = their username).
    # External Secrets Operator in namespace 910 (role 910 below): read the 910 mount.
    "eso-910": """
path "910/data/*"     { capabilities = ["read"] }
path "910/metadata/*" { capabilities = ["read", "list"] }
""",
    # Infra's own secrets (admin only), e.g. the 910 runners' GitHub App; runners read their one path.
    "runners-910": """
path "infra/data/runners/*" { capabilities = ["read"] }
""",
    "self-password": 'path "auth/userpass/users/{{identity.entity.aliases.USERPASS.name}}/password" { capabilities = ["update"] }\n',
}


def ensure_auth(path, kind):
    if f"{path}/" not in api("GET", "sys/auth")["data"]:
        api("POST", f"sys/auth/{path}", {"type": kind})
    return api("GET", "sys/auth")["data"][f"{path}/"]["accessor"]


def main():
    if not TOKEN:
        sys.exit("No OpenBao token in the keyring")
    # The audit device (every request to the container log) is declared in config/openbao.hcl.

    oidc = ensure_auth("oidc", "oidc")
    userpass = ensure_auth("userpass", "userpass")
    # Sign-in page: only OIDC (first, so the default) and username/password are listed. The built-in
    # token method can't be disabled; the UI keeps it behind "other methods".
    for path, desc in (("oidc", "Tailscale (tsidp)"), ("userpass", "Password (fallback when the identity provider is down)")):
        api("POST", f"sys/auth/{path}/tune", {"listing_visibility": "unauth", "description": desc})
    api("POST", "sys/auth/token/tune", {"listing_visibility": "hidden"})
    api("POST", "auth/oidc/config", {"oidc_discovery_url": ISSUER, "oidc_client_id": "openbao",
                                     "oidc_client_secret": keyring("service", "openclaw-sso", "purpose", "openbao-client-secret"),
                                     "default_role": "person"})
    api("POST", "auth/oidc/role/person", {
        "role_type": "oidc", "user_claim": "email", "allowed_redirect_uris": REDIRECTS,
        "bound_claims": {"email": [p[0] for p in PEOPLE.values()]}, "oidc_scopes": ["openid", "email", "profile"],
        "token_ttl": "8h", "token_max_ttl": "24h", "token_policies": ["default"]})
    for name, body in POLICIES.items():
        api("PUT", f"sys/policies/acl/{name}", {"policy": body.replace("USERPASS", userpass)})

    if "infra/" not in api("GET", "sys/mounts")["data"]:
        api("POST", "sys/mounts/infra", {"type": "kv", "options": {"version": "2"}, "description": "infra secrets (admins only)"})
    if "910/" not in api("GET", "sys/mounts")["data"]:

        api("POST", "sys/mounts/910", {"type": "kv", "options": {"version": "2"}, "description": "910 team secrets"})

    # Kubernetes auth for the homelab cluster (MicroK8s, k8snode1). Each login's token reviews
    # itself (its account has system:auth-delegator), so OpenBao holds no long-lived cluster JWT.
    ensure_auth("kubernetes-homelab", "kubernetes")
    ca = subprocess.run(["kubectl", "--kubeconfig", os.path.expanduser("~/.kube/configs/local-don"), "-n", "kube-system", "get",
                         "configmap", "kube-root-ca.crt", "-o", "jsonpath={.data.ca\\.crt}"], capture_output=True, text=True, check=True).stdout
    api("POST", "auth/kubernetes-homelab/config", {"kubernetes_host": "https://192.168.2.92:16443", "kubernetes_ca_cert": ca,
                                                  "disable_local_ca_jwt": True})
    api("POST", "auth/kubernetes-homelab/role/910", {
        "bound_service_account_names": ["openbao-auth"], "bound_service_account_namespaces": ["910"],
        # No custom audience: the token also authenticates its own TokenReview to the API server.
        "audience": "", "token_policies": ["eso-910"], "token_ttl": "1h", "token_max_ttl": "1h"})

    # Self-hosted runners (namespace 910-runners, infra-owned): read infra/runners/* only.
    api("POST", "auth/kubernetes-homelab/role/910-runners", {
        "bound_service_account_names": ["openbao-auth"], "bound_service_account_namespaces": ["910-runners"],
        "audience": "", "token_policies": ["runners-910"], "token_ttl": "1h", "token_max_ttl": "1h"})

    members = {"admins": [], "team-910": []}
    for person, (email, user, groups) in PEOPLE.items():
        # The fallback login exists with a random password nobody knows; each person sets their own
        # after signing in with Tailscale (UI: their entity's userpass alias, or `bao write auth/userpass/users/NAME/password`).
        if api("GET", f"auth/userpass/users/{user}", ok404=True) is None:
            api("POST", f"auth/userpass/users/{user}", {"password": secrets.token_urlsafe(32), "token_ttl": "8h", "token_max_ttl": "24h"})
        api("POST", f"identity/entity/name/{person}", {"metadata": {"email": email}, "policies": ["self-password"]})
        entity = api("GET", f"identity/entity/name/{person}")["data"]
        have = {(a["mount_accessor"], a["name"]) for a in entity.get("aliases") or []}
        for accessor, alias in ((oidc, email), (userpass, user)):
            if (accessor, alias) not in have:
                api("POST", "identity/entity-alias", {"name": alias, "canonical_id": entity["id"], "mount_accessor": accessor})
        for g in groups:
            members[g].append(entity["id"])
    for group, ids in members.items():
        api("POST", f"identity/group/name/{group}", {"type": "internal", "policies": ["admin" if group == "admins" else group],
                                                    "member_entity_ids": ids})

    if "--issue-infra-token" in sys.argv:
        tok = api("POST", "auth/token/create-orphan", {"policies": ["admin"], "period": "720h", "display_name": "infra-automation",
                                                       "meta": {"purpose": "John's infra automation (configure.py, ESO setup)"}})
        subprocess.run(["secret-tool", "store", "--label", "OpenBao infra-token (secrets.jsksell.com)", "service", "openbao",
                        "host", "secrets.jsksell.com", "purpose", "infra-token"], input=tok["auth"]["client_token"], text=True, check=True)
        print("stored a periodic admin token in the keyring (purpose infra-token); renew it within 30 days")
    print("OpenBao configured: oidc (tsidp) + userpass fallback, groups admins/team-910, kv 910/")


if __name__ == "__main__":
    main()
