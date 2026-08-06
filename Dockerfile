FROM php:8.3-apache

# ベースイメージに pdo_sqlite / sqlite3 が同梱済み（docker-php-ext-install 不要と確認済み）

COPY index.php api.php /var/www/html/
COPY lib /var/www/html/lib/
COPY entrypoint.sh /usr/local/bin/park-entrypoint
RUN chmod +x /usr/local/bin/park-entrypoint
