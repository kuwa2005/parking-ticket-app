FROM php:8.3-apache

# ベースイメージに pdo_sqlite / sqlite3 が同梱済み（docker-php-ext-install 不要と確認済み）

# 監査F2/F3: 本番向け設定（エラー開示抑止・バージョン開示抑止）
RUN printf 'display_errors = Off\nlog_errors = On\nexpose_php = Off\n' > /usr/local/etc/php/conf.d/zz-security.ini \
 && printf 'ServerTokens Prod\nServerSignature Off\n' > /etc/apache2/conf-available/zz-security.conf \
 && a2enconf zz-security

COPY index.php api.php /var/www/html/
COPY lib /var/www/html/lib/
COPY entrypoint.sh /usr/local/bin/park-entrypoint
RUN chmod +x /usr/local/bin/park-entrypoint
