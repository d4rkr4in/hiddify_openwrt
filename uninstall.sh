#!/bin/sh
# Полное удаление установки Hiddify + OpenWrt (обратный скрипт к install.sh)
# Запуск: ./uninstall.sh [--remove-packages] [--no-reboot]

set -e

SUBSCRIPTION_FILE="/root/hiddify_subscription.url"
APPCONF="/root/appconf.conf"
CIDR_FILE="/root/cidr4.txt"

if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите скрипт с правами root" >&2
  exit 1
fi

echo "=== Удаление Hiddify и связанных компонентов ==="

# --- Остановка и отключение сервисов ---
echo "Останавливаем сервисы..."
service HiddifyCli stop 2>/dev/null || true
service hev-socks5-tunnel stop 2>/dev/null || true
service tun0-routes stop 2>/dev/null || true
service tun2socks stop 2>/dev/null || true
service HiddifyCli disable 2>/dev/null || true
service hev-socks5-tunnel disable 2>/dev/null || true
service tun0-routes disable 2>/dev/null || true
service tun2socks disable 2>/dev/null || true
# Принудительно завершаем процессы (иначе rm даёт "Stale file handle" / "Text file busy")
killall HiddifyCli 2>/dev/null || true
killall hev-socks5-tunnel 2>/dev/null || true
killall tun2socks 2>/dev/null || true
sleep 2

# --- Удаление init-скриптов ---
echo "Удаляем init-скрипты..."
rm -f /etc/init.d/HiddifyCli
rm -f /etc/init.d/hev-socks5-tunnel
rm -f /etc/init.d/tun0-routes
rm -f /etc/hotplug.d/iface/99-tun0-routes
rm -f /etc/init.d/tun2socks

# --- Удаление бинарников и скриптов ---
# Удаление с повтором: после остановки процесса ядро может ещё держать file handle
echo "Удаляем бинарники и скрипты..."
_rm_retry() {
  _f="$1"; _n=0
  while [ $_n -lt 3 ]; do
    rm -f "$_f" 2>/dev/null && return 0
    _n=$((_n + 1)); sleep 1
  done
  return 1
}
_rm_retry /usr/bin/HiddifyCli || echo "  Предупреждение: не удалось удалить /usr/bin/HiddifyCli (перезагрузка и повторный uninstall помогут)" >&2
_rm_retry /usr/bin/hev-socks5-tunnel || echo "  Предупреждение: не удалось удалить /usr/bin/hev-socks5-tunnel" >&2
_rm_retry /usr/bin/tun2socks || echo "  Предупреждение: не удалось удалить /usr/bin/tun2socks" >&2
rm -f /usr/bin/upx
rm -f /usr/bin/get_cidr4.sh /usr/bin/check_hiddify.sh
rm -f /etc/hev-socks5-tunnel.yml
opkg remove xz-utils 2>/dev/null || opkg remove xz 2>/dev/null || true

# --- Удаление конфигов и данных в /root ---
echo "Удаляем конфигурации..."
rm -f "$APPCONF"
# Файл подписки не удаляем — можно использовать при повторной установке
rm -f "$CIDR_FILE"
[ -d /overlay/upper/usr/share/hiddify ] && rm -rf /overlay/upper/usr/share/hiddify

# --- Удаление заданий cron ---
echo "Удаляем задания cron..."
( crontab -l 2>/dev/null | grep -v check_hiddify.sh | grep -v "get_cidr4.sh" | grep -v "tun0-routes.sh" | grep -v "0 5 \* \* \* /sbin/reboot" || true ) | crontab - 2>/dev/null || true

# --- Удаление маршрутизации tun0 (скрипт + правила) ---
echo "Удаляем скрипт tun0-routes и правила маршрутизации..."
_rm_retry /usr/bin/tun0-routes.sh || true
rm -f /overlay/upper/usr/bin/tun0-routes.sh 2>/dev/null || true
# Удалить ip rule, таблицу 200, iptables mangle и ipset (маршрутизация tun0); nft — при наличии (старые установки)
while ip rule del table 200 2>/dev/null; do :; done
ip rule del fwmark 200 table 200 2>/dev/null || true
ip route flush table 200 2>/dev/null || true
nft delete table ip tun0_routes 2>/dev/null || true
iptables -t mangle -D PREROUTING -m set --match-set tun0_cidr4 dst -j MARK --set-mark 200 2>/dev/null || true
iptables -t mangle -D OUTPUT -m set --match-set tun0_cidr4 dst -j MARK --set-mark 200 2>/dev/null || true
ipset destroy tun0_cidr4 2>/dev/null || true
if [ -f /etc/rc.local ]; then
  sed -i '/tun0-routes\.sh/d' /etc/rc.local
fi
( crontab -l 2>/dev/null | grep -v tun0-routes.sh || true ) | crontab - 2>/dev/null || true

# --- PBR: полное удаление (сервис, конфиг, сгенерированные файлы, пакеты) ---
echo "Удаляем PBR..."
service pbr stop 2>/dev/null || true
service pbr disable 2>/dev/null || true
killall pbr 2>/dev/null || true
sleep 1
# Сгенерированные nft-файлы и рантайм
rm -f /var/run/pbr.nft 2>/dev/null || true
rm -f /usr/share/nftables.d/ruleset-post/30-pbr.nft 2>/dev/null || true
# Конфиг UCI
rm -f /etc/config/pbr 2>/dev/null || true
# Откат опции dhcp, которую мог требовать PBR
uci delete dhcp.lan.force 2>/dev/null || true
uci commit dhcp 2>/dev/null || true
# Сначала luci-app-pbr, затем pbr
opkg remove luci-app-pbr --force-depends 2>/dev/null || true
opkg remove pbr --force-depends 2>/dev/null || true
if [ -f /etc/rc.local ]; then
  sed -i '/pbr start/d' /etc/rc.local
fi
echo "  PBR удалён."

# --- Удаление остальных пакетов из install.sh ---
echo "Удаляем пакеты: curl, nano, unzip, luci-theme-openwrt-2020, kmod-tun, ipset, kmod-ipt-ipset..."
opkg remove curl nano unzip luci-theme-openwrt-2020 kmod-tun nftables ipset kmod-ipt-ipset 2>/dev/null || true

# --- Удаление интерфейса tun0 из network ---
echo "Удаляем интерфейс tun0 из network..."
if uci get network.tun0 >/dev/null 2>&1; then
  uci delete network.tun0
  uci commit network
fi

# --- Удаление зоны tun и forwarding lan-tun из firewall ---
echo "Удаляем зону tun и forwarding из firewall..."
# удалить зону с name='tun'
i=0
while uci get firewall.@zone[$i] >/dev/null 2>&1; do
  if [ "$(uci get firewall.@zone[$i].name 2>/dev/null)" = "tun" ]; then
    uci delete firewall.@zone[$i]
    uci commit firewall
    break
  fi
  i=$((i + 1))
done
# удалить forwarding lan-tun
i=0
while uci get firewall.@forwarding[$i] >/dev/null 2>&1; do
  if [ "$(uci get firewall.@forwarding[$i].name 2>/dev/null)" = "lan-tun" ]; then
    uci delete firewall.@forwarding[$i]
    uci commit firewall
    break
  fi
  i=$((i + 1))
done

echo ""
echo "=== Удаление завершено ==="
echo "Сделано:"
echo "  - остановлены и удалены сервисы HiddifyCli, hev-socks5-tunnel, tun2socks"
echo "  - удалены HiddifyCli, hev-socks5-tunnel, tun2socks, upx, get_cidr4.sh, check_hiddify.sh, /etc/hev-socks5-tunnel.yml, пакет xz/xz-utils"
echo "  - удалены $APPCONF, $CIDR_FILE (файл подписки $SUBSCRIPTION_FILE сохранён)"
echo "  - убраны задания cron (check_hiddify, get_cidr4, reboot)"
echo "  - удалены скрипт tun0-routes.sh, сервис и hotplug, ip rule/таблица 200, iptables mangle, ipset; при наличии — nft table tun0_routes"
echo "  - при наличии: PBR полностью удалён (сервис, конфиг, nft-файлы, luci-app-pbr, pbr)"
echo "  - удалены интерфейс tun0 и зона firewall tun"
echo "  - удалены пакеты: curl, nano, unzip, luci-theme-openwrt-2020, xz-utils/xz, kmod-tun, ipset, kmod-ipt-ipset (и pbr при наличии)"
echo ""

# --- Перезагрузка ---
REBOOT=1
for arg in "$@"; do
  [ "$arg" = "--no-reboot" ] && REBOOT=0
done
if [ "$REBOOT" = "1" ]; then
  echo "Перезагрузка через 5 сек (Ctrl+C — отмена)..."
  sleep 5
  reboot
else
  echo "Перезагрузка не выполнена (--no-reboot). Рекомендуется перезагрузить роутер вручную."
fi
