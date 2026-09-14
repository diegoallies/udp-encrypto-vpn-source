#!/usr/bin/env bash
set -euo pipefail

ZIVPN_VERSION="1.4.9"
ZIVPN_SHA256="df6658c195882ff2f6cefb44050e8cb2c238ceb2b6e3fbefb931698f4f0519cb"
ZIVPN_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_${ZIVPN_VERSION}/udp-zivpn-linux-amd64"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run with sudo: sudo ./encrypto.sh" >&2
  exit 1
fi

for command in cmp curl install mktemp openssl sha256sum sysctl systemctl useradd; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Missing required command: ${command}" >&2
    exit 1
  fi
done

if [[ $(uname -m) != "x86_64" ]]; then
  echo "This installer supports x86_64 only." >&2
  exit 1
fi

work_dir=$(mktemp -d)
trap 'rm -rf "${work_dir}"' EXIT
service_changed=false

if id encrypto-vpn >/dev/null 2>&1; then
  echo "[ok] Service user already exists."
else
  useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin encrypto-vpn
  echo "[done] Created service user."
fi

install -d -m 0750 -o root -g encrypto-vpn /etc/encrypto-vpn

if [[ -x /usr/local/bin/encrypto-vpn ]] \
  && echo "${ZIVPN_SHA256}  /usr/local/bin/encrypto-vpn" | sha256sum --check --status; then
  echo "[ok] Server engine is current."
else
  curl --fail --location --proto '=https' --tlsv1.2 "${ZIVPN_URL}" --output "${work_dir}/encrypto-vpn"
  echo "${ZIVPN_SHA256}  ${work_dir}/encrypto-vpn" | sha256sum --check --status
  systemctl stop encrypto-vpn.service 2>/dev/null || true
  install -m 0755 -o root -g root "${work_dir}/encrypto-vpn" /usr/local/bin/encrypto-vpn
  service_changed=true
  echo "[done] Installed verified server engine."
fi

if [[ -s /etc/encrypto-vpn/config.json ]]; then
  echo "[ok] Existing VPN configuration and password preserved."
else
  read -r -s -p "Encrypto VPN password [masepoes]: " encrypto_password
  echo

  if [[ -z ${encrypto_password} ]]; then
    encrypto_password="masepoes"
  elif [[ ${#encrypto_password} -lt 16 || ! ${encrypto_password} =~ ^[A-Za-z0-9._~-]+$ ]]; then
    echo "Use at least 16 characters from: A-Z a-z 0-9 . _ ~ -" >&2
    exit 1
  fi

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
  service_changed=true
  echo "[done] Created VPN configuration."
fi

if [[ -s /etc/encrypto-vpn/encrypto-vpn.key ]] \
  && openssl x509 -in /etc/encrypto-vpn/encrypto-vpn.crt -checkend 0 -noout >/dev/null 2>&1; then
  echo "[ok] Existing TLS certificate is valid."
else
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/CN=encrypto-vpn" \
    -keyout /etc/encrypto-vpn/encrypto-vpn.key \
    -out /etc/encrypto-vpn/encrypto-vpn.crt \
    >/dev/null 2>&1
  service_changed=true
  echo "[done] Generated TLS certificate."
fi

chown root:encrypto-vpn /etc/encrypto-vpn/config.json /etc/encrypto-vpn/encrypto-vpn.key /etc/encrypto-vpn/encrypto-vpn.crt
chmod 0640 /etc/encrypto-vpn/config.json /etc/encrypto-vpn/encrypto-vpn.key
chmod 0644 /etc/encrypto-vpn/encrypto-vpn.crt

cat > "${work_dir}/90-encrypto-vpn.conf" <<'EOF'
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF

if [[ -f /etc/sysctl.d/90-encrypto-vpn.conf ]] \
  && cmp -s "${work_dir}/90-encrypto-vpn.conf" /etc/sysctl.d/90-encrypto-vpn.conf; then
  echo "[ok] Network buffer settings are current."
else
  install -m 0644 "${work_dir}/90-encrypto-vpn.conf" /etc/sysctl.d/90-encrypto-vpn.conf
  sysctl --system >/dev/null
  echo "[done] Applied network buffer settings."
fi

cat > "${work_dir}/encrypto-vpn.service" <<'EOF'
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

if [[ -f /etc/systemd/system/encrypto-vpn.service ]] \
  && cmp -s "${work_dir}/encrypto-vpn.service" /etc/systemd/system/encrypto-vpn.service; then
  echo "[ok] Systemd service definition is current."
else
  install -m 0644 "${work_dir}/encrypto-vpn.service" /etc/systemd/system/encrypto-vpn.service
  systemctl daemon-reload
  service_changed=true
  echo "[done] Installed systemd service definition."
fi

if ! systemctl is-enabled --quiet encrypto-vpn.service; then
  systemctl enable encrypto-vpn.service
fi

if [[ ${service_changed} == true ]] || ! systemctl is-active --quiet encrypto-vpn.service; then
  systemctl restart encrypto-vpn.service
  echo "[done] Started Encrypto VPN service."
else
  echo "[ok] Encrypto VPN service is already running."
fi

systemctl --no-pager --full status encrypto-vpn.service

if command -v playit >/dev/null 2>&1; then
  echo "[ok] Playit is already installed."
else
  for command in apt-get gpg; do
    if ! command -v "${command}" >/dev/null 2>&1; then
      echo "Missing required command: ${command}" >&2
      exit 1
    fi
  done

  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    https://playit-cloud.github.io/ppa/key.gpg \
    | gpg --dearmor --batch --yes --output /etc/apt/trusted.gpg.d/playit.gpg
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/playit.gpg] https://playit-cloud.github.io/ppa/data ./" \
    > /etc/apt/sources.list.d/playit-cloud.list
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y playit
  echo "[done] Installed Playit."
fi

if ! systemctl is-enabled --quiet playit.service; then
  systemctl enable playit.service
fi

if systemctl is-active --quiet playit.service; then
  echo "[ok] Playit service is already running."
else
  systemctl start playit.service
  echo "[done] Started Playit service."
fi

if [[ -s /etc/playit/playit.toml ]]; then
  echo "[ok] Playit agent is already claimed."
else
  echo "Playit will print a claim URL. Open it in your browser and approve this agent."
  playit setup
fi

echo "[ready] Encrypto VPN is listening locally on UDP 127.0.0.1:5667."
echo "Open the Playit account link below, then create a Custom UDP tunnel to 127.0.0.1:5667."
if ! playit account login-url; then
  echo "https://playit.gg/account/tunnels"
fi

show_playit_step() {
  local step_number=$1
  local instruction=$2

  echo
  echo "Playit step ${step_number}: ${instruction}"

  if [[ -t 0 ]]; then
    read -r -p "Press Enter after completing this step in the browser... "
  fi
}

echo
echo "Playit asks for tunnel details across several screens."
echo "The answers will be shown one at a time to avoid confusion."
show_playit_step 1 'Tunnel name: Encrypto VPN'
show_playit_step 2 'Tunnel type: UDP'
show_playit_step 3 'Port count: 1'
show_playit_step 4 'Acknowledge that Roblox is prohibited, then click Next.'
show_playit_step 5 'Software description: Self-hosted Encrypto VPN server for accessing my own network'
show_playit_step 6 'Usage confirmation: I will not use this tunnel for malware, abuse, or prohibited software.'
