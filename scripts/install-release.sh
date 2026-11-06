#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Instala un artefacto de liberación en el servidor de PREPRODUCCIÓN.
# Estructura de despliegue (cambio atómico mediante enlace simbólico):
#
#   $APP_DIR/
#   ├── releases/<versión>-<fecha>/   cada liberación instalada
#   ├── shared/.env                   variables de entorno de preproducción
#   ├── shared/storage/               archivos persistentes (logs, uploads…)
#   └── current -> releases/...       versión activa (raíz de Nginx: current/public)
#
# Uso (en el servidor):
#   APP_DIR=/var/www/laravel-preprod bash install-release.sh /tmp/laravel-release-v1.0.0.tar.gz
# -----------------------------------------------------------------------------
set -euo pipefail

PKG="$(realpath "${1:?Indica la ruta del paquete .tar.gz}")"
APP_DIR="${APP_DIR:-/var/www/laravel-preprod}"
WEB_GROUP="${WEB_GROUP:-www-data}"
PHP_FPM_SERVICE="${PHP_FPM_SERVICE:-php8.3-fpm}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://127.0.0.1}"

log() { echo "[$(date +%H:%M:%S)] $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# 0. Verificaciones previas
command -v php >/dev/null      || fail "PHP no está instalado"
[[ -f "${PKG}.sha256" ]] && ( cd "$(dirname "$PKG")" && sha256sum -c "$(basename "$PKG").sha256" )
[[ -f "$APP_DIR/shared/.env" ]] || fail "No existe $APP_DIR/shared/.env (ejecuta primero deploy/setup-preprod-server.sh y configura el .env)"

VERSION="$(tar -xOzf "$PKG" ./VERSION 2>/dev/null || echo unknown)"
RELEASE="$APP_DIR/releases/${VERSION}-$(date +%Y%m%d%H%M%S)"
PREVIOUS="$(readlink -f "$APP_DIR/current" 2>/dev/null || true)"

# 1. Extraer
log "Instalando versión $VERSION en $RELEASE"
mkdir -p "$RELEASE"
tar -xzf "$PKG" -C "$RELEASE"

# 2. Recursos compartidos entre versiones (.env y storage)
if [[ ! -d "$APP_DIR/shared/storage" ]]; then
  log "Inicializando shared/storage"
  cp -a "$RELEASE/storage" "$APP_DIR/shared/storage"
fi
mkdir -p "$APP_DIR"/shared/storage/{app/public,framework/{cache/data,sessions,views},logs}
rm -rf "$RELEASE/storage"
ln -s "$APP_DIR/shared/storage" "$RELEASE/storage"
ln -sf "$APP_DIR/shared/.env" "$RELEASE/.env"

# 3. Permisos: el usuario de despliegue es dueño; el servidor web (grupo) puede escribir
chgrp -R "$WEB_GROUP" "$RELEASE/bootstrap/cache" "$APP_DIR/shared/storage" 2>/dev/null || true
chmod -R ug+rwX "$RELEASE/bootstrap/cache" "$APP_DIR/shared/storage"
find "$APP_DIR/shared/storage" -type d -exec chmod g+s {} +

# 4. Preparar la aplicación
cd "$RELEASE"
php artisan migrate --force
php artisan storage:link --force 2>/dev/null || php artisan storage:link || true
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan event:cache 2>/dev/null || true

# 5. Activar la nueva versión (cambio atómico)
ln -sfn "$RELEASE" "$APP_DIR/current.tmp"
mv -Tf "$APP_DIR/current.tmp" "$APP_DIR/current"
sudo -n systemctl reload "$PHP_FPM_SERVICE" 2>/dev/null || log "Aviso: no se pudo recargar $PHP_FPM_SERVICE (recárgalo manualmente)"
log "Versión activa: $(readlink -f "$APP_DIR/current")"

# 6. Verificación de salud con reversión automática
sleep 1
HEALTHY=0
for path in /up /; do
  code="$(curl -s -o /dev/null -w '%{http_code}' "${HEALTHCHECK_URL}${path}" || true)"
  log "GET ${HEALTHCHECK_URL}${path} -> HTTP ${code}"
  [[ "$code" =~ ^(2|3)[0-9][0-9]$ ]] && { HEALTHY=1; break; }
done
if [[ $HEALTHY -ne 1 ]]; then
  if [[ -n "$PREVIOUS" && -d "$PREVIOUS" ]]; then
    log "Verificación fallida: revirtiendo a $PREVIOUS"
    ln -sfn "$PREVIOUS" "$APP_DIR/current.tmp" && mv -Tf "$APP_DIR/current.tmp" "$APP_DIR/current"
    sudo -n systemctl reload "$PHP_FPM_SERVICE" 2>/dev/null || true
  fi
  fail "La versión $VERSION no pasó la verificación de salud"
fi

# 7. Conservar solo las últimas N versiones
ls -1dt "$APP_DIR"/releases/*/ | tail -n +$((KEEP_RELEASES + 1)) | xargs -r rm -rf
log "Liberación $VERSION instalada correctamente en preproducción"
