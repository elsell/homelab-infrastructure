# OpenBao on lenny: secrets.jsksell.com (README.md).
ui            = true
disable_mlock = true # integrated storage: mlock is not recommended
api_addr      = "https://secrets.jsksell.com"
cluster_addr  = "https://openbao:8201"

storage "raft" {
  path    = "/openbao/file"
  node_id = "lenny"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  tls_cert_file   = "/openbao/tls/tls.crt"
  tls_key_file    = "/openbao/tls/tls.key"
  tls_min_version = "tls12"
}

# Auto-unseal from a key that never leaves lenny's openbao-unseal volume (and John's keyring, for
# disaster recovery). A reboot or an identity-provider outage never leaves OpenBao sealed.
seal "static" {
  current_key_id = "lenny-2026-11-18"
  current_key    = "file:///openbao/unseal/unseal.key"
}
