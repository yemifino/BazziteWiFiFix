# Bazzite Wi-Fi fix for Mercusys MU6H / Realtek 8821CU

Этот репозиторий фиксирует ситуацию, когда в **Bazzite** после перезагрузки пропадает Wi‑Fi адаптер на чипе **Realtek 8821CU**.

## Симптомы

- адаптер виден не всегда;
- после ручной загрузки драйвера Wi‑Fi начинает работать;
- после перезагрузки проблема возвращается;
- модуль удаётся поднять командой вроде:

```bash
sudo insmod /var/lib/extra-modules/rtw_8821cu.ko
```

## Что было причиной

Проблема была не в NetworkManager, а в том, что внешний модуль **rtw_8821cu** не загружался автоматически при старте системы. Из-за этого USB Wi‑Fi адаптер оставался без драйвера до ручного `insmod`.

## Идея решения

Решение состоит из двух частей:

1. найти файл модуля `rtw_8821cu.ko`;
2. создать `systemd`-сервис, который будет выполнять `insmod` на каждом старте системы.

## Установка

Скопируй репозиторий и запусти:

```bash
sudo bash install_wifi_fix.sh
```

Скрипт:

- ищет модуль `rtw_8821cu.ko`;
- загружает его вручную;
- создаёт сервис `/etc/systemd/system/rtw8821cu-load.service`;
- включает автозапуск сервиса;
- при наличии `nmcli` включает Wi‑Fi.

## Удаление

```bash
sudo bash uninstall_wifi_fix.sh
```

## Какие команды решали проблему вручную

Базовый ручной сценарий был таким:

```bash
sudo insmod /var/lib/extra-modules/rtw_8821cu.ko
sudo tee /etc/systemd/system/rtw8821cu-load.service > /dev/null <<'SERVICE'
[Unit]
Description=Load Realtek rtw_8821cu Wi-Fi module on boot
After=local-fs.target
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/insmod /var/lib/extra-modules/rtw_8821cu.ko
ExecStop=/usr/sbin/rmmod rtw_8821cu

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable rtw8821cu-load.service
sudo systemctl start rtw8821cu-load.service
```

## Проверка

Проверить, что драйвер поднялся:

```bash
lsmod | grep rtw_8821cu
systemctl status rtw8821cu-load.service
```

## Публикация на GitHub

Локально:

```bash
git init
git add .
git commit -m "Add Bazzite Wi-Fi fix for Realtek 8821CU"
git branch -M main
git remote add origin https://github.com/USERNAME/bazzite-wifi-fix.git
git push -u origin main
```

Если хочешь, можно назвать репозиторий так:

- `bazzite-wifi-fix`
- `bazzite-rtl8821cu-fix`
- `mercusys-mu6h-bazzite-fix`

## Замечание

Скрипт рассчитан именно на сценарий, где модуль уже существует в системе, но **не поднимается автоматически**. Если самого `.ko` файла нет, сначала нужно собрать или установить драйвер отдельно.
