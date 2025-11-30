#!/bin/sh

# Формат времени
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
TAG="check_hiddify"

# Получаем IP через tun0
IP=$(curl --interface tun0 -s --max-time 10 ifconfig.me)

# Проверка результата
if [ -z "$IP" ]; then
    MESSAGE="$TIMESTAMP — нет ответа через tun0. Перезапускаю HiddifyCli..."
    /etc/init.d/HiddifyCli restart
else
    MESSAGE="$TIMESTAMP — tun0 работает. IP: $IP"
fi

# Вывод и логирование
echo "$MESSAGE"
logger -t "$TAG" "$MESSAGE"
