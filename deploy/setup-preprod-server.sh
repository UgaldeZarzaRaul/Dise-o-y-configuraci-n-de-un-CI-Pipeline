#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Aprovisiona un servidor de PREPRODUCCIÓN para Laravel (Ubuntu 24.04 LTS).
# Ejecutar UNA vez como root (o con sudo) en la máquina virtual / servidor:
#
#   sudo DB_PASSWORD='algo-seguro' bash deploy/setup-preprod-server.sh
#
# Instala: PHP 8.3 + extensiones, Composer, Nginx, MySQL, usuario de despliegue.
# -----------------------------------------------------------------------------
set -euo pipefail

PHP_V="${PHP_V:-8.3}"
APP_DIR="${APP_DIR:-/var/www/laravel-preprod}"
DEPLOY_USER="${DEPLOY_USER:-deployer}"
DB_NAME="${DB_NAME:-laravel_preprod}"
DB_USER="${DB_USER:-laravel_preprod}"
DB_PASSWORD="${DB_PASSWORD:?Define DB_PASSWORD para el usuario de la base de datos}"
SERVER_NAME="${SERVER_NAME:-_}"

[[ $EUID -eq 0 ]] || { echo "Ejecuta como root (sudo)"; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> 1. Paquetes del sistema, PHP ${PHP_V} y extensiones requeridas por Laravel"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  nginx mysql-server unzip curl git acl \
  php${PHP_V}-fpm php${PHP_V}-cli php${PHP_V}-common php${PHP_V}-mysql php${PHP_V}-sqlite3 \
  php${PHP_V}-mbstring php${PHP_V}-xml php${PHP_V}-curl php${PHP_V}-zip php${PHP_V}-bcmath \
  php${PHP_V}-intl php${PHP_V}-gd php${PHP_V}-opcache

echo "==> 2. Composer"
if ! command -v composer >/dev/null; then
  curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
  php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
fi
composer --version

echo "==> 3. Base de datos de preproducción"
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "==> 4. Usuario de despliegue y estructura de directorios"
id "$DEPLOY_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$DEPLOY_USER"
usermod -aG www-data "$DEPLOY_USER"
mkdir -p "$APP_DIR"/{releases,shared/storage}
chown -R "$DEPLOY_USER":www-data "$APP_DIR"
chmod 2775 "$APP_DIR/shared/storage"
setfacl -R -m g:www-data:rwX -m d:g:www-data:rwX "$APP_DIR/shared/storage"

# Permitir al usuario de despliegue recargar PHP-FPM sin contraseña
echo "${DEPLOY_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl reload php${PHP_V}-fpm" \
  > /etc/sudoers.d/laravel-deploy && chmod 440 /etc/sudoers.d/laravel-deploy

echo "==> 5. Variables de entorno independientes (shared/.env)"
if [[ ! -f "$APP_DIR/shared/.env" ]]; then
  cp "$SCRIPT_DIR/.env.preprod.example" "$APP_DIR/shared/.env"
  sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|; s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|; s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|" "$APP_DIR/shared/.env"
  APP_KEY="base64:$(head -c 32 /dev/urandom | base64)"
  sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|" "$APP_DIR/shared/.env"
  chown "$DEPLOY_USER":www-data "$APP_DIR/shared/.env"
  chmod 640 "$APP_DIR/shared/.env"
fi

echo "==> 6. Nginx"
sed "s|__APP_DIR__|${APP_DIR}|g; s|__SERVER_NAME__|${SERVER_NAME}|g; s|__PHP_V__|${PHP_V}|g" \
  "$SCRIPT_DIR/nginx-laravel-preprod.conf" > /etc/nginx/sites-available/laravel-preprod
ln -sf /etc/nginx/sites-available/laravel-preprod /etc/nginx/sites-enabled/laravel-preprod
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
systemctl enable --now php${PHP_V}-fpm nginx mysql

echo
echo "Servidor de preproducción listo."
echo "  - Agrega la llave pública de GitHub Actions a /home/${DEPLOY_USER}/.ssh/authorized_keys"
echo "  - Revisa ${APP_DIR}/shared/.env"
echo "  - Instala una versión: APP_DIR=${APP_DIR} bash install-release.sh <paquete.tar.gz>"
