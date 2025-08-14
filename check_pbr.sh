#!/bin/sh
# check_pbr_and_fw4.sh
# Проверка pbr и наличия правил в nft fw4 с выводом и логированием

TABLE="inet fw4"
CHAIN_PATTERN="pbr_"
PBR_SERVICE="pbr"

log() {
    echo "$1"
    logger -t check_pbr "$1"
}

# 1. Проверка запущен ли pbr
if ! /etc/init.d/$PBR_SERVICE status 2>/dev/null | grep -q "running"; then
    log "Сервис $PBR_SERVICE не запущен — перезапуск..."
    ( sleep 2; /etc/init.d/$PBR_SERVICE restart && log "Сервис $PBR_SERVICE перезапущен" ) &
    exit 0
else
    log "Сервис $PBR_SERVICE запущен"
fi

# 2. Проверка наличия таблицы fw4
if ! nft list table $TABLE >/dev/null 2>&1; then
    log "Таблица $TABLE не найдена — перезапуск $PBR_SERVICE..."
    ( sleep 2; /etc/init.d/$PBR_SERVICE restart && log "Сервис $PBR_SERVICE перезапущен" ) &
    exit 0
else
    log "Таблица $TABLE существует"
fi

# 3. Проверка наличия цепочек pbr
if ! nft list table $TABLE | grep -q "$CHAIN_PATTERN"; then
    log "В $TABLE нет цепочек pbr — перезапуск $PBR_SERVICE..."
    ( sleep 2; /etc/init.d/$PBR_SERVICE restart && log "Сервис $PBR_SERVICE перезапущен" ) &
    exit 0
else
    log "Цепочки pbr найдены в $TABLE"
fi

log "Проверка завершена — всё в порядке"
exit 0
