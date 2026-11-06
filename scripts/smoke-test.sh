#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Prueba de instalación ("smoke test") del artefacto en un ambiente efímero.
# Simula la preparación en preproducción usando SQLite y el servidor embebido.
#
# Uso:  bash scripts/smoke-test.sh <paquete.tar.gz>
# -----------------------------------------------------------------------------
set -euo pipefail

PKG="$(realpath "${1:?Indica la ruta del paquete .tar.gz}")"
DIR="${RUNNER_TEMP:-/tmp}/smoke-release"
PORT="${SMOKE_PORT:-8099}"
LOG="${DIR}.server.log"

step() { echo; echo "==> $*"; }
set_env() { # clave valor
  if grep -qE "^#?\s*$1=" .env; then sed -i -E "s|^#?\s*$1=.*|$1=$2|" .env; else echo "$1=$2" >> .env; fi
}

rm -rf "$DIR" && mkdir -p "$DIR"
step "Extrayendo $(basename "$PKG")"
tar -xzf "$PKG" -C "$DIR"
cd "$DIR"
echo "Versión: $(cat VERSION)"

step "Configurando variables de entorno independientes (.env de preproducción simulado)"
cp .env.example .env
set_env APP_ENV staging
set_env APP_DEBUG false
set_env APP_URL "http://127.0.0.1:${PORT}"
set_env LOG_CHANNEL stderr
set_env DB_CONNECTION sqlite
set_env DB_DATABASE "${DIR}/database/preprod.sqlite"
set_env SESSION_DRIVER file
set_env CACHE_STORE file
set_env CACHE_DRIVER file
set_env QUEUE_CONNECTION sync
touch database/preprod.sqlite
php artisan key:generate --force

step "Permisos de storage/ y bootstrap/cache/"
chmod -R ug+rwX storage bootstrap/cache

step "Migraciones y optimización"
php artisan migrate --force
php artisan storage:link || true
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan about --only=environment || true

step "Levantando servidor de prueba en el puerto ${PORT}"
php artisan serve --host=127.0.0.1 --port="$PORT" > "$LOG" 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do curl -s "http://127.0.0.1:${PORT}" >/dev/null && break; sleep 0.5; done

step "Verificación HTTP"
OK=0
for path in /up /; do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}${path}" || true)"
  echo "GET ${path} -> HTTP ${code}"
  if [[ "$code" =~ ^(2|3)[0-9][0-9]$ ]]; then OK=1; break; fi
done

RESULT="FALLÓ"; [[ $OK -eq 1 ]] && RESULT="CORRECTA"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Prueba de instalación del artefacto: ${RESULT}"
    echo "- Versión: \`$(cat VERSION)\`"
    echo "- Migraciones ejecutadas, caché de configuración/rutas/vistas generada"
    echo "- Respuesta HTTP: \`GET ${path} -> ${code}\`"
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [[ $OK -ne 1 ]]; then
  echo "La aplicación no respondió correctamente. Log del servidor:"; cat "$LOG"
  tail -n 50 storage/logs/*.log 2>/dev/null || true
  exit 1
fi
echo "Prueba de instalación CORRECTA"
