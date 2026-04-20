#!/bin/sh
# Установщик Hiddify + OpenWrt с маршрутизацией через PBR (mossdef-org/pbr)
# Отличие от install.sh: вместо tun0-routes.sh используется пакет pbr + luci-app-pbr

set -e

# --- Совместимость пакетного менеджера: opkg -> apk ---
opkg() {
  _opkg_bin="$(command -v opkg 2>/dev/null || true)"
  if [ -n "$_opkg_bin" ] && [ "${_opkg_bin#*/}" != "$_opkg_bin" ]; then
    "$_opkg_bin" "$@"
    return $?
  fi

  if ! command -v apk >/dev/null 2>&1; then
    echo "Ошибка: не найден ни opkg, ни apk" >&2
    return 127
  fi

  _op="$1"
  shift || true
  case "$_op" in
    install) apk add "$@" ;;
    remove) apk del "$@" ;;
    update) apk update "$@" ;;
    *)
      echo "Ошибка: неподдерживаемая команда opkg для apk-wrapper: $_op" >&2
      return 1
      ;;
  esac
}

# --- Логирование ---
LOG_FILE="/tmp/hiddify-install.log"
STEP=0

ts() { date '+%H:%M:%S'; }
log_line() {
  _lvl="$1"
  shift
  printf '%s [%s] %s\n' "$(ts)" "$_lvl" "$*" | tee -a "$LOG_FILE"
}
step() {
  _xtrace=0
  case "$-" in
    *x*) _xtrace=1; set +x ;;
  esac

  STEP=$((STEP + 1))
  if [ -t 1 ]; then
    printf '\n\033[1;36m==== [%02d] %s ====\033[0m\n' "$STEP" "$*" | tee -a "$LOG_FILE"
  else
    printf '\n==== [%02d] %s ====\n' "$STEP" "$*" | tee -a "$LOG_FILE"
  fi

  [ "$_xtrace" -eq 1 ] && set -x
}
info() { log_line INFO "$*"; }
success() { log_line OK "$*"; }
warn() { log_line WARN "$*" >&2; }

# --- Версии (обновлять здесь) ---
HIDDIFY_VER="4.0.3"
HEV_TUNNEL_VER="2.14.4"
PBR_VER="1.2.2-6"
UPX_VER="4.2.4"

# --- Остальные константы ---
REPO_RAW="https://raw.githubusercontent.com/d4rkr4in/hiddify_openwrt/refs/heads/main"
HEV_CONF="/etc/hev-socks5-tunnel.yml"
SUBSCRIPTION_FILE="/root/hiddify_subscription.url"
APPCONF="/root/appconf.conf"
CIDR_FILE="/root/cidr4.txt"

# --- Загрузки: общие параметры curl и проверка файла ---
CURL_OPTS="--retry 10 --connect-timeout 15 -fL"
check_download() {
  [ -n "$1" ] && [ -s "$1" ] || { log_line ERR "Загрузка не удалась или файл пустой: $1" >&2; exit 1; }
}

# --- Проверка root ---
if [ "$(id -u)" -ne 0 ]; then
  log_line ERR "Этот скрипт должен быть запущен с правами root" >&2
  exit 1
fi

echo "" > "$LOG_FILE"
info "Лог установки: $LOG_FILE"

# --- Очистка при выходе ---
cleanup() {
  rm -f /tmp/HiddifyCli.tar.gz /tmp/hev-socks5-tunnel-linux-arm64
  rm -f /tmp/upx-*-arm64_linux.tar.xz
  rm -f /tmp/pbr-*.ipk /tmp/luci-app-pbr-*.ipk
  rm -rf /tmp/upx-*-arm64_linux
}
trap cleanup EXIT

# --- Проверка формата ссылки (https://домен/сегмент1/сегмент2[, #фрагмент]) ---
check_subscription_link() {
  case "$1" in
    https://*/*/*) return 0 ;;
    https://*/*/*#*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Запрос ссылки на подписку ---
if [ -f "$SUBSCRIPTION_FILE" ] && [ -s "$SUBSCRIPTION_FILE" ]; then
  read -p "Найдена сохранённая ссылка. Использовать её? [Y/n]: " use_saved
  case "${use_saved:-y}" in
    [nN]|[nN][oO]) use_saved="" ;;
    *) SUBSCRIPTION_LINK=$(cat "$SUBSCRIPTION_FILE"); use_saved=1 ;;
  esac
  if [ -n "$use_saved" ] && ! check_subscription_link "$SUBSCRIPTION_LINK"; then
    echo "Ошибка: сохранённая ссылка неверного формата (ожидается https://домен/сегмент1/сегмент2)" >&2
    use_saved=""
  fi
fi
if [ -z "$use_saved" ]; then
  while true; do
    read -p "Введите ССЫЛКУ_НА_ПОДПИСКУ: " SUBSCRIPTION_LINK
    if [ -z "$SUBSCRIPTION_LINK" ]; then
      echo "Ошибка: Ссылка на подписку не может быть пустой" >&2
      continue
    fi
    if check_subscription_link "$SUBSCRIPTION_LINK"; then
      break
    fi
    echo "Ошибка: неверный формат. Пример: https://pvs77.ru/xxx/xxx" >&2
  done
  printf '%s' "$SUBSCRIPTION_LINK" > "$SUBSCRIPTION_FILE"
fi

step "Установка базовых пакетов"
opkg install curl unzip xz-utils kmod-tun https-dns-proxy luci-app-https-dns-proxy luci-theme-openwrt-2020
command -v xz >/dev/null 2>&1 || opkg install xz 2>/dev/null || true
/etc/init.d/https-dns-proxy enable
success "Базовые пакеты установлены"

# --- UPX (для сжатия HiddifyCli), если доступен xz ---
USE_UPX=0
if command -v xz >/dev/null 2>&1; then
  step "Установка UPX (опционально)"
  info "Пробуем установить UPX ${UPX_VER}"
  _upx_arc="/tmp/upx-${UPX_VER}-arm64_linux.tar.xz"
  if curl $CURL_OPTS -o "$_upx_arc" "https://github.com/upx/upx/releases/download/v${UPX_VER}/upx-${UPX_VER}-arm64_linux.tar.xz" && \
     [ -s "$_upx_arc" ] && \
     xz -dc "$_upx_arc" | tar -xf - -C /tmp && \
     [ -f "/tmp/upx-${UPX_VER}-arm64_linux/upx" ]; then
    mv "/tmp/upx-${UPX_VER}-arm64_linux/upx" /usr/bin/upx
    chmod +x /usr/bin/upx
    USE_UPX=1
  else
    warn "UPX не установлен (нет xz или ошибка загрузки), HiddifyCli будет без сжатия."
  fi
else
  warn "xz не найден, пропускаем UPX. HiddifyCli будет без сжатия."
fi

# --- HiddifyCli ---
step "Установка HiddifyCli"
curl $CURL_OPTS -o /tmp/HiddifyCli.tar.gz \
  "https://github.com/hiddify/hiddify-core/releases/download/v${HIDDIFY_VER}/hiddify-cli-linux-arm64.tar.gz"
check_download /tmp/HiddifyCli.tar.gz
tar -xzf /tmp/HiddifyCli.tar.gz -C /tmp
[ -f /tmp/HiddifyCli ] || { echo "Ошибка: HiddifyCli не найден в архиве" >&2; exit 1; }
[ "$USE_UPX" = "1" ] && command -v upx >/dev/null 2>&1 && upx -1 /tmp/HiddifyCli 2>/dev/null || true
mv /tmp/HiddifyCli /usr/bin/
chmod +x /usr/bin/HiddifyCli

cat > /etc/init.d/HiddifyCli << EOF
#!/bin/sh /etc/rc.common
START=15
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

# --- appconf.conf (оптимизировано под OpenWrt: меньше логов, реже проверки, безопасный MTU) ---
step "Настройка HiddifyCli"
info "Создаём appconf.conf"
cat > "$APPCONF" << 'APPCONF_EOF'
{
  "region": "other",
  "block-ads": false,
  "use-xray-core-when-possible": true,
  "execute-config-as-is": false,
  "log-level": "error",
  "resolve-destination": false,
  "ipv6-mode": "ipv4_only",
  "remote-dns-address": "udp://1.1.1.1",
  "remote-dns-domain-strategy": "",
  "direct-dns-address": "https://1.1.1.1/dns-query",
  "direct-dns-domain-strategy": "",
  "mixed-port": 12334,
  "tproxy-port": 12335,
  "local-dns-port": 16450,
  "tun-implementation": "gvisor",
  "mtu": 1400,
  "strict-route": true,
  "connection-test-url": "http://cp.cloudflare.com",
  "url-test-interval": 900,
  "enable-clash-api": false,
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
success "HiddifyCli установлен и включён"

# --- hev-socks5-tunnel (tun2socks) ---
step "Установка hev-socks5-tunnel"
curl $CURL_OPTS -o /tmp/hev-socks5-tunnel-linux-arm64 \
  "https://github.com/heiher/hev-socks5-tunnel/releases/download/${HEV_TUNNEL_VER}/hev-socks5-tunnel-linux-arm64"
check_download /tmp/hev-socks5-tunnel-linux-arm64
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

# --- Удаление интерфейса wan6 (если есть) ---
if uci get network.wan6 >/dev/null 2>&1; then
  uci delete network.wan6
  uci commit network
fi

# --- LAN: отключаем Local IPv6 DNS server ---
if uci get dhcp.lan >/dev/null 2>&1; then
  # На разных версиях OpenWrt используется ra_dns или dns_service.
  uci set dhcp.lan.ra_dns='0' 2>/dev/null || true
  uci set dhcp.lan.dns_service='0' 2>/dev/null || true
  uci commit dhcp 2>/dev/null || true
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

# --- Guest -> tun (если зона guest есть) ---
if [ "$(uci get firewall.guest 2>/dev/null)" = "zone" ] && ! grep -q "option name 'guest-tun'" /etc/config/firewall 2>/dev/null; then
  uci set firewall.guest_tun="forwarding"
  uci set firewall.guest_tun.name="guest-tun"
  uci set firewall.guest_tun.src="guest"
  uci set firewall.guest_tun.dest="tun"
  uci set firewall.guest_tun.family="ipv4"
  uci commit firewall
  info "Добавлено правило firewall: guest -> tun"
fi

# --- Конфиг и init hev-socks5-tunnel ---
step "Настройка сети, firewall и tun"
info "Создаём конфиг hev-socks5-tunnel"
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
START=20
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
success "hev-socks5-tunnel установлен и включён"

# --- Вспомогательные скрипты ---
step "Вспомогательные скрипты и cron"
info "Загружаем get_cidr4.sh и check_hiddify.sh"
curl $CURL_OPTS -o /usr/bin/get_cidr4.sh "$REPO_RAW/get_cidr4.sh"
check_download /usr/bin/get_cidr4.sh
curl $CURL_OPTS -o /usr/bin/check_hiddify.sh "$REPO_RAW/check_hiddify.sh"
check_download /usr/bin/check_hiddify.sh
chmod +x /usr/bin/get_cidr4.sh /usr/bin/check_hiddify.sh
sed -i "s|cidr4\.txt|$CIDR_FILE|g" /usr/bin/get_cidr4.sh

# --- Crontab (без дубликатов) ---
CRON_CHECK="*/2 * * * * /usr/bin/check_hiddify.sh"
CRON_REBOOT="0 5 * * * /sbin/reboot"
CRON_CIDR="0 4 * * * /usr/bin/get_cidr4.sh && /etc/init.d/pbr restart"
( crontab -l 2>/dev/null | grep -v check_hiddify.sh | grep -v "get_cidr4.sh" | grep -v "0 5 \* \* \* /sbin/reboot" || true; echo "$CRON_CHECK"; echo "$CRON_REBOOT"; echo "$CRON_CIDR" ) | crontab -
info "Cron: check_hiddify — каждые 2 мин, get_cidr4 + restart PBR — 04:00, reboot — 05:00."

# --- CIDR: формируем список для PBR ---
/usr/bin/get_cidr4.sh || true

# --- Установка PBR (mossdef-org) и настройка маршрутизации через tun0 ---
step "Установка и настройка PBR"
info "Устанавливаем PBR и luci-app-pbr"
curl $CURL_OPTS -o /tmp/pbr.ipk "https://github.com/mossdef-org/pbr/releases/download/v${PBR_VER}/pbr-${PBR_VER}_openwrt-24.10_all.ipk"
check_download /tmp/pbr.ipk
curl $CURL_OPTS -o /tmp/luci-app-pbr.ipk "https://github.com/mossdef-org/luci-app-pbr/releases/download/v${PBR_VER}/luci-app-pbr-${PBR_VER}_openwrt-24.10_all.ipk"
check_download /tmp/luci-app-pbr.ipk
opkg install /tmp/pbr.ipk /tmp/luci-app-pbr.ipk

info "Настраиваем PBR (интерфейс tun0, CIDR: $CIDR_FILE, исключение портов 6881-6889, 27015-27050)"
info "Очищаем все правила PBR (policy, dns_policy, include)"
while uci delete pbr.@policy[0] 2>/dev/null; do :; done
while uci delete pbr.@dns_policy[0] 2>/dev/null; do :; done
while uci delete pbr.@include[0] 2>/dev/null; do :; done
uci commit pbr 2>/dev/null || true

if ! uci get pbr.config >/dev/null 2>&1; then
  uci set pbr.config=config
fi
uci set pbr.config.enabled='1'
uci delete pbr.config.supported_interface 2>/dev/null || true

# Политика 1: порты 6881-6889 и 27015-27050 — всегда через WAN (выше tun0_cidr4, чтобы обрабатывалась первой).
POLICY_WAN=$(uci add pbr policy)
uci set pbr."$POLICY_WAN".name='wan_ports'
uci set pbr."$POLICY_WAN".interface='wan'
uci set pbr."$POLICY_WAN".dest_port='6881-6889 27015-27050'

# Политика 2: трафик к адресам из cidr4.txt — через tun0.
# chain=output: только трафик с роутера; трафик клиентов (forward) не трогаем.
POLICY_SECTION=$(uci add pbr policy)
uci set pbr."$POLICY_SECTION".name='tun0_cidr4'
uci set pbr."$POLICY_SECTION".interface='tun0'
uci set pbr."$POLICY_SECTION".dest_addr="file://$CIDR_FILE"
uci commit pbr

# PBR запускается последним (START=100), чтобы tun0 уже был поднят
sed -i 's/^START=.*/START=100/' /etc/init.d/pbr 2>/dev/null || true
service pbr enable
success "PBR установлен. Маршрутизация по списку CIDR через tun0"

# --- DNS на WAN: 1.1.1.1 ---
if uci get network.wan >/dev/null 2>&1; then
  uci set network.wan.peerdns='0'
  uci delete network.wan.dns 2>/dev/null || true
  uci add_list network.wan.dns='1.1.1.1'
  uci commit network
fi

# --- Очистка всех DNS forwards в dnsmasq перед https-dns-proxy ---
if uci get dhcp.@dnsmasq[0] >/dev/null 2>&1; then
  i=0
  while uci get dhcp.@dnsmasq[$i] >/dev/null 2>&1; do
    uci -q delete dhcp.@dnsmasq[$i].server
    i=$((i + 1))
  done
  uci commit dhcp
fi

# --- Перезапуск network ---
step "Завершение установки"
success "Установка завершена успешно"
info "Перезагрузка через 5 сек (отмена: Ctrl+C)"
sleep 5
reboot
