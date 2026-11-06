#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Prepara los archivos de la liberación y genera el paquete comprimido.
#
# Uso:   bash scripts/prepare-release.sh v1.0.0
# Requisito previo:  composer install --no-dev --optimize-autoloader
#                    (y npm ci && npm run build si el proyecto usa Vite)
# Resultado en dist/:
#   laravel-release-<versión>.tar.gz          paquete liberable
#   laravel-release-<versión>.tar.gz.sha256   suma de verificación
#   laravel-release-<versión>.manifest.txt    lista de archivos incluidos
# -----------------------------------------------------------------------------
set -euo pipefail

VERSION="${1:?Indica la versión, ej. v1.0.0}"
ROOT="$(pwd)"
NAME="laravel-release-${VERSION}"
BUILD="${ROOT}/.release-build"
DIST="${ROOT}/dist"

fail() { echo "ERROR: $*" >&2; exit 1; }

# 1. Comprobaciones previas
[[ -f artisan && -f composer.json ]]  || fail "Ejecuta el script desde la raíz del proyecto Laravel."
[[ -f composer.lock ]]                || fail "Falta composer.lock (las versiones deben estar fijadas)."
[[ -f vendor/autoload.php ]]          || fail "Falta vendor/. Ejecuta: composer install --no-dev --optimize-autoloader"
[[ ! -d vendor/phpunit ]]             || fail "vendor/ contiene dependencias de desarrollo. Usa --no-dev."
if [[ -f package.json ]] && grep -q '"vite"' package.json && [[ ! -f public/build/manifest.json ]]; then
  fail "El proyecto usa Vite pero no existe public/build/manifest.json. Ejecuta: npm ci && npm run build"
fi

rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD" "$DIST"

# 2. Copiar código de la aplicación aplicando la lista de exclusión
tar --anchored --exclude-from=.releaseignore -cf - . | tar -xf - -C "$BUILD"

# 3. Volver a incluir plantillas de entorno sin secretos (.env.example, etc.)
find . \( -path ./vendor -o -path ./node_modules -o -path ./.git -o -path ./.release-build -o -path ./dist -o -path ./deploy \) -prune \
     -o -type f -name '.env*.example' -print | while read -r f; do
  mkdir -p "$BUILD/$(dirname "$f")"
  cp "$f" "$BUILD/$f"
done

# 4. Dependencias de producción (vendor/ completo, sin repositorios git)
tar --exclude='.git' -cf - vendor | tar -xf - -C "$BUILD"

# 5. Estructura de directorios escribibles que Laravel necesita
for d in storage/app/public storage/framework/cache/data storage/framework/sessions \
         storage/framework/views storage/logs bootstrap/cache; do
  mkdir -p "$BUILD/$d"
done

# 6. Metadatos de la versión
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
BRANCH="${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo local)}"
LARAVEL_VERSION="$(php -r '$l=json_decode(file_get_contents("composer.lock"),true); foreach($l["packages"] as $p){ if($p["name"]==="laravel/framework"){ echo $p["version"]; } }')"
echo "$VERSION" > "$BUILD/VERSION"
cat > "$BUILD/RELEASE_INFO.json" <<JSON
{
  "version": "${VERSION}",
  "commit": "${COMMIT}",
  "ref": "${BRANCH}",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "built_by": "${GITHUB_ACTOR:-$(whoami)}",
  "run_id": "${GITHUB_RUN_ID:-local}",
  "php_version": "$(php -r 'echo PHP_VERSION;')",
  "laravel_version": "${LARAVEL_VERSION:-desconocida}"
}
JSON

# 7. Empaquetar, calcular checksum y manifiesto
tar -C "$BUILD" -czf "$DIST/${NAME}.tar.gz" .
( cd "$DIST" && sha256sum "${NAME}.tar.gz" > "${NAME}.tar.gz.sha256" )
tar -tzf "$DIST/${NAME}.tar.gz" | sed 's|^\./||' | grep -v '^$' | sort > "$DIST/${NAME}.manifest.txt"

rm -rf "$BUILD"

echo "Paquete generado: dist/${NAME}.tar.gz"
echo "  Tamaño : $(du -h "$DIST/${NAME}.tar.gz" | cut -f1)"
echo "  Entradas: $(wc -l < "$DIST/${NAME}.manifest.txt")"
echo "  SHA-256: $(cut -d' ' -f1 "$DIST/${NAME}.tar.gz.sha256")"
