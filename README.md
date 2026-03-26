# Bazzite Wi-Fi fix for Mercusys MU6H / Realtek 8821CU
Фикс ситуации с затычкой, которая не работает в  **Bazzite** **Realtek 8821CU**.

Фикс делался с использованием ЭйАй, так что на свой страх и риск. В моём случае все работает, счастье есть


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

## Проверка

Проверить, что драйвер поднялся:

```bash
lsmod | grep rtw_8821cu
systemctl status rtw8821cu-load.service
```
