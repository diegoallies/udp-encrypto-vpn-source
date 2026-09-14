#!/usr/bin/env bash
set -euo pipefail

ZIVPN_VERSION="1.4.9"
ZIVPN_SHA256="df6658c195882ff2f6cefb44050e8cb2c238ceb2b6e3fbefb931698f4f0519cb"
ZIVPN_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_${ZIVPN_VERSION}/udp-zivpn-linux-amd64"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run with sudo: sudo ./encrypto.sh" >&2
  exit 1
fi

for command in apt-get curl gpg openssl sha256sum systemctl useradd install; do
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

if ! command -v playit >/dev/null 2>&1; then
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    https://playit-cloud.github.io/ppa/key.gpg \
    | gpg --dearmor --batch --yes --output /etc/apt/trusted.gpg.d/playit.gpg
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/playit.gpg] https://playit-cloud.github.io/ppa/data ./" \
    > /etc/apt/sources.list.d/playit-cloud.list
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y jq playit
elif ! command -v jq >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y jq
fi

systemctl enable --now playit

echo "Encrypto VPN is listening locally on UDP 127.0.0.1:5667."

if [[ ! -s /etc/playit/playit.toml ]]; then
  echo "Playit will print a claim URL. Open it in your browser and approve this agent."
  playit setup
fi

playit_secret=$(sed -n 's/^[[:space:]]*secret_key[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' /etc/playit/playit.toml)

if [[ -z ${playit_secret} ]]; then
  echo "Could not read the Playit agent key." >&2
  exit 1
fi

playit_api() {
  local endpoint=$1
  local payload=$2

  printf 'header = "Authorization: Agent-Key %s"\n' "${playit_secret}" \
    | curl --config - --fail --silent --show-error \
      --header 'Content-Type: application/json' \
      --request POST \
      --data "${payload}" \
      "https://api.playit.gg${endpoint}"
}

tunnels_response=$(playit_api /v1/tunnels/list '{}')

if [[ $(jq -r '.status' <<<"${tunnels_response}") != "success" ]]; then
  echo "Playit could not list tunnels: ${tunnels_response}" >&2
  exit 1
fi

tunnel_id=$(jq -r 'first(.data.tunnels[]? | select(.name == "Encrypto VPN") | .id) // empty' <<<"${tunnels_response}")

if [[ -z ${tunnel_id} ]]; then
  create_payload='{"ports":{"type":"custom-udp","details":5667},"origin":{"type":"agent","data":{"agent_id":null,"config":{"fields":[{"name":"local_ip","value":"127.0.0.1"},{"name":"local_port","value":"5667"}]}}},"enabled":true,"alloc":null,"name":"Encrypto VPN","firewall_id":null}'
  create_response=$(playit_api /v1/tunnels/create "${create_payload}")

  if [[ $(jq -r '.status' <<<"${create_response}") != "success" ]]; then
    echo "Playit could not create the UDP tunnel: ${create_response}" >&2
    exit 1
  fi

  tunnel_id=$(jq -r '.data.id' <<<"${create_response}")
fi

for _ in {1..10}; do
  rundata_response=$(playit_api /v1/agents/rundata '{}')
  public_endpoint=$(jq -r --arg tunnel_id "${tunnel_id}" 'first(.data.tunnels[]? | select(.id == $tunnel_id) | .display_address) // empty' <<<"${rundata_response}")

  if [[ -n ${public_endpoint} ]]; then
    echo "Encrypto VPN public endpoint: ${public_endpoint}"
    exit 0
  fi

  sleep 2
done

echo "The Playit tunnel was created but its public endpoint is still pending."
