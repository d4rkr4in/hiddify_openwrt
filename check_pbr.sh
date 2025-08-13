# Название сервиса в OpenWrt
SERVICE="pbr"

# Формат времени
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# Проверка состояния
if ! /etc/init.d/$SERVICE status >/dev/null 2>&1; then
    MESSAGE="$TIMESTAMP — сервис $SERVICE не запущен. Запускаю..."
    echo "$MESSAGE"
    logger -t "$SERVICE-check" "$MESSAGE"
    /etc/init.d/$SERVICE start
else
    MESSAGE="$TIMESTAMP — сервис $SERVICE работает."
    echo "$MESSAGE"
    logger -t "$SERVICE-check" "$MESSAGE"
fi
