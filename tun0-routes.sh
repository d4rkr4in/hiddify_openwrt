#!/bin/sh
# Policy routing: трафик с dst из /root/cidr4.txt — в tun0.
# Маркировка через ipset + iptables mangle (на OpenWrt часто срабатывает только так для forward).
# Один ip rule fwmark 200 → table 200 → default dev tun0.
# Запуск: сервис (цикл раз в 30 с) + hotplug при ifup tun0; вручную: service tun0-routes start

TABLE=200
FWMARK=200
PRIO=30100
IPSET_NAME="tun0_cidr4"
CIDR_FILE="/root/cidr4.txt"
LOCKFILE="/var/run/tun0-routes.lock"
IPTABLES="${IPTABLES:-/usr/sbin/iptables}"

# Один экземпляр: не запускать параллельно с hotplug/сервисом (flock может отсутствовать)
_run() {
if ! ip link show tun0 >/dev/null 2>&1; then
  echo "tun0 не найден, выходим." >&2
  exit 1
fi

if ! command -v ipset >/dev/null 2>&1; then
  echo "ipset не найден. Установите: opkg install ipset kmod-ipt-ipset" >&2
  exit 1
fi

if ! command -v iptables >/dev/null 2>&1 && [ ! -x "$IPTABLES" ]; then
  echo "iptables не найден. Установите пакет с iptables (например iptables-nft)." >&2
  exit 1
fi

_ipt() { if command -v iptables >/dev/null 2>&1; then iptables "$@"; else "$IPTABLES" "$@"; fi; }

# Удалить старые правила: ip rule по таблице и одна по fwmark
while ip rule del table "$TABLE" 2>/dev/null; do :; done
ip rule del fwmark "$FWMARK" table "$TABLE" 2>/dev/null || true
ip route flush table "$TABLE" 2>/dev/null

# Маршрут по умолчанию в таблице — через tun0
ip route add default dev tun0 table "$TABLE" 2>/dev/null || exit 1
ip rule add fwmark "$FWMARK" table "$TABLE" priority "$PRIO" 2>/dev/null || exit 1

# ipset: создать или пересоздать, заполнить из cidr4.txt
if ! ipset list "$IPSET_NAME" >/dev/null 2>&1; then
  ipset create "$IPSET_NAME" hash:net hashsize 4096 maxelem 65536 2>/dev/null || exit 1
fi
ipset flush "$IPSET_NAME"

skip_cidr() {
  case "$1" in
    0.0.0.0/0) return 0 ;;   # никогда не слать весь трафик в tun0 — риск потери доступа
    192.168.*) return 0 ;;
    *) return 1 ;;
  esac
}

if [ -f "$CIDR_FILE" ] && [ -s "$CIDR_FILE" ]; then
  while read -r line; do
    line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$line" ] && continue
    skip_cidr "$line" && continue
    ipset add "$IPSET_NAME" "$line" 2>/dev/null || true
  done < "$CIDR_FILE"
fi

# iptables mangle: маркировка по ipset (идемпотентно: удалить затем добавить)
_ipt -t mangle -D PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK" 2>/dev/null || true
_ipt -t mangle -D OUTPUT -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK" 2>/dev/null || true
_ipt -t mangle -A PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK" 2>/dev/null || exit 1
_ipt -t mangle -A OUTPUT -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK" 2>/dev/null || exit 1

exit 0
}

if command -v flock >/dev/null 2>&1; then
  { flock -n 9 || exit 0; _run; } 9>"$LOCKFILE"
else
  _run
fi
