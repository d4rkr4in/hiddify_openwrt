#!/bin/sh

# Название сервиса в OpenWrt
SERVICE="pbr"

# Проверка состояния
if ! /etc/init.d/$SERVICE status >/dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') — сервис $SERVICE не запущен. Запускаю..."
    /etc/init.d/$SERVICE start
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') — сервис $SERVICE работает."
fi
