#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAMES=(
  "rtl8821cu-wifi-fix.service"
  "rtw8821cu-load.service"
)
MODULE_NAMES=(
  "8821cu"
  "rtw_8821cu"
)
WORKDIR="/usr/local/src/rtl8821cu-driver"

if [[ $EUID -ne 0 ]]; then
  echo "Запусти скрипт через sudo: sudo bash uninstall_wifi_fix.sh" >&2
  exit 1
fi

for service in "${SERVICE_NAMES[@]}"; do
  systemctl disable --now "$service" 2>/dev/null || true
  rm -f "/etc/systemd/system/${service}"
done

systemctl daemon-reload

for module in "${MODULE_NAMES[@]}"; do
  modprobe -r "$module" 2>/dev/null || /usr/sbin/rmmod "$module" 2>/dev/null || true
done

rm -rf "$WORKDIR"

echo "Фикс удалён (сервисы и загруженные модули остановлены)."
