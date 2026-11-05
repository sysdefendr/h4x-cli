#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
apt install -y whois bind9-dnsutils curl python3
chmod +x "$DIR/h4x-cli" "$DIR"/modules/*.sh
for dep in curl python3 whois dig; do command -v "$dep" >/dev/null || echo "[~] Missing dependency: $dep"; done
sudo ln -sf "$DIR/h4x-cli" /usr/local/bin/h4x-cli
echo "[+] Installed: $(command -v h4x-cli)"
