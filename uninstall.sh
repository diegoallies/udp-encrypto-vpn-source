#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run with sudo: sudo ./uninstall.sh" >&2
  exit 1
fi

systemctl disable --now zivpn.service 2>/dev/null || true
rm -f /etc/systemd/system/zivpn.service
rm -f /etc/sysctl.d/90-zivpn.conf
rm -f /usr/local/bin/zivpn
rm -rf /etc/zivpn
systemctl daemon-reload
sysctl --system >/dev/null

if id zivpn >/dev/null 2>&1; then
  userdel zivpn
fi

echo "ZIVPN removed."
