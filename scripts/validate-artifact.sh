#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Valida un artefacto de liberación Laravel y genera un reporte Markdown.
#
# Uso:  bash scripts/validate-artifact.sh <paquete.tar.gz> [reporte.md]
#
# Verifica:
#   A. Integridad (tar legible y SHA-256 si existe el archivo .sha256)
#   B. Archivos necesarios para ejecutar la aplicación
#   C. Ausencia de archivos sensibles (.env, llaves, BD, logs, .git)
#   D. Ausencia de dependencias de desarrollo en vendor/
#   E. Búsqueda de credenciales dentro del contenido
# Termina con código 1 si alguna verificación obligatoria falla.
# -----------------------------------------------------------------------------
set -uo pipefail

PKG="${1:?Indica la ruta del paquete .tar.gz}"
REPORT="${2:-validation-report.md}"
[[ -f "$PKG" ]] || { echo "No existe $PKG" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
LIST="$WORK/list.txt"

PASS=0; FAIL=0; WARN=0
ROWS=""
row() { # estado, categoría, verificación, detalle
  local icon
  case "$1" in ok) icon="✅"; PASS=$((PASS+1));; fail) icon="❌"; FAIL=$((FAIL+1));; *) icon="⚠️"; WARN=$((WARN+1));; esac
  ROWS+="| ${icon} | $2 | $3 | $4 |"$'\n'
  printf '%s %-14s %s %s\n' "$icon" "$2" "$3" "${4:+($4)}"
}

# ---------------- A. Integridad ----------------
if tar -tzf "$PKG" > "$WORK/raw.txt" 2>/dev/null; then
  sed 's|^\./||' "$WORK/raw.txt" | grep -v '^$' > "$LIST"
  row ok "Integridad" "El paquete se puede leer (tar.gz válido)" "$(wc -l < "$LIST") entradas"
else
  row fail "Integridad" "El paquete se puede leer (tar.gz válido)" "archivo corrupto"
  LIST=/dev/null
fi

SUMFILE="${PKG}.sha256"
if [[ -f "$SUMFILE" ]]; then
  if ( cd "$(dirname "$PKG")" && sha256sum -c "$(basename "$SUMFILE")" >/dev/null 2>&1 ); then
    row ok "Integridad" "Coincide la suma SHA-256" "$(cut -c1-16 "$SUMFILE")…"
  else
    row fail "Integridad" "Coincide la suma SHA-256" "el paquete fue alterado"
  fi
else
  row warn "Integridad" "Archivo .sha256 presente" "no se encontró $SUMFILE"
fi

has() { awk -v p="$1" '$0==p || $0==p"/" || index($0,p"/")==1 {f=1; exit} END{exit !f}' "$LIST"; }

# ---------------- B. Archivos necesarios ----------------
REQUIRED=(
  "artisan|Consola de Laravel"
  "composer.json|Definición de dependencias"
  "composer.lock|Versiones fijadas de dependencias"
  "app|Código de la aplicación"
  "bootstrap/app.php|Arranque del framework"
  "config/app.php|Configuración"
  "routes/web.php|Rutas"
  "public/index.php|Punto de entrada web"
  "resources/views|Vistas Blade"
  "database/migrations|Migraciones"
  "vendor/autoload.php|Dependencias de producción instaladas"
  "storage/framework|Directorio escribible storage/framework"
  "storage/logs|Directorio escribible storage/logs"
  "bootstrap/cache|Directorio escribible bootstrap/cache"
  ".env.example|Plantilla de variables de entorno (sin secretos)"
  "VERSION|Identificador de versión"
  "RELEASE_INFO.json|Metadatos de la liberación"
)
for item in "${REQUIRED[@]}"; do
  p="${item%%|*}"; d="${item#*|}"
  if has "$p"; then row ok "Necesarios" "\`$p\`" "$d"; else row fail "Necesarios" "\`$p\`" "FALTA – $d"; fi
done
if grep -q '^package.json$' "$LIST"; then
  if grep -q '^public/build/manifest.json$' "$LIST"; then
    row ok "Necesarios" "\`public/build/manifest.json\`" "recursos front-end compilados"
  else
    row warn "Necesarios" "\`public/build/manifest.json\`" "no hay assets compilados (¿usa Vite?)"
  fi
fi

# ---------------- C. Archivos sensibles ----------------
check_absent() { # descripción, regex (ERE sobre la ruta)
  local hits
  hits="$(grep -E "$2" "$LIST" | head -n 5 | tr '\n' ' ')"
  if [[ -z "$hits" ]]; then row ok "Sensibles" "$1" "no encontrado"; else row fail "Sensibles" "$1" "ENCONTRADO: ${hits}"; fi
}
check_absent "Sin archivo \`.env\`"                       '(^|/)\.env$'
ENV_VARIANTS="$(grep -E '(^|/)\.env\.[^/]+$' "$LIST" | grep -vE '\.example$' | head -n 5 | tr '\n' ' ')"
if [[ -z "$ENV_VARIANTS" ]]; then row ok "Sensibles" "Sin variantes \`.env.*\` (excepto .example)" "no encontrado"
else row fail "Sensibles" "Sin variantes \`.env.*\` (excepto .example)" "ENCONTRADO: ${ENV_VARIANTS}"; fi
check_absent "Sin repositorio \`.git/\`"                   '(^|/)\.git(/|$)'
check_absent "Sin \`node_modules/\`"                       '^node_modules(/|$)'
KEYS="$(grep -v '^vendor/' "$LIST" | grep -E '\.(pem|key|p12)$|(^|/)id_rsa' | head -n 5 | tr '\n' ' ')"
if [[ -z "$KEYS" ]]; then row ok "Sensibles" "Sin llaves privadas/certificados (fuera de vendor)" "no encontrado"
else row fail "Sensibles" "Sin llaves privadas/certificados (fuera de vendor)" "ENCONTRADO: ${KEYS}"; fi
check_absent "Sin \`auth.json\` de Composer"               '(^|/)auth\.json$'
check_absent "Sin bases de datos SQLite"                   '\.sqlite(-journal)?$'
check_absent "Sin logs en \`storage/logs\`"                '^storage/logs/.+\.log$'
check_absent "Sin sesiones/caché de ejecución"             '^storage/framework/(sessions|cache/data)/[^.].+'
if grep -qE '^tests/' "$LIST"; then row warn "Limpieza" "Sin carpeta \`tests/\`" "incluida (no es necesaria)"
else row ok "Limpieza" "Sin carpeta \`tests/\`" "no incluida"; fi

# ---------------- D. Dependencias de desarrollo ----------------
for dev in phpunit/phpunit mockery/mockery fakerphp/faker laravel/sail nunomaduro/collision; do
  if has "vendor/$dev"; then row fail "Producción" "Sin \`$dev\` (require-dev)" "INCLUIDO"
  else row ok "Producción" "Sin \`$dev\` (require-dev)" "no incluido"; fi
done

# ---------------- E. Credenciales en el contenido ----------------
mkdir -p "$WORK/x"
tar -xzf "$PKG" -C "$WORK/x" --exclude='./vendor' --exclude='vendor' 2>/dev/null
scan() { # descripción, regex
  local hits
  hits="$(grep -rIlE --exclude-dir=vendor --exclude-dir=node_modules "$2" "$WORK/x" 2>/dev/null | sed "s|$WORK/x/||; s|^\./||" | head -n 5 | tr '\n' ' ')"
  if [[ -z "$hits" ]]; then row ok "Credenciales" "$1" "sin coincidencias"; else row fail "Credenciales" "$1" "EN: ${hits}"; fi
}
scan "Sin \`APP_KEY\` real"                    'APP_KEY=base64:[A-Za-z0-9+/=]{20,}'
scan "Sin contraseñas asignadas en archivos env" '^[[:space:]]*(DB_PASSWORD|MAIL_PASSWORD|REDIS_PASSWORD|AWS_SECRET_ACCESS_KEY)=[^[:space:]#]+'
scan "Sin llaves privadas embebidas"          '-----BEGIN [A-Z ]*PRIVATE KEY-----'
scan "Sin llaves de AWS"                       'AKIA[0-9A-Z]{16}'
scan "Sin tokens de GitHub"                    'gh[pousr]_[A-Za-z0-9]{36}'

# ---------------- Reporte ----------------
VERSION_TXT="$(tar -xOzf "$PKG" ./VERSION 2>/dev/null || tar -xOzf "$PKG" VERSION 2>/dev/null || echo 'N/D')"
SIZE="$(du -h "$PKG" | cut -f1)"
SHA="$(sha256sum "$PKG" | cut -d' ' -f1)"
STATUS="APROBADO"; [[ $FAIL -gt 0 ]] && STATUS="RECHAZADO"

{
  echo "# Reporte de validación del artefacto"
  echo
  echo "| Dato | Valor |"
  echo "|---|---|"
  echo "| Paquete | \`$(basename "$PKG")\` |"
  echo "| Versión | \`${VERSION_TXT}\` |"
  echo "| Tamaño | ${SIZE} |"
  echo "| SHA-256 | \`${SHA}\` |"
  echo "| Entradas | $(wc -l < "$LIST" 2>/dev/null || echo 0) |"
  echo "| Fecha de validación | $(date -u +'%Y-%m-%d %H:%M:%S UTC') |"
  if [[ -n "${GITHUB_RUN_ID:-}" ]]; then echo "| Ejecutado en | GitHub Actions – ${GITHUB_REPOSITORY:-} run ${GITHUB_RUN_ID} |"; else echo "| Ejecutado en | $(hostname) (manual) |"; fi
  echo "| **Resultado** | **${STATUS}** – ✅ ${PASS} · ❌ ${FAIL} · ⚠️ ${WARN} |"
  echo
  echo "| Estado | Categoría | Verificación | Detalle |"
  echo "|---|---|---|---|"
  printf '%s' "$ROWS" | grep -v '^$'
} > "$REPORT"

[[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && cat "$REPORT" >> "$GITHUB_STEP_SUMMARY"

echo
echo "Resultado: ${STATUS}  (✅ ${PASS}  ❌ ${FAIL}  ⚠️ ${WARN})  -> reporte: ${REPORT}"
[[ $FAIL -eq 0 ]]
