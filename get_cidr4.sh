#!/bin/sh
# Скачивает список IPv4 CIDR (формат: comma) и сохраняет по одному CIDR на строку в cidr4.txt.
# Путь к cidr4.txt задаётся при установке (install.sh подставляет /root/cidr4.txt).

TMP_FILE=$(mktemp)

if wget -q -O "$TMP_FILE" "https://iplist.opencck.org/?format=comma&data=cidr4"; then
  # Запятые — в переводы строк (один CIDR на строку), убрать пустые строки
  tr ',' '\n' < "$TMP_FILE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' > "${TMP_FILE}.n"
  mv "${TMP_FILE}.n" "$TMP_FILE"

  if ! cmp -s "$TMP_FILE" cidr4.txt; then
    mv "$TMP_FILE" cidr4.txt
    echo "Файл обновлён"
  else
    rm -f "$TMP_FILE"
    echo "Изменений нет"
  fi
else
  echo "Ошибка загрузки"
  rm -f "$TMP_FILE"
  exit 1
fi
