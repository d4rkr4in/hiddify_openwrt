#!/bin/sh
# Policy routing: трафик из /root/cidr4.txt направлять через tun0 (без PBR).
# Запуск: вручную или из rc.local после подъёма tun0; по cron после обновления cidr4.

TABLE=200
PRIO=30100
CIDR_FILE="/root/cidr4.txt"

if ! ip link show tun0 >/dev/null 2>&1; then
  echo "tun0 не найден, выходим." >&2
  exit 1
fi

# Удалить все правила, указывающие на нашу таблицу
while ip rule del table "$TABLE" 2>/dev/null; do :; done
ip route flush table "$TABLE" 2>/dev/null

# Маршрут по умолчанию в таблице — через tun0
ip route add default dev tun0 table "$TABLE" 2>/dev/null || exit 1

# Правила: трафик с dest в cidr4 — в таблицу TABLE.
# Не добавляем приватные/LAN и 0.0.0.0/0, чтобы не потерять доступ к роутеру.
skip_cidr() {
  case "$1" in
    0.0.0.0/0) return 0 ;;
    10.0.0.0/*|10.*) return 0 ;;
    172.16.*|172.17.*|172.18.*|172.19.*|172.2*.*|172.30.*|172.31.*) return 0 ;;
    192.168.*) return 0 ;;
    127.*) return 0 ;;
    169.254.*) return 0 ;;
    *) return 1 ;;
  esac
}
if [ -f "$CIDR_FILE" ] && [ -s "$CIDR_FILE" ]; then
  while read -r line; do
    line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$line" ] && continue
    skip_cidr "$line" && continue
    ip rule add to "$line" table "$TABLE" priority "$PRIO" 2>/dev/null || true
  done < "$CIDR_FILE"
fi

exit 0
