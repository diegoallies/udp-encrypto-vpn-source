#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run with sudo: sudo ./encrypto-uninstall.sh" >&2
  exit 1
fi

systemctl disable --now encrypto-vpn.service 2>/dev/null || true
rm -f /etc/systemd/system/encrypto-vpn.service
rm -f /etc/sysctl.d/90-encrypto-vpn.conf
rm -f /usr/local/bin/encrypto-vpn
rm -rf /etc/encrypto-vpn
systemctl daemon-reload
sysctl --system >/dev/null

if id encrypto-vpn >/dev/null 2>&1; then
  userdel encrypto-vpn
fi

echo "Encrypto VPN removed."
