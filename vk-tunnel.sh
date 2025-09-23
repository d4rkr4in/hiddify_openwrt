#!/bin/bash

set -e

echo "=== Обновление системы и установка базового ПО ==="
sudo apt update && sudo apt install -y wget git curl

echo "=== Установка Node.js 20.x ==="
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

echo "=== Создание папки и клонирование vk-tunnel-client ==="
mkdir -p ~/vk-proxy
cd ~/vk-proxy

# Проверяем, есть ли уже проект
if [ -d ".git" ]; then
    echo "VK Tunnel client уже клонирован, пропускаем git clone"
else
    git clone https://github.com/VKCOM/vk-tunnel-client.git .
fi

echo "=== Установка vk-tunnel глобально ==="
sudo npm install -g @vkontakte/vk-tunnel

echo "=== Запуск VK Tunnel ==="
echo "После запуска откроется ссылка для авторизации VK. Нажмите Enter после авторизации."
vk-tunnel --insecure=1 --http-protocol=https --ws-protocol=wss --host=localhost --port=80 --timeout=18000

#!/bin/bash
set -e

# Найдём бинарник vk-tunnel
VK_TUNNEL_PATH=$(which vk-tunnel || true)

if [ -z "$VK_TUNNEL_PATH" ]; then
  echo "❌ vk-tunnel не найден в PATH. Установите его или укажите путь вручную."
  exit 1
fi

echo "✅ Найден vk-tunnel: $VK_TUNNEL_PATH"

# Создаём unit-файл
SERVICE_FILE="/etc/systemd/system/vk-tunnel.service"

sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=vk-tunnel service
After=network.target

[Service]
Type=simple
ExecStart=$VK_TUNNEL_PATH --insecure=1 --http-protocol=https --ws-protocol=wss --host=localhost --port=80 --timeout=18000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "✅ Unit-файл создан: $SERVICE_FILE"

# Обновляем systemd и включаем сервис
sudo systemctl daemon-reload
sudo systemctl enable --now vk-tunnel.service

echo "✅ Сервис vk-tunnel запущен и добавлен в автозагрузку."
echo "👉 Проверить статус: sudo systemctl status vk-tunnel.service"
echo "👉 Смотреть логи: sudo journalctl -u vk-tunnel.service -f"

