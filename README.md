Ready script for complete installation Hiddify with Tun2Socks and Policy Routing rules on Openwrt Router

1. Run this command via ssh:

```opkg update && opkg install wget bash && wget --header="Cache-Control: no-cache" --header="Pragma: no-cache" -O /tmp/install.sh "https://raw.githubusercontent.com/d4rkr4in/hiddify_openwrt/main/install.sh?t=$(date +%s)" && chmod +x /tmp/install.sh && bash -x /tmp/install.sh```

2. Enter your subscription of Hiddify

3. Wait for installation

4. Ready!
