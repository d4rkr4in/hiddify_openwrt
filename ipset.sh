#!/bin/sh

# Имя ipset
IPSET_NAME="vpn_cidrs"

# VPN интерфейс (замените на свой)
VPN_IF="tun1"          # или tun0 для OpenVPN

# Создаём ipset (если уже есть, игнорируем)
ipset create $IPSET_NAME hash:net -exist

# Добавляем все CIDR из файла
while read cidr; do
  ipset add $IPSET_NAME $cidr -exist
done < /root/ipset.txt

# Создаём таблицу маршрутизации для VPN
# Номер таблицы 200, имя vpn
grep -q '^200 vpn' /etc/iproute2/rt_tables || echo "200 vpn" >> /etc/iproute2/rt_tables

# Настраиваем маршрут по умолчанию через VPN интерфейс
ip route flush table vpn
ip route add default dev $VPN_IF table vpn

# Создаём цепочку для маркировки пакетов
iptables -t mangle -N VPNMARK -m comment --comment "Mark VPN traffic" -j RETURN 2>/dev/null
iptables -t mangle -F VPNMARK
iptables -t mangle -A PREROUTING -m set --match-set $IPSET_NAME dst -j MARK --set-mark 0x1

# Привязываем маркировку к таблице vpn
ip rule add fwmark 0x1 table vpn pref 100

# Проверка: можно увидеть правила и маршруты
echo "IP set:"
ipset list $IPSET_NAME
echo "IP rules:"
ip rule show
echo "VPN routing table:"
ip route show table vpn
