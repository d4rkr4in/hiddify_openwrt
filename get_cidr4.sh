TMP_FILE=$(mktemp)

if wget -q -O "$TMP_FILE" "https://iplist.opencck.org/?format=comma&data=cidr4"; then
    sed -i 's/,//g' "$TMP_FILE"

    if ! cmp -s "$TMP_FILE" cidr4.txt; then
        mv "$TMP_FILE" cidr4.txt
        echo "Файл обновлён"
    else
        rm "$TMP_FILE"
        echo "Изменений нет"
    fi
else
    echo "Ошибка загрузки"
    rm -f "$TMP_FILE"
    exit 1
fi
