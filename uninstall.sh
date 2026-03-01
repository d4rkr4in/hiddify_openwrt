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
service tun2socks stop 2>/dev/null || true
service HiddifyCli disable 2>/dev/null || true
service hev-socks5-tunnel disable 2>/dev/null || true
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
# Удалить правила и таблицу 200 (как в tun0-routes.sh; 254 = main — не трогать)
while ip rule del table 200 2>/dev/null; do :; done
ip route flush table 200 2>/dev/null || true
if [ -f /etc/rc.local ]; then
  sed -i '/tun0-routes\.sh/d' /etc/rc.local
fi
( crontab -l 2>/dev/null | grep -v tun0-routes.sh || true ) | crontab - 2>/dev/null || true

# --- PBR: удаление, если был установлен ранее ---
service pbr stop 2>/dev/null || true
service pbr disable 2>/dev/null || true
uci delete dhcp.lan.force 2>/dev/null || true
uci commit dhcp 2>/dev/null || true
opkg remove pbr luci-app-pbr --force-depends 2>/dev/null || true
rm -f /etc/config/pbr 2>/dev/null || true
if [ -f /etc/rc.local ]; then
  sed -i '/pbr start/d' /etc/rc.local
fi

# --- Удаление остальных пакетов из install.sh ---
echo "Удаляем пакеты: curl, nano, unzip, luci-theme-openwrt-2020, kmod-tun (если установлен)..."
opkg remove curl nano unzip luci-theme-openwrt-2020 kmod-tun 2>/dev/null || true

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
echo "  - удалены /usr/bin/HiddifyCli, hev-socks5-tunnel, tun2socks, upx, get_cidr4.sh, check_hiddify.sh, /etc/hev-socks5-tunnel.yml, пакет xz/xz-utils"
echo "  - удалены $APPCONF, $CIDR_FILE (файл подписки $SUBSCRIPTION_FILE сохранён)"
echo "  - убраны задания cron (check_hiddify, get_cidr4, reboot)"
echo "  - удалены скрипт tun0-routes.sh, правила и таблица 200, строки в rc.local и cron"
echo "  - при наличии: PBR (сервис, конфиг, пакеты) удалён"
echo "  - удалены интерфейс tun0 и зона firewall tun"
echo "  - удалены пакеты: curl, nano, unzip, luci-theme-openwrt-2020, xz-utils/xz, kmod-tun (и pbr при наличии)"
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
