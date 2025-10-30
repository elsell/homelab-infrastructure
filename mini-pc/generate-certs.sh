#!/bin/bash
# Generate self-signed certificates for nginx

CERT_DIR="/opt/homelab/certs"
DOMAIN="lenny"  # Change to your mini PC hostname

mkdir -p "$CERT_DIR"

# Generate self-signed certificate valid for 10 years
openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout "$CERT_DIR/nginx-selfsigned.key" \
  -out "$CERT_DIR/nginx-selfsigned.crt" \
  -subj "/C=US/ST=State/L=City/O=Homelab/CN=$DOMAIN" \
  -addext "subjectAltName=DNS:$DOMAIN,DNS:*.local,IP:192.168.2.228,IP:127.0.0.1"

# Set proper permissions
chmod 644 "$CERT_DIR/nginx-selfsigned.crt"
chmod 600 "$CERT_DIR/nginx-selfsigned.key"

echo "Certificates generated in $CERT_DIR"
echo "To trust on your local machine:"
echo "  - macOS: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CERT_DIR/nginx-selfsigned.crt"
echo "  - Linux: sudo cp $CERT_DIR/nginx-selfsigned.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
