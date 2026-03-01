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
service tun2socks stop 2>/dev/null || true
service HiddifyCli disable 2>/dev/null || true
service tun2socks disable 2>/dev/null || true
# Принудительно завершаем процессы (иначе rm даёт "Stale file handle" / "Text file busy")
killall HiddifyCli 2>/dev/null || true
killall tun2socks 2>/dev/null || true
sleep 2

# --- Удаление init-скриптов ---
echo "Удаляем init-скрипты..."
rm -f /etc/init.d/HiddifyCli
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
_rm_retry /usr/bin/tun2socks || echo "  Предупреждение: не удалось удалить /usr/bin/tun2socks" >&2
rm -f /usr/bin/get_cidr4.sh /usr/bin/check_hiddify.sh

# --- Удаление конфигов и данных в /root ---
echo "Удаляем конфигурации..."
rm -f "$APPCONF"
rm -f "$SUBSCRIPTION_FILE"
rm -f "$CIDR_FILE"

# --- Удаление заданий cron ---
echo "Удаляем задания cron..."
( crontab -l 2>/dev/null | grep -v check_hiddify.sh | grep -v "get_cidr4.sh" | grep -v "0 5 \* \* \* /sbin/reboot" || true ) | crontab - 2>/dev/null || true

# --- Удаление строки PBR из rc.local ---
echo "Удаляем запуск PBR из rc.local..."
if [ -f /etc/rc.local ]; then
  sed -i '/pbr start/d' /etc/rc.local
fi

# --- PBR: удаление правил и отключение ---
echo "Отключаем PBR и удаляем правила..."
if [ -f /etc/config/pbr ]; then
  uci set pbr.config.enabled="0" 2>/dev/null || true
  uci commit pbr 2>/dev/null || true
  # удалить все policy (в т.ч. torrents и cidr4)
  while uci get pbr.@policy[0] >/dev/null 2>&1; do
    uci delete pbr.@policy[0]
  done
  while uci get pbr.@dns_policy[0] >/dev/null 2>&1; do
    uci delete pbr.@dns_policy[0]
  done
  uci commit pbr 2>/dev/null || true
fi
# вернуть dhcp.lan.force (убрать принудительную перезапись)
uci delete dhcp.lan.force 2>/dev/null || true
uci commit dhcp 2>/dev/null || true

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

# --- Удаление пакетов (опционально) ---
REMOVE_PACKAGES=0
for arg in "$@"; do
  [ "$arg" = "--remove-packages" ] && REMOVE_PACKAGES=1
done
if [ "$REMOVE_PACKAGES" = "1" ]; then
  echo "Удаляем пакеты PBR и опционально kmod-tun..."
  opkg remove --autoremove pbr luci-app-pbr 2>/dev/null || true
  # kmod-tun может использоваться другими — удаляем только если не нужен
  opkg remove kmod-tun 2>/dev/null || true
fi

echo ""
echo "=== Удаление завершено ==="
echo "Сделано:"
echo "  - остановлены и удалены сервисы HiddifyCli, tun2socks"
echo "  - удалены /usr/bin/HiddifyCli, tun2socks, get_cidr4.sh, check_hiddify.sh"
echo "  - удалены $APPCONF, $SUBSCRIPTION_FILE, $CIDR_FILE"
echo "  - убраны задания cron (check_hiddify, get_cidr4, reboot)"
echo "  - убрана строка PBR из rc.local"
echo "  - отключён PBR и удалены его правила"
echo "  - удалены интерфейс tun0 и зона firewall tun"
if [ "$REMOVE_PACKAGES" = "1" ]; then
  echo "  - удалены пакеты pbr, luci-app-pbr (и при возможности kmod-tun)"
fi
echo ""
echo "Пакеты curl, nano, unzip, luci-theme-openwrt-2020 не удалялись."
echo "Чтобы удалить и их: opkg remove curl nano unzip luci-theme-openwrt-2020"
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
