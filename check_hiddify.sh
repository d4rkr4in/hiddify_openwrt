#!/bin/sh
# Проверка работы туннеля tun0; при сбое — перезапуск HiddifyCli (с cooldown).

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
TAG="check_hiddify"
RESTART_STAMP="/tmp/check_hiddify_restart.stamp"
COOLDOWN_SEC=120
CURL_MAX_TIME=10
RETRIES=3

# Проверка через tun0: несколько попыток
_ip=""
_i=0
while [ $_i -lt "$RETRIES" ]; do
  _ip=$(curl --interface tun0 -s --max-time "$CURL_MAX_TIME" ifconfig.me 2>/dev/null)
  [ -n "$_ip" ] && break
  _i=$((_i + 1))
  [ $_i -lt "$RETRIES" ] && sleep 2
done

if [ -n "$_ip" ]; then
  MESSAGE="$TIMESTAMP — tun0 работает. IP: $_ip"
  echo "$MESSAGE"
  logger -t "$TAG" "$MESSAGE"
  exit 0
fi

# Cooldown: не перезапускать чаще чем раз в COOLDOWN_SEC
_now=$(date +%s)
if [ -f "$RESTART_STAMP" ]; then
  _last=$(cat "$RESTART_STAMP" 2>/dev/null)
  if [ -n "$_last" ] && [ $((_now - _last)) -lt "$COOLDOWN_SEC" ]; then
    MESSAGE="$TIMESTAMP — нет ответа через tun0; cooldown, перезапуск пропущен (следующий через $((COOLDOWN_SEC - (_now - _last))) с)"
    logger -t "$TAG" "$MESSAGE"
    exit 0
  fi
fi

MESSAGE="$TIMESTAMP — нет ответа через tun0 после ${RETRIES} попыток. Перезапускаю HiddifyCli..."
echo "$MESSAGE"
logger -t "$TAG" "$MESSAGE"

/etc/init.d/HiddifyCli restart
_rc=$?
if [ $_rc -eq 0 ]; then
  echo "$_now" > "$RESTART_STAMP"
  MESSAGE="$TIMESTAMP — HiddifyCli перезапущен успешно"
else
  MESSAGE="$TIMESTAMP — HiddifyCli restart завершился с ошибкой (код $_rc)"
fi
logger -t "$TAG" "$MESSAGE"
