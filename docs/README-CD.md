# Entrega continua – Proyecto Laravel (Unidad III)

> **Alumno:** <TU NOMBRE COMPLETO> · **Matrícula:** <TU MATRÍCULA> · **Grupo:** <GRUPO> · **Docente:** <NOMBRE DEL DOCENTE>

![CI/CD](https://github.com/<TU_USUARIO>/<TU_REPOSITORIO>/actions/workflows/ci-cd.yml/badge.svg)

## Contenido del entregable

| Requisito | Archivo |
|-----------|---------|
| Workflow de liberación continua | [`.github/workflows/ci-cd.yml`](../.github/workflows/ci-cd.yml) |
| Configuración de generación de artefactos | [`scripts/prepare-release.sh`](../scripts/prepare-release.sh), [`.releaseignore`](../.releaseignore), [`scripts/version.sh`](../scripts/version.sh) |
| Scripts para preparar el entorno de liberación | [`deploy/setup-preprod-server.sh`](../deploy/setup-preprod-server.sh), [`deploy/nginx-laravel-preprod.conf`](../deploy/nginx-laravel-preprod.conf), [`deploy/.env.preprod.example`](../deploy/.env.preprod.example), [`scripts/install-release.sh`](../scripts/install-release.sh) |
| Validación del artefacto | [`scripts/validate-artifact.sh`](../scripts/validate-artifact.sh), [`scripts/smoke-test.sh`](../scripts/smoke-test.sh) |
| Diseño del proceso + diagrama | [`docs/01-diseno-proceso-liberacion.md`](01-diseno-proceso-liberacion.md) |
| Parámetros del ambiente de preproducción | [`docs/02-ambiente-preproduccion.md`](02-ambiente-preproduccion.md) |
| Evidencia de validaciones | [`docs/03-validacion-artefacto.md`](03-validacion-artefacto.md), [`docs/evidencias/`](evidencias/) |

## Cómo generar una versión

```bash
# Versión candidata (automática en cada push a main/develop)
git push origin main                       # -> laravel-release-v1.0.1-rc.<N>

# Versión final
git tag -a v1.0.0 -m "Versión 1.0.0"
git push origin v1.0.0                     # -> laravel-release-v1.0.0 + GitHub Release
```

## Probar localmente (sin GitHub)

```bash
composer install --no-dev --optimize-autoloader
npm ci && npm run build                    # si usa Vite
bash scripts/prepare-release.sh v0.0.0-local
bash scripts/validate-artifact.sh dist/laravel-release-v0.0.0-local.tar.gz
bash scripts/smoke-test.sh dist/laravel-release-v0.0.0-local.tar.gz
composer install                           # restaurar dependencias de desarrollo
```
