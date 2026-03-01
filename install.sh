#!/bin/sh
# Оптимизированный установщик Hiddify + OpenWrt (d4rkr4in/hiddify_openwrt)
# Изменения: обработка ошибок, идемпотентность, константы, очистка, правка путей

set -e

# --- Константы (удобно обновлять версии) ---
HIDDIFY_VER="v4.0.3"
HIDDIFY_ARCH="arm64"
HEV_TUNNEL_VER="2.14.4"
HEV_TUNNEL_ARCH="arm64"
REPO_RAW="https://raw.githubusercontent.com/d4rkr4in/hiddify_openwrt/refs/heads/main"
HEV_CONF="/etc/hev-socks5-tunnel.yml"
SUBSCRIPTION_FILE="/root/hiddify_subscription.url"
APPCONF="/root/appconf.conf"
CIDR_FILE="/root/cidr4.txt"

# --- Проверка root ---
if [ "$(id -u)" -ne 0 ]; then
  echo "Этот скрипт должен быть запущен с правами root" >&2
  exit 1
fi

# --- Очистка при выходе ---
cleanup() {
  rm -f /tmp/HiddifyCli.tar.gz /tmp/hev-socks5-tunnel-linux-arm64
}
trap cleanup EXIT

# --- Запрос ссылки на подписку ---
if [ -f "$SUBSCRIPTION_FILE" ] && [ -s "$SUBSCRIPTION_FILE" ]; then
  read -p "Найдена сохранённая ссылка. Использовать её? [Y/n]: " use_saved
  case "${use_saved:-y}" in
    [nN]|[nN][oO]) use_saved="" ;;
    *) SUBSCRIPTION_LINK=$(cat "$SUBSCRIPTION_FILE"); use_saved=1 ;;
  esac
fi
if [ -z "$use_saved" ]; then
  while true; do
    read -p "Введите ССЫЛКУ_НА_ПОДПИСКУ: " SUBSCRIPTION_LINK
    if [ -n "$SUBSCRIPTION_LINK" ]; then
      break
    fi
    echo "Ошибка: Ссылка на подписку не может быть пустой" >&2
  done
  printf '%s' "$SUBSCRIPTION_LINK" > "$SUBSCRIPTION_FILE"
fi

echo "Установка пакетов..."
opkg update -q
opkg install curl nano unzip luci-theme-openwrt-2020

# --- HiddifyCli ---
echo "Устанавливаем HiddifyCli..."
curl -fL --retry 3 --connect-timeout 10 -o /tmp/HiddifyCli.tar.gz \
  "https://github.com/hiddify/hiddify-core/releases/download/${HIDDIFY_VER}/hiddify-cli-linux-${HIDDIFY_ARCH}.tar.gz"
tar -xzf /tmp/HiddifyCli.tar.gz -C /tmp
mv /tmp/HiddifyCli /usr/bin/
chmod +x /usr/bin/HiddifyCli

cat > /etc/init.d/HiddifyCli << EOF
#!/bin/sh /etc/rc.common
START=40
STOP=89
USE_PROCD=1

start_service() {
    _sub=\$(cat $SUBSCRIPTION_FILE 2>/dev/null)
    [ -z "\$_sub" ] && return 1
    procd_open_instance
    procd_set_param command /usr/bin/HiddifyCli run -c "\$_sub" -d $APPCONF
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn
    procd_close_instance
}
EOF

# --- appconf.conf ---
echo "Создаём конфигурацию..."
cat > "$APPCONF" << 'APPCONF_EOF'
{
  "region": "other",
  "block-ads": false,
  "use-xray-core-when-possible": false,
  "execute-config-as-is": false,
  "log-level": "warn",
  "resolve-destination": false,
  "ipv6-mode": "ipv4_only",
  "remote-dns-address": "udp://1.1.1.1",
  "remote-dns-domain-strategy": "",
  "direct-dns-address": "1.1.1.1",
  "direct-dns-domain-strategy": "",
  "mixed-port": 12334,
  "tproxy-port": 12335,
  "local-dns-port": 16450,
  "tun-implementation": "gvisor",
  "mtu": 9000,
  "strict-route": true,
  "connection-test-url": "http://cp.cloudflare.com",
  "url-test-interval": 600,
  "enable-clash-api": true,
  "clash-api-port": 16756,
  "enable-tun": false,
  "enable-tun-service": false,
  "set-system-proxy": false,
  "bypass-lan": true,
  "allow-connection-from-lan": false,
  "enable-fake-dns": false,
  "enable-dns-routing": true,
  "independent-dns-cache": true,
  "rules": []
}
APPCONF_EOF

chmod 755 /etc/init.d/HiddifyCli
service HiddifyCli start
service HiddifyCli status
service HiddifyCli enable

# --- hev-socks5-tunnel (tun2socks) ---
echo "Устанавливаем hev-socks5-tunnel..."
opkg install kmod-tun
curl -fL --retry 3 --connect-timeout 10 -o /tmp/hev-socks5-tunnel-linux-arm64 \
  "https://github.com/heiher/hev-socks5-tunnel/releases/download/${HEV_TUNNEL_VER}/hev-socks5-tunnel-linux-${HEV_TUNNEL_ARCH}"
mv /tmp/hev-socks5-tunnel-linux-arm64 /usr/bin/hev-socks5-tunnel
chmod +x /usr/bin/hev-socks5-tunnel

# --- Интерфейс tun0 ---
if ! grep -q "interface 'tun0'" /etc/config/network 2>/dev/null; then
  cat >> /etc/config/network << 'NET_EOF'

config interface 'tun0'
	option device 'tun0'
	option proto 'static'
	option ipaddr '172.16.250.1'
	option netmask '255.255.255.0'
NET_EOF
fi

# --- Firewall ---
if ! grep -q "option name 'tun'" /etc/config/firewall 2>/dev/null; then
  cat >> /etc/config/firewall << 'FW_EOF'

config zone
	option name 'tun'
	option forward 'ACCEPT'
	option output 'ACCEPT'
	option input 'REJECT'
	option masq '1'
	option mtu_fix '1'
	option device 'tun0'
	option family 'ipv4'

config forwarding
	option name 'lan-tun'
	option dest 'tun'
	option src 'lan'
	option family 'ipv4'
FW_EOF
fi

# --- Конфиг и init hev-socks5-tunnel ---
echo "Создаём конфиг hev-socks5-tunnel..."
cat > "$HEV_CONF" << 'HEV_YAML_EOF'
tunnel:
  name: tun0
  mtu: 9000
  multi-queue: false
  ipv4: 172.16.250.1

socks5:
  address: 127.0.0.1
  port: 12334
  udp: 'udp'
HEV_YAML_EOF

cat > /etc/init.d/hev-socks5-tunnel << HEV_INIT_EOF
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=45
STOP=89

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/hev-socks5-tunnel $HEV_CONF
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn
    procd_close_instance
}
HEV_INIT_EOF
chmod 755 /etc/init.d/hev-socks5-tunnel
service hev-socks5-tunnel start
service hev-socks5-tunnel enable

# --- Вспомогательные скрипты ---
# Параметр ?t= обходит кэш GitHub/CDN, заголовки — просьба не отдавать кэш
_CACHE_BUST="?t=$(date +%s)"
echo "Загружаем get_cidr4.sh и check_hiddify.sh..."
wget -q --header="Cache-Control: no-cache" --header="Pragma: no-cache" \
  -O /usr/bin/get_cidr4.sh "$REPO_RAW/get_cidr4.sh$_CACHE_BUST"
wget -q --header="Cache-Control: no-cache" --header="Pragma: no-cache" \
  -O /usr/bin/check_hiddify.sh "$REPO_RAW/check_hiddify.sh$_CACHE_BUST"
chmod +x /usr/bin/get_cidr4.sh /usr/bin/check_hiddify.sh
# get_cidr4.sh по умолчанию пишет в текущую директорию — задаём абсолютный путь для cron
sed -i "s|cidr4\.txt|$CIDR_FILE|g" /usr/bin/get_cidr4.sh

# --- Crontab (без дубликатов) ---
CRON_CHECK="*/2 * * * * /usr/bin/check_hiddify.sh"
CRON_REBOOT="0 5 * * * /sbin/reboot"
CRON_CIDR="0 4 * * * /usr/bin/get_cidr4.sh"
( crontab -l 2>/dev/null | grep -v check_hiddify.sh | grep -v "get_cidr4.sh" | grep -v "0 5 \* \* \* /sbin/reboot" || true; echo "$CRON_CHECK"; echo "$CRON_REBOOT"; echo "$CRON_CIDR" ) | crontab -
echo "Cron: check_hiddify — каждые 2 мин, get_cidr4 — 04:00, reboot — 05:00 ежедневно."

# --- CIDR и PBR ---
/usr/bin/get_cidr4.sh || true

echo "Устанавливаем PBR..."
opkg install pbr luci-app-pbr
# Проверка синтаксиса init-скрипта (в некоторых сборках PBR он приходит с ошибкой)
if ! sh -n /etc/init.d/pbr 2>/dev/null; then
  echo "Ошибка синтаксиса в /etc/init.d/pbr, переустанавливаем пакет..."
  opkg install --force-reinstall pbr luci-app-pbr 2>/dev/null || true
fi
if ! sh -n /etc/init.d/pbr 2>/dev/null; then
  echo "Внимание: /etc/init.d/pbr по-прежнему с ошибкой. Проверьте версию OpenWrt и пакета pbr (opkg list-installed | grep pbr)." >&2
  echo "Варианты: обновить прошивку, переустановить вручную: opkg remove pbr luci-app-pbr && opkg install pbr luci-app-pbr" >&2
fi
# Секция pbr.config может отсутствовать, если конфиг пустой (пакет был установлен ранее без luci-app-pbr)
if ! uci get pbr.config >/dev/null 2>&1; then
  uci add pbr config
  uci rename pbr.@config[0]=config
fi
uci set pbr.config.enabled="1"
uci commit pbr
uci set dhcp.lan.force="1"
uci commit dhcp

# Удаление старых правил PBR
while uci get pbr.@policy[0] >/dev/null 2>&1; do uci delete pbr.@policy[0]; done
while uci get pbr.@dns_policy[0] >/dev/null 2>&1; do uci delete pbr.@dns_policy[0]; done

uci add pbr policy
uci set pbr.@policy[-1].name="torrents"
uci set pbr.@policy[-1].src_port="1725 6881-6889"
uci set pbr.@policy[-1].interface="wan"
uci set pbr.@policy[-1].enabled="1"

uci add pbr policy
uci set pbr.@policy[-1].name="cidr4"
uci set pbr.@policy[-1].dest_addr="file://$CIDR_FILE"
uci set pbr.@policy[-1].interface="tun0"
uci set pbr.@policy[-1].enabled="1"
uci commit pbr

# rc.local: запуск PBR после загрузки (идемпотентно)
if ! grep -q "/etc/init.d/pbr start" /etc/rc.local 2>/dev/null; then
  [ ! -f /etc/rc.local ] && echo "#!/bin/sh" > /etc/rc.local
  grep -q '^exit 0' /etc/rc.local || echo "exit 0" >> /etc/rc.local
  sed -i '/^exit 0/i (sleep 10; /etc/init.d/pbr start) \&' /etc/rc.local
fi

# --- Перезагрузка ---
if [ "$1" != "--no-reboot" ]; then
  echo "Перезагрузка через 5 сек (отмена: Ctrl+C). Для установки без перезагрузки: $0 --no-reboot"
  sleep 5
  reboot
else
  /etc/init.d/pbr start 2>/dev/null || true
  echo "Готово. Перезагрузка не выполнена (--no-reboot)."
fi
