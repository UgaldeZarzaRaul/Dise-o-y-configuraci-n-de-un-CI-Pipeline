# Proyecto Laravel – Pipeline de Integración Continua

Aplicación web desarrollada con **PHP / Laravel** y **MySQL**. Este repositorio incluye un
pipeline de **GitHub Actions** que verifica cada cambio antes de integrarlo a la rama `main`.

## Requisitos

- PHP 8.3 o superior (ver `composer.json`) con las extensiones `mbstring`, `xml`, `ctype`, `fileinfo`, `pdo_mysql`, `bcmath`
- Composer 2
- Node.js 20 y npm (si el proyecto compila recursos frontend)
- MySQL 8

## Preparar el entorno local

```bash
git clone <URL-DEL-REPOSITORIO>
cd <CARPETA-DEL-PROYECTO>

composer install
cp .env.example .env
php artisan key:generate

# Configurar en .env los datos de la base de datos (DB_DATABASE, DB_USERNAME, DB_PASSWORD)
php artisan migrate

npm ci
npm run build
```

## Verificar el proyecto

```bash
composer validate --no-check-publish   # valida composer.json y composer.lock
php artisan test                       # ejecuta las pruebas automatizadas
```

## Pipeline de CI

Archivo: [`.github/workflows/ci.yml`](.github/workflows/ci.yml)

| Evento | Cuándo se ejecuta |
|---|---|
| `push` | Al subir cambios a `main` o `develop` |
| `pull_request` | Al abrir o actualizar un PR hacia `main` |
| `workflow_dispatch` | Manualmente desde la pestaña *Actions* |

Pasos: checkout → PHP → validar Composer → instalar dependencias (con caché) → preparar `.env`
y clave → Node y `npm run build` (si hay `package.json`) → migraciones → `php artisan test`.

**Aprobación:** todos los pasos terminan con código 0. **Rechazo:** cualquier paso falla; el
pipeline se marca en rojo y, con la protección de rama activa, el PR no puede unirse a `main`.

Diagrama del flujo: [`docs/diagrama_flujo.png`](docs/diagrama_flujo.png)

## Evidencias

Las capturas de las ejecuciones (fallida y exitosa) se guardan en `docs/evidencias/`.
