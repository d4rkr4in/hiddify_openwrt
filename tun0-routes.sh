#!/bin/sh
# Policy routing через nftables: трафик с dst из /root/cidr4.txt — в tun0.
# Один nft set, две правила (prerouting + output), один ip rule. Масштабируется на тысячи CIDR.
# Запуск: сервис (цикл раз в 30 с) + hotplug при ifup tun0; вручную: service tun0-routes start

TABLE=200
FWMARK=200
PRIO=30100
NFT_TABLE="tun0_routes"
NFT_SET="cidr4"
CIDR_FILE="/root/cidr4.txt"
LOCKFILE="/var/run/tun0-routes.lock"

# Один экземпляр: не запускать параллельно с hotplug/сервисом (flock может отсутствовать)
_run() {
if ! ip link show tun0 >/dev/null 2>&1; then
  echo "tun0 не найден, выходим." >&2
  exit 1
fi

if ! command -v nft >/dev/null 2>&1; then
  echo "nft не найден. Установите: opkg install nftables" >&2
  exit 1
fi

# Удалить старые правила: ip rule по таблице и одна по fwmark
while ip rule del table "$TABLE" 2>/dev/null; do :; done
ip rule del fwmark "$FWMARK" table "$TABLE" 2>/dev/null || true
ip route flush table "$TABLE" 2>/dev/null

# Маршрут по умолчанию в таблице — через tun0
ip route add default dev tun0 table "$TABLE" 2>/dev/null || exit 1
ip rule add fwmark "$FWMARK" table "$TABLE" priority "$PRIO" 2>/dev/null || exit 1

# nft: удалить таблицу (идемпотентно), создать заново — set, chains, rules
nft delete table ip "$NFT_TABLE" 2>/dev/null || true

nft add table ip "$NFT_TABLE" 2>/dev/null || exit 1
nft add set ip "$NFT_TABLE" "$NFT_SET" '{ type ipv4_addr; flags interval; }' 2>/dev/null || exit 1
# Цепочки: filter, hook prerouting/output, приоритет до фаервола (mangle обычно 0 или -150)
nft add chain ip "$NFT_TABLE" prerouting '{ type filter hook prerouting priority -150; }' 2>/dev/null || exit 1
nft add chain ip "$NFT_TABLE" output '{ type filter hook output priority -150; }' 2>/dev/null || exit 1
nft add rule ip "$NFT_TABLE" prerouting ip daddr @cidr4 meta mark set "$FWMARK" 2>/dev/null || exit 1
nft add rule ip "$NFT_TABLE" output ip daddr @cidr4 meta mark set "$FWMARK" 2>/dev/null || exit 1

skip_cidr() {
  case "$1" in
    0.0.0.0/0) return 0 ;;   # никогда не слать весь трафик в tun0 — риск потери доступа
    192.168.*) return 0 ;;
    *) return 1 ;;
  esac
}

# Заполнить set из cidr4.txt (батчами по 100, чтобы не упереться в лимит командной строки)
if [ -f "$CIDR_FILE" ] && [ -s "$CIDR_FILE" ]; then
  _batch=""
  _n=0
  while read -r line; do
    line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$line" ] && continue
    skip_cidr "$line" && continue
    if [ -n "$_batch" ]; then _batch="$_batch, $line"; else _batch="$line"; fi
    _n=$((_n + 1))
    if [ "$_n" -ge 100 ]; then
      nft add element ip "$NFT_TABLE" "$NFT_SET" "{ $_batch }" 2>/dev/null || true
      _batch=""; _n=0
    fi
  done < "$CIDR_FILE"
  [ -n "$_batch" ] && nft add element ip "$NFT_TABLE" "$NFT_SET" "{ $_batch }" 2>/dev/null || true
fi

exit 0
}

if command -v flock >/dev/null 2>&1; then
  { flock -n 9 || exit 0; _run; } 9>"$LOCKFILE"
else
  _run
fi
