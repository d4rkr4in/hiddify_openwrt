#!/bin/sh

# Use curl via tun0 to get IP from ifconfig.me
IP=$(curl --interface tun0 -s --max-time 10 ifconfig.me)

# If curl fails or returns empty, restart services
if [ -z "$IP" ]; then
  echo "No response via tun0. Restarting HiddifyCli and Tun2Socks..."
  logger -t check_hiddify "No response via tun0. Restarting HiddifyCli and Tun2Socks..."
  /etc/init.d/HiddifyCli restart
  /etc/init.d/tun2socks restart
else
  echo "tun0 is working. IP: $IP"
  logger -t check_hiddify "tun0 is working. IP: $IP"
fi
