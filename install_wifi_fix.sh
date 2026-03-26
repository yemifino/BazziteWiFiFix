#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="rtw8821cu-load.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
MODULE_CANDIDATES=(
  "/var/lib/extra-modules/rtw_8821cu.ko"
  "/var/lib/extra-modules/8821cu.ko"
)

log() {
  printf '[+] %s\n' "$1"
}

err() {
  printf '[!] %s\n' "$1" >&2
}

if [[ $EUID -ne 0 ]]; then
  err "Запусти скрипт через sudo: sudo bash install_wifi_fix.sh"
  exit 1
fi

log "Ищу модуль Wi-Fi драйвера..."
MODULE_PATH=""
for candidate in "${MODULE_CANDIDATES[@]}"; do
  if [[ -f "$candidate" ]]; then
    MODULE_PATH="$candidate"
    break
  fi
done

if [[ -z "$MODULE_PATH" ]]; then
  MODULE_PATH="$(find /var/lib/extra-modules /lib/modules -type f \( -name 'rtw_8821cu.ko' -o -name '8821cu.ko' \) 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "$MODULE_PATH" ]]; then
  err "Файл модуля rtw_8821cu.ko не найден. Сначала положи модуль в /var/lib/extra-modules или установи его другим способом."
  exit 1
fi

log "Найден модуль: $MODULE_PATH"

if lsmod | grep -q '^rtw_8821cu'; then
  log "Модуль уже загружен."
else
  log "Загружаю модуль вручную через insmod..."
  /usr/sbin/insmod "$MODULE_PATH" || true
fi

log "Создаю systemd unit для автоматической загрузки драйвера после перезагрузки..."
cat > "$SERVICE_PATH" <<SERVICE
[Unit]
Description=Load Realtek rtw_8821cu Wi-Fi module on boot
After=local-fs.target
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/insmod $MODULE_PATH
ExecStop=/usr/sbin/rmmod rtw_8821cu

[Install]
WantedBy=multi-user.target
SERVICE

log "Обновляю systemd и включаю сервис..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME" || systemctl start "$SERVICE_NAME"

if command -v nmcli >/dev/null 2>&1; then
  log "Включаю Wi-Fi через NetworkManager..."
  nmcli radio wifi on || true
fi

log "Готово. Проверяю состояние:"
lsmod | grep -E '^rtw_8821cu' || err "Модуль пока не виден в lsmod, проверь journalctl -u $SERVICE_NAME"
systemctl --no-pager --full status "$SERVICE_NAME" || true

echo
echo "Фикс установлен. После следующей перезагрузки модуль должен подниматься автоматически."
