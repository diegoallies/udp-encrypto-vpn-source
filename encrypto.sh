#!/usr/bin/env bash
set -euo pipefail

ZIVPN_VERSION="1.4.9"
ZIVPN_SHA256="df6658c195882ff2f6cefb44050e8cb2c238ceb2b6e3fbefb931698f4f0519cb"
ZIVPN_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_${ZIVPN_VERSION}/udp-zivpn-linux-amd64"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run with sudo: sudo ./encrypto.sh" >&2
  exit 1
fi

for command in curl openssl sha256sum systemctl useradd install; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Missing required command: ${command}" >&2
    exit 1
  fi
done

if [[ $(uname -m) != "x86_64" ]]; then
  echo "This installer supports x86_64 only." >&2
  exit 1
fi

read -r -s -p "Encrypto VPN password [masepoes]: " encrypto_password
echo

if [[ -z ${encrypto_password} ]]; then
  encrypto_password="masepoes"
elif [[ ${#encrypto_password} -lt 16 || ! ${encrypto_password} =~ ^[A-Za-z0-9._~-]+$ ]]; then
  echo "Use at least 16 characters from: A-Z a-z 0-9 . _ ~ -" >&2
  exit 1
fi

download_path=$(mktemp)
trap 'rm -f "${download_path}"' EXIT

curl --fail --location --proto '=https' --tlsv1.2 "${ZIVPN_URL}" --output "${download_path}"
echo "${ZIVPN_SHA256}  ${download_path}" | sha256sum --check --status

systemctl stop encrypto-vpn.service 2>/dev/null || true

if ! id encrypto-vpn >/dev/null 2>&1; then
  useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin encrypto-vpn
fi

install -d -m 0750 -o root -g encrypto-vpn /etc/encrypto-vpn
install -m 0755 -o root -g root "${download_path}" /usr/local/bin/encrypto-vpn

cat > /etc/encrypto-vpn/config.json <<EOF
{
  "listen": "127.0.0.1:5667",
  "cert": "/etc/encrypto-vpn/encrypto-vpn.crt",
  "key": "/etc/encrypto-vpn/encrypto-vpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["${encrypto_password}"]
  }
}
EOF

openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
  -subj "/CN=encrypto-vpn" \
  -keyout /etc/encrypto-vpn/encrypto-vpn.key \
  -out /etc/encrypto-vpn/encrypto-vpn.crt

chown root:encrypto-vpn /etc/encrypto-vpn/config.json /etc/encrypto-vpn/encrypto-vpn.key /etc/encrypto-vpn/encrypto-vpn.crt
chmod 0640 /etc/encrypto-vpn/config.json /etc/encrypto-vpn/encrypto-vpn.key
chmod 0644 /etc/encrypto-vpn/encrypto-vpn.crt

cat > /etc/sysctl.d/90-encrypto-vpn.conf <<'EOF'
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF

sysctl --system >/dev/null

cat > /etc/systemd/system/encrypto-vpn.service <<'EOF'
[Unit]
Description=Encrypto VPN UDP server for local Playit forwarding
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=encrypto-vpn
Group=encrypto-vpn
WorkingDirectory=/etc/encrypto-vpn
ExecStart=/usr/local/bin/encrypto-vpn server -c /etc/encrypto-vpn/config.json
Restart=on-failure
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadOnlyPaths=/etc/encrypto-vpn
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now encrypto-vpn.service
systemctl --no-pager --full status encrypto-vpn.service

echo "Encrypto VPN is listening locally on UDP 127.0.0.1:5667."
echo "Create a Playit custom UDP tunnel whose local address is 127.0.0.1:5667."
