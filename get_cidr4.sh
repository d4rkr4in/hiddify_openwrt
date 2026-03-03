#!/bin/sh
# Скачивает список IPv4 CIDR (формат: comma) и сохраняет в cidr4.txt.
# Путь к cidr4.txt задаётся при установке (install.sh подставляет /root/cidr4.txt).
# Разделитель записей: newline — одна запись на строку; space — записи через пробел.
RECORD_SEP="space"

TMP_FILE=$(mktemp)

if wget -q -O "$TMP_FILE" "https://iplist.opencck.org/?format=comma&data=cidr4"; then
  # Запятые — в выбранный разделитель, обрезка пробелов, убрать пустые
  case "$RECORD_SEP" in
    space)  tr ',' ' ' < "$TMP_FILE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/[[:space:]]\+/ /g' | grep -v '^$' > "${TMP_FILE}.n" ;;
    *)      tr ',' '\n' < "$TMP_FILE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' > "${TMP_FILE}.n" ;;
  esac
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
