#!/bin/sh

echo "Отключение IPv6 на интерфейсах LAN и WAN..."

# Отключаем IPv6 на интерфейсах LAN и WAN
uci set network.lan.ipv6='0'
uci set network.wan.ipv6='0'

# Отключаем делегирование префиксов на LAN
uci set network.lan.delegate='0'

# Отключаем DHCPv6 и RA на LAN
uci set dhcp.lan.dhcpv6='disabled'
uci -q delete dhcp.lan.dhcpv6
uci -q delete dhcp.lan.ra

# Отключаем odhcpd (демон IPv6/DHCPv6)
/etc/init.d/odhcpd disable
/etc/init.d/odhcpd stop

# Удаляем ULA-префикс IPv6
uci -q delete network.globals.ula_prefix

# Сохраняем и применяем изменения
uci commit network
uci commit dhcp

echo "Перезапуск сетевых служб..."
/etc/init.d/network restart
/etc/init.d/odhcpd restart

echo "IPv6 полностью отключён."
