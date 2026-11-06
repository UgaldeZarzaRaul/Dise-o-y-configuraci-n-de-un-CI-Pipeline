# Parte 4. Validación del artefacto

> **Alumno:** <TU NOMBRE COMPLETO> · **Matrícula:** <TU MATRÍCULA>
> **Ejecución del workflow:** https://github.com/<TU_USUARIO>/<TU_REPOSITORIO>/actions/runs/<RUN_ID>
> **Versión validada:** `<v1.0.0>` · **Fecha:** <FECHA>

La validación se hace dos veces: **automáticamente** en el pipeline (jobs `build-release` y `deploy-preprod`) y **manualmente** descargando el artefacto, para comprobar de forma independiente lo que generó GitHub Actions.

## 4.1 Descargar el artefacto

Opción A – interfaz web: *Actions → ejecución → sección **Artifacts** → `laravel-release-vX.Y.Z`* (se descarga como `.zip`).

Opción B – GitHub CLI:

```bash
gh run list --workflow ci-cd.yml --limit 5
gh run download <RUN_ID> -n laravel-release-<VERSIÓN> -D ./artifact
ls -lh ./artifact
```

## 4.2 Comprobar que contiene los archivos necesarios

```bash
cd artifact
sha256sum -c laravel-release-<VERSIÓN>.tar.gz.sha256        # integridad
tar -tzf laravel-release-<VERSIÓN>.tar.gz | grep -E '^\./(artisan|composer\.lock|public/index\.php|vendor/autoload\.php|VERSION)$'
tar -xOzf laravel-release-<VERSIÓN>.tar.gz ./RELEASE_INFO.json
```

## 4.3 Verificar que no incluye `.env`, credenciales ni información sensible

```bash
tar -tzf laravel-release-<VERSIÓN>.tar.gz | grep -v '^\./vendor/' | grep -vE '\.example$' \
  | grep -E '(^|/)\.env(\..+)?$|\.git/|node_modules/|\.sqlite$|\.key$|\.pem$|auth\.json$' \
  || echo "OK: sin archivos sensibles"

# Validación completa con reporte (desde la raíz del repositorio)
bash scripts/validate-artifact.sh artifact/laravel-release-<VERSIÓN>.tar.gz docs/evidencias/validacion-manual.md
```

## 4.4 Comprobar que puede instalarse en el ambiente de pruebas

```bash
# Prueba rápida local/VM con SQLite
bash scripts/smoke-test.sh artifact/laravel-release-<VERSIÓN>.tar.gz

# Instalación real en el servidor de preproducción
scp artifact/laravel-release-<VERSIÓN>.tar.gz* scripts/install-release.sh deployer@<IP>:/tmp/
ssh deployer@<IP> "APP_DIR=/var/www/laravel-preprod bash /tmp/install-release.sh /tmp/laravel-release-<VERSIÓN>.tar.gz"
curl -I http://<IP>/up
ssh deployer@<IP> "cd /var/www/laravel-preprod/current && php artisan about --only=environment && cat VERSION"
```

## 4.5 Registro de resultados

| # | Verificación | Comando / evidencia | Resultado esperado | Resultado obtenido | ✔/✘ |
|---|--------------|---------------------|--------------------|--------------------|-----|
| 1 | Pruebas automatizadas | Job `ci` → `php artisan test` | Todas pasan | `__ pruebas, __ aserciones` | |
| 2 | Artefacto generado | Sección *Artifacts* de la ejecución | `laravel-release-<v>` disponible (7 días) | | |
| 3 | Integridad SHA-256 | `sha256sum -c` | `OK` | | |
| 4 | Archivos necesarios | `validate-artifact.sh` (categoría *Necesarios*) | 17/17 ✅ | | |
| 5 | Sin `.env` ni variantes | `validate-artifact.sh` (*Sensibles*) | No encontrado | | |
| 6 | Sin llaves, BD, logs, `.git`, `node_modules` | `validate-artifact.sh` (*Sensibles*) | No encontrado | | |
| 7 | Sin dependencias de desarrollo | `validate-artifact.sh` (*Producción*) | `phpunit`, `faker`… no incluidos | | |
| 8 | Sin credenciales en el contenido | `validate-artifact.sh` (*Credenciales*) | Sin coincidencias | | |
| 9 | Instalación en ambiente efímero | Job `deploy-preprod` → smoke test | Migraciones OK, HTTP 200 | | |
| 10 | Instalación en preproducción | `install-release.sh` | `current` apunta a la nueva versión, `/up` 200 | | |
| 11 | Versión desplegada | `cat current/VERSION` | `<v>` | | |
| 12 | Permisos de escritura | `sudo -u www-data touch current/storage/logs/test && echo OK` | `OK` | | |
| 13 | Prueba negativa: paquete con `.env` es rechazado | Ver 4.6 | Validador termina con ❌ | | |

**Conclusión:** <El artefacto vX.Y.Z cumple / no cumple los criterios de liberación y queda listo para validación funcional en preproducción.>

## 4.6 Prueba negativa (demuestra que el control funciona)

El paquete del ejemplo de la actividad (`tar --exclude='.git' --exclude='.env' ... -czf laravel-release.tar.gz .`) **no es suficiente**: el validador lo rechaza porque no excluye `.env.backup`/`.env.production`, llaves en `storage/*.key`, la BD SQLite, sesiones ni `tests/`, y empaqueta `vendor/` con dependencias de desarrollo. Para demostrarlo:

```bash
cp .env .env.backup           # simula un respaldo olvidado
tar --exclude='.git' --exclude='.env' --exclude='node_modules' --exclude='storage/logs/*' \
    -czf /tmp/ingenuo.tar.gz .
bash scripts/validate-artifact.sh /tmp/ingenuo.tar.gz /tmp/reporte-ingenuo.md   # -> RECHAZADO
rm .env.backup
```

Resultado obtenido en una prueba con un proyecto simulado: **RECHAZADO (✅ 27 · ❌ 10 · ⚠️ 2)** — detectó `.env.backup`, `storage/oauth-private.key`, `database/database.sqlite`, sesiones, `vendor/phpunit`, un `APP_KEY` real y una llave AWS en `config/`.

## 4.7 Capturas de evidencia (guardar en `docs/evidencias/`)

| Archivo | Qué debe mostrar |
|---------|------------------|
| `01-workflow-verde.png` | Ejecución completa con los 3–4 jobs en verde |
| `02-pruebas.png` | Log del paso *Ejecutar pruebas automatizadas* |
| `03-artefacto.png` | Sección *Artifacts* con `laravel-release-<v>` y su tamaño |
| `04-resumen-validacion.png` | *Summary* de la ejecución con la tabla del validador |
| `05-smoke-test.png` | Log de la prueba de instalación con HTTP 200 |
| `06-descarga-local.png` | Terminal con `gh run download` + `sha256sum -c` + validador |
| `07-preproduccion.png` | Navegador en `http://<IP>` y/o `php artisan about` en el servidor |
| `08-prueba-negativa.png` | Validador rechazando el paquete con `.env.backup` |
| `09-release.png` | (Si creaste tag) GitHub Release `vX.Y.Z` con los archivos adjuntos |
| `validacion-manual.md` | Reporte generado por `validate-artifact.sh` |
