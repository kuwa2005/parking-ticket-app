#!/bin/sh
set -e

mkdir -p /var/www/html/data
chown -R www-data:www-data /var/www/html/data

# バインドマウント先が空（初回クローン等）の場合も DB 直アクセスは遮断する
if [ ! -f /var/www/html/data/.htaccess ]; then
  cat > /var/www/html/data/.htaccess <<'EOF'
<IfModule mod_authz_core.c>
  Require all denied
</IfModule>
<IfModule !mod_authz_core.c>
  Order allow,deny
  Deny from all
</IfModule>
EOF
fi

exec apache2-foreground
