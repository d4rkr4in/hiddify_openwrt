#!/bin/bash

# Проверка на root-права
if [ "$(id -u)" -ne 0 ]; then
  echo "Этот скрипт должен быть запущен с правами root" >&2
  exit 1
fi

# Цикл запроса ссылки на подписку, пока она пуста
while true; do
  read -p "Введите ССЫЛКУ_НА_ПОДПИСКУ: " SUBSCRIPTION_LINK
  if [ -n "$SUBSCRIPTION_LINK" ]; then
    break
  fi
  echo "Ошибка: Ссылка на подписку не может быть пустой" >&2
done

echo "Начинаем установку HiddifyCli и настройку окружения..."

# Установка HiddifyCli
echo "Устанавливаем HiddifyCli..."
wget -O /tmp/HiddifyCli.tar.gz https://github.com/hiddify/hiddify-core/releases/download/v3.1.8/hiddify-cli-linux-arm64.tar.gz
tar -xvzf /tmp/HiddifyCli.tar.gz -C /tmp  
mv /tmp/HiddifyCli /usr/bin/  
chmod +x /usr/bin/HiddifyCli  

# Создание init скрипта для HiddifyCli
echo "Создаем init скрипт для HiddifyCli..."
cat > /etc/init.d/HiddifyCli <<EOF
#!/bin/sh /etc/rc.common
START=40
STOP=89
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/HiddifyCli run -c $SUBSCRIPTION_LINK -d /root/appconf.conf
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn
    procd_close_instance
}
EOF

# Создание конфигурационного файла
echo "Создаем конфигурационный файл appconf.conf..."
cat > /root/appconf.conf <<EOF
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
  "direct-dns-address": "95.85.95.85",
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
EOF

chmod 755 /etc/init.d/HiddifyCli  
service HiddifyCli start && service HiddifyCli status

# Установка Tun2Socks
echo "Устанавливаем Tun2Socks..."
wget -O tun2socks-linux-arm64.zip https://github.com/xjasonlyu/tun2socks/releases/download/v2.5.2/tun2socks-linux-arm64.zip
opkg update && opkg install unzip
unzip tun2socks-linux-arm64.zip
mv tun2socks-linux-arm64 /usr/bin/tun2socks
opkg install kmod-tun && opkg install dnsmasq-full
uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
uci commit dhcp

# Настройка сети
echo "Настраиваем сетевой интерфейс..."
cat >> /etc/config/network <<EOF
config interface 'tun0'
        option device 'tun0'
        option proto 'static'
        option ipaddr '172.16.250.1'
        option netmask '255.255.255.0'
EOF

# Настройка фаервола
echo "Настраиваем firewall..."
cat >> /etc/config/firewall <<EOF
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
EOF

# Создание init скрипта для tun2socks
echo "Создаем init скрипт для tun2socks..."
PROTO="socks5"
HOST="localhost"
PORT="12334"
PROG="/usr/bin/tun2socks"
IF="tun0"

cat > /etc/init.d/tun2socks <<EOF
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=45
STOP=89

start_service() {
    procd_open_instance
    procd_set_param command "$PROG" -device "$IF" -proxy "$PROTO"://"$HOST":"$PORT"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn
    procd_close_instance
}
EOF


chmod 755 /etc/init.d/tun2socks
service tun2socks start
service HiddifyCli enable && service tun2socks enable

# Меняем DNS в wan на Hiddify
uci set network.wan.peerdns='0'
uci set network.wan.dns='172.16.250.1'
uci commit network

# Установка PBR
echo "Устанавливаем Policy Based Routing..."
opkg install pbr luci-app-pbr
uci set pbr.config.enabled="1"
uci commit pbr
uci set dhcp.lan.force='1'
uci commit dhcp
service pbr restart && service rpcd restart

# Загрузка CIDR списка и настройка PBR
echo "Загружаем CIDR список и настраиваем PBR..."
wget -O cidr4.txt https://raw.githubusercontent.com/d4rkr4in/hiddify_openwrt/refs/heads/main/cidr4

# Добавляем правило в PBR для CIDR списка
uci add pbr policy
uci set pbr.@policy[-1].name='torrents'
uci set pbr.@policy[-1].src_port='6881-6889'
uci set pbr.@policy[-1].dest_port='6881-6889'
uci set pbr.@policy[-1].interface='wan'
uci set pbr.@policy[-1].enabled='1'

uci add pbr policy
uci set pbr.@policy[-1].name='cidr4'
uci set pbr.@policy[-1].dest_addr='file:///root/cidr4.txt'
uci set pbr.@policy[-1].interface='tun0'
uci set pbr.@policy[-1].enabled='1'

uci add pbr dns_policy
uci set pbr.@dns_policy[-1].name='dns'
uci set pbr.@dns_policy[-1].src_addr='0.0.0.0'
uci set pbr.@dns_policy[-1].dest_dns='tun0'
uci set pbr.@dns_policy[-1].enabled='1'

uci commit pbr
/etc/init.d/pbr restart

# Перезагрузка в 4 утра
echo "Добавляем ежедневную перезагрузку в 4:00 в crontab..."
CRON_JOB="0 4 * * * /sbin/reboot"
# Добавляем, если такой строки ещё нет
( crontab -l 2>/dev/null | grep -Fxq "$CRON_JOB" ) || ( crontab -l 2>/dev/null; echo "$CRON_JOB" ) | crontab -


# Перезапуск сервисов
echo "Применяем изменения и перезагружаемся..."
reboot
