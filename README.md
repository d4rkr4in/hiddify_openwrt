Ready script for complete installation Hiddify with hev-socks5-tunnel and Policy Routing rules on Openwrt Router

1. Run this command via ssh:

OpenWRT 25-
```
opkg update && opkg install curl bash && curl -fL -o /tmp/install.sh https://raw.githubusercontent.com/d4rkr4in/hiddify_openwrt/main/install.sh && chmod +x /tmp/install.sh && bash -x /tmp/install.sh
```

OpenWRT 25+
```
apk update && apk add curl bash && curl -fL -o /tmp/install.sh https://raw.githubusercontent.com/d4rkr4in/hiddify_openwrt/main/install.sh && chmod +x /tmp/install.sh && bash -x /tmp/install.sh
```

2. Enter your subscription of Hiddify

3. Wait for installation

4. Ready!
