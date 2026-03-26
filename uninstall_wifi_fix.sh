#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="rtw8821cu-load.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

if [[ $EUID -ne 0 ]]; then
  echo "Запусти скрипт через sudo: sudo bash uninstall_wifi_fix.sh" >&2
  exit 1
fi

systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
rm -f "$SERVICE_PATH"
systemctl daemon-reload
/usr/sbin/rmmod rtw_8821cu 2>/dev/null || true

echo "Фикс удалён."
