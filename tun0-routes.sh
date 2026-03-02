#!/bin/sh
# Policy routing: dst из cidr4.txt → mark 200 → table 200 → tun0. ipset + iptables mangle.

TABLE=200
FWMARK=200
PRIO=30100
IPSET_NAME="tun0_cidr4"
CIDR_FILE="/root/cidr4.txt"
LOCKFILE="/var/run/tun0-routes.lock"

[ -z "$(ip link show tun0 2>/dev/null)" ] && { echo "tun0 не найден." >&2; exit 1; }
command -v ipset >/dev/null 2>&1 || { echo "ipset не найден." >&2; exit 1; }
command -v iptables >/dev/null 2>&1 || { echo "iptables не найден." >&2; exit 1; }

_main() {
  while ip rule del table "$TABLE" 2>/dev/null; do :; done
  ip route flush table "$TABLE" 2>/dev/null
  ip route add default dev tun0 table "$TABLE" 2>/dev/null || exit 1
  ip rule add fwmark "$FWMARK" table "$TABLE" priority "$PRIO" 2>/dev/null || exit 1

  ipset list "$IPSET_NAME" >/dev/null 2>&1 || ipset create "$IPSET_NAME" hash:net hashsize 4096 maxelem 65536 2>/dev/null || exit 1
  ipset flush "$IPSET_NAME"

  skip() { case "$1" in 0.0.0.0/0|192.168.*) return 0 ;; *) return 1 ;; esac; }
  [ -f "$CIDR_FILE" ] && [ -s "$CIDR_FILE" ] && while read -r line; do
    line=$(echo "$line" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$line" ] || skip "$line" || ipset add "$IPSET_NAME" "$line" 2>/dev/null
  done < "$CIDR_FILE"

  iptables -t mangle -D PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK" 2>/dev/null
  iptables -t mangle -D OUTPUT -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK" 2>/dev/null
  iptables -t mangle -A PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK" 2>/dev/null || exit 1
  iptables -t mangle -A OUTPUT -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK" 2>/dev/null || exit 1
}

if command -v flock >/dev/null 2>&1; then
  { flock -n 9 || exit 0; _main; } 9>"$LOCKFILE"
else
  _main
fi
