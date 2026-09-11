#!/bin/bash
# Выкладывает приложение в каталог, который раздаёт Caddy.
#
# Почему копированием, а не напрямую из /root/Графики: Caddy работает под пользователем
# caddy, а /root закрыт (drwx------). Плюс так наружу попадают ТОЛЬКО файлы приложения —
# без .git (в нём токен), без *.md и *.sql.
#
# Запуск:  bash tools/deploy.sh
set -e
SRC="/root/Графики"
DST="/var/www/gantt"

mkdir -p "$DST"
# index.html — чтобы адрес был просто /gantt/; construction_gantt.html — чтобы не ломались
# ссылки, которые уже разосланы людям
install -m 0644 "$SRC/construction_gantt.html" "$DST/index.html"
install -m 0644 "$SRC/construction_gantt.html" "$DST/construction_gantt.html"
rm -rf "$DST/vendor"
cp -r "$SRC/vendor" "$DST/vendor"
chown -R caddy:caddy "$DST"
find "$DST" -type d -exec chmod 755 {} +
find "$DST" -type f -exec chmod 644 {} +
echo "выложено в $DST:"
du -sh "$DST"
