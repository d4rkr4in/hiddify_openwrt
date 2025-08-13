#!/bin/sh

# Название сервиса в OpenWrt
SERVICE="pbr"
TAG="check_pbr"

# Формат времени
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# Проверка состояния
if ! /etc/init.d/$SERVICE status >/dev/null 2>&1; then
    MESSAGE="$TIMESTAMP — сервис $SERVICE не запущен. Запускаю..."
    /etc/init.d/$SERVICE start
else
    MESSAGE="$TIMESTAMP — сервис $SERVICE работает."
fi

# Вывод и логирование
echo "$MESSAGE"
logger -t "$TAG" "$MESSAGE"
