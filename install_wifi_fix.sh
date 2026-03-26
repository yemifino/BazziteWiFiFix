#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="rtl8821cu-wifi-fix.service"
LEGACY_SERVICE_NAME="rtw8821cu-load.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
LEGACY_SERVICE_PATH="/etc/systemd/system/${LEGACY_SERVICE_NAME}"
WORKDIR="/usr/local/src/rtl8821cu-driver"
DRIVER_REPO="https://github.com/morrownr/8821cu-20210916.git"
KERNEL_VER="$(uname -r)"

log() {
  printf '[+] %s\n' "$1"
}

warn() {
  printf '[!] %s\n' "$1" >&2
}

die() {
  printf '[x] %s\n' "$1" >&2
  exit 1
}

need_root() {
  if [[ $EUID -ne 0 ]]; then
    die "Запусти скрипт через sudo: sudo bash install_wifi_fix.sh"
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

version_ge() {
  [[ "$(printf '%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ]]
}

find_existing_module() {
  local path
  for path in \
    "/lib/modules/${KERNEL_VER}/kernel/drivers/net/wireless/realtek/rtw88/rtw_8821cu.ko" \
    "/lib/modules/${KERNEL_VER}/extra/8821cu.ko" \
    "/var/lib/extra-modules/rtw_8821cu.ko" \
    "/var/lib/extra-modules/8821cu.ko"; do
    [[ -f "$path" ]] && { echo "$path"; return 0; }
  done

  find "/lib/modules/${KERNEL_VER}" /var/lib/extra-modules -type f \
    \( -name 'rtw_8821cu.ko' -o -name '8821cu.ko' \) 2>/dev/null | head -n1 || true
}

choose_module_name() {
  if modinfo rtw_8821cu >/dev/null 2>&1; then
    echo "rtw_8821cu"
    return 0
  fi

  if modinfo 8821cu >/dev/null 2>&1; then
    echo "8821cu"
    return 0
  fi

  local existing
  existing="$(find_existing_module)"
  if [[ "$existing" == *"rtw_8821cu.ko" ]]; then
    echo "rtw_8821cu"
  elif [[ "$existing" == *"8821cu.ko" ]]; then
    echo "8821cu"
  else
    echo ""
  fi
}

try_load_module() {
  local module_name="$1"
  [[ -z "$module_name" ]] && return 1

  if lsmod | grep -q "^${module_name}\\b"; then
    log "Модуль ${module_name} уже загружен."
    return 0
  fi

  if modprobe "$module_name"; then
    log "Модуль ${module_name} успешно загружен через modprobe."
    return 0
  fi

  return 1
}

ensure_build_tools_hint() {
  if ! have_cmd git || ! have_cmd make || ! have_cmd gcc; then
    warn "Не найдены git/make/gcc. Для сборки драйвера на Bazzite обычно нужно добавить инструменты разработки и kernel headers."
    warn "На rpm-ostree системах это часто делается через layering, после чего нужна перезагрузка."
  fi

  if [[ ! -d "/usr/src/kernels/${KERNEL_VER}" && ! -e "/lib/modules/${KERNEL_VER}/build" ]]; then
    warn "Не вижу headers/kernel-devel для ядра ${KERNEL_VER}. Сборка внешнего драйвера может не пройти."
  fi
}

build_external_driver() {
  ensure_build_tools_hint
  have_cmd git || die "git не установлен, поэтому скачать исходники драйвера не получится."
  have_cmd make || die "make не установлен, поэтому собрать драйвер не получится."
  have_cmd gcc || die "gcc не установлен, поэтому собрать драйвер не получится."

  log "Скачиваю исходники драйвера RTL8821CU в ${WORKDIR} ..."
  rm -rf "$WORKDIR"
  git clone --depth=1 "$DRIVER_REPO" "$WORKDIR"

  cd "$WORKDIR"
  log "Собираю и устанавливаю внешний модуль 8821cu..."
  bash ./install-driver.sh
}

cleanup_legacy_service() {
  if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${LEGACY_SERVICE_NAME}"; then
    log "Отключаю legacy-сервис ${LEGACY_SERVICE_NAME}."
    systemctl disable --now "$LEGACY_SERVICE_NAME" 2>/dev/null || true
  fi

  if [[ -f "$LEGACY_SERVICE_PATH" ]]; then
    rm -f "$LEGACY_SERVICE_PATH"
  fi
}

write_service() {
  local module_name="$1"

  cat > "$SERVICE_PATH" <<EOF2
[Unit]
Description=Load Realtek ${module_name} Wi-Fi module on boot
After=local-fs.target
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/modprobe ${module_name}
ExecStop=/usr/sbin/modprobe -r ${module_name}

[Install]
WantedBy=multi-user.target
EOF2

  cleanup_legacy_service
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME" || systemctl start "$SERVICE_NAME"
}

main() {
  need_root

  log "Ядро: ${KERNEL_VER}"
  local kernel_base="${KERNEL_VER%%-*}"

  if version_ge "$kernel_base" "6.12"; then
    log "Ядро >= 6.12, поэтому сначала пробую встроенный драйвер rtw88/rtw_8821cu."
    if try_load_module "rtw_8821cu"; then
      write_service "rtw_8821cu"
      log "Используется встроенный драйвер ядра."
    else
      warn "Встроенный драйвер не загрузился, пробую внешний 8821cu."
      build_external_driver
      depmod -a
      try_load_module "8821cu" || die "После установки внешний модуль 8821cu всё равно не загрузился."
      write_service "8821cu"
    fi
  else
    log "Ядро < 6.12, поэтому сразу пробую внешний драйвер 8821cu."
    local module_name
    module_name="$(choose_module_name)"

    if [[ -n "$module_name" ]] && try_load_module "$module_name"; then
      write_service "$module_name"
    else
      build_external_driver
      depmod -a
      try_load_module "8821cu" || die "После установки внешний модуль 8821cu всё равно не загрузился."
      write_service "8821cu"
    fi
  fi

  if have_cmd nmcli; then
    nmcli radio wifi on || true
  fi

  echo
  log "Проверка состояния:"
  lsmod | grep -E '^(rtw_8821cu|8821cu)\b' || warn "Модуль не виден в lsmod."
  systemctl --no-pager --full status "$SERVICE_NAME" || true

  echo
  log "Готово. Скрипт либо использовал встроенный драйвер, либо скачал и собрал внешний, после чего добавил автозагрузку через systemd."
}

main "$@"
