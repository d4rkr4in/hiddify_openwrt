#!/bin/sh
# Проверка работы tun0:
# - если tun0 не работает -> останавливаем pbr, запоминаем это, перезапускаем HiddifyCli
# - если tun0 восстановился -> запускаем pbr только если ранее он был остановлен этим скриптом
# С cooldown от частых рестартов.

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
TAG="check_hiddify"

RESTART_STAMP="/tmp/check_hiddify_restart.stamp"
PBR_STOPPED_FLAG="/tmp/check_hiddify_pbr_stopped.flag"

COOLDOWN_SEC=120
CURL_MAX_TIME=10
RETRIES=3

PBR_SERVICE="/etc/init.d/pbr"
HIDDIFY_SERVICE="/etc/init.d/HiddifyCli"

log_msg() {
  echo "$1"
  logger -t "$TAG" "$1"
}

# Проверка через tun0: несколько попыток
_ip=""
_i=0
while [ "$_i" -lt "$RETRIES" ]; do
  _ip=$(curl --interface tun0 -s --max-time "$CURL_MAX_TIME" ifconfig.me 2>/dev/null)
  [ -n "$_ip" ] && break
  _i=$((_i + 1))
  [ "$_i" -lt "$RETRIES" ] && sleep 2
done

# Если tun0 работает
if [ -n "$_ip" ]; then
  log_msg "$TIMESTAMP — tun0 работает. IP: $_ip"

  # Запускаем pbr только если ранее сами его остановили
  if [ -f "$PBR_STOPPED_FLAG" ]; then
    log_msg "$TIMESTAMP — tun0 восстановлен; запускаю pbr..."
    "$PBR_SERVICE" start
    _pbr_start_rc=$?

    if [ "$_pbr_start_rc" -eq 0 ]; then
      rm -f "$PBR_STOPPED_FLAG"
      log_msg "$TIMESTAMP — pbr запущен успешно"
    else
      log_msg "$TIMESTAMP — ошибка запуска pbr (код $_pbr_start_rc)"
    fi
  fi

  exit 0
fi

# tun0 не работает -> cooldown
_now=$(date +%s)
if [ -f "$RESTART_STAMP" ]; then
  _last=$(cat "$RESTART_STAMP" 2>/dev/null)
  if [ -n "$_last" ] && [ $((_now - _last)) -lt "$COOLDOWN_SEC" ]; then
    _remain=$((COOLDOWN_SEC - (_now - _last)))
    log_msg "$TIMESTAMP — нет ответа через tun0; cooldown, действия пропущены (следующий через ${_remain} с)"
    exit 0
  fi
fi

log_msg "$TIMESTAMP — нет ответа через tun0 после ${RETRIES} попыток. Останавливаю pbr..."

"$PBR_SERVICE" stop
_pbr_rc=$?
if [ "$_pbr_rc" -eq 0 ]; then
  touch "$PBR_STOPPED_FLAG"
  log_msg "$TIMESTAMP — pbr остановлен успешно"
else
  log_msg "$TIMESTAMP — ошибка остановки pbr (код $_pbr_rc)"
fi

log_msg "$TIMESTAMP — перезапускаю HiddifyCli..."

"$HIDDIFY_SERVICE" restart
_rc=$?
if [ "$_rc" -eq 0 ]; then
  echo "$_now" > "$RESTART_STAMP"
  log_msg "$TIMESTAMP — HiddifyCli перезапущен успешно"
else
  log_msg "$TIMESTAMP — HiddifyCli restart завершился с ошибкой (код $_rc)"
fi
