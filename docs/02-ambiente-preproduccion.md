# Parte 3. Parámetros del ambiente de preproducción

> **Alumno:** <TU NOMBRE COMPLETO> · **Matrícula:** <TU MATRÍCULA>
> Tipo de ambiente utilizado: ☐ Máquina virtual (VirtualBox/VMware/Multipass) ☐ Servidor de pruebas ☐ Servicio de alojamiento autorizado: ________

## 3.1 Características del servidor

| Parámetro | Valor configurado | Cómo verificarlo |
|-----------|-------------------|------------------|
| Sistema operativo | Ubuntu Server 24.04 LTS | `lsb_release -a` |
| CPU / RAM / Disco (mínimo) | 1 vCPU · 2 GB · 20 GB | `nproc`, `free -h`, `df -h` |
| Nombre / IP | `<preprod.tu-dominio.local>` / `<IP>` | `hostname -I` |
| PHP | 8.3 (FPM + CLI) — compatible con Laravel 11/12 (≥ 8.2) | `php -v` |
| Composer | 2.x | `composer --version` |
| Servidor web | Nginx 1.24 + PHP-FPM (socket `/run/php/php8.3-fpm.sock`) | `nginx -v`, `systemctl status php8.3-fpm` |
| Base de datos | MySQL 8.0 · BD `laravel_preprod` · usuario `laravel_preprod` (solo privilegios sobre esa BD) | `mysql -u laravel_preprod -p -e "SHOW DATABASES;"` |
| Usuario de despliegue | `deployer` (miembro del grupo `www-data`, sin acceso root salvo recargar PHP-FPM) | `id deployer` |
| Ruta de la aplicación | `/var/www/laravel-preprod` | `ls -l /var/www/laravel-preprod` |
| Raíz pública de Nginx | `/var/www/laravel-preprod/current/public` | `nginx -T \| grep root` |

## 3.2 Extensiones PHP necesarias

| Extensión | Paquete Ubuntu | Uso en Laravel |
|-----------|----------------|----------------|
| ctype, fileinfo, tokenizer, openssl, pdo | `php8.3-common` / `php8.3-cli` | Núcleo del framework, cifrado, subida de archivos |
| mbstring | `php8.3-mbstring` | Manejo de cadenas UTF-8 |
| xml, dom | `php8.3-xml` | Paquetes que procesan XML |
| curl | `php8.3-curl` | Cliente HTTP |
| pdo_mysql | `php8.3-mysql` | Conexión a MySQL |
| bcmath | `php8.3-bcmath` | Cálculos de precisión |
| intl | `php8.3-intl` | Localización / formatos |
| zip | `php8.3-zip` | Composer y manejo de archivos |
| gd | `php8.3-gd` | Imágenes |
| opcache | `php8.3-opcache` | Rendimiento |

Verificación: `php -m | grep -Ei 'ctype|curl|dom|fileinfo|mbstring|openssl|pdo_mysql|tokenizer|xml|bcmath|intl|zip|gd'`

## 3.3 Estructura de despliegue

```
/var/www/laravel-preprod/
├── releases/
│   ├── v1.0.1-rc.36-20261105120000/
│   └── v1.0.1-rc.37-20261106163000/   ← versión más reciente
├── shared/
│   ├── .env                            ← variables de preproducción (640, deployer:www-data)
│   └── storage/                        ← logs, sesiones, archivos subidos (persisten entre versiones)
└── current -> releases/v1.0.1-rc.37-20261106163000
```

Ventajas: cambio atómico de versión, reversión inmediata (re-apuntar `current`), se conservan las últimas 5 versiones.

## 3.4 Variables de entorno independientes

El archivo `shared/.env` **solo existe en el servidor**; nunca se versiona ni viaja en el artefacto. Plantilla: [`deploy/.env.preprod.example`](../deploy/.env.preprod.example).

| Variable | Desarrollo (local) | Pruebas (CI) | **Preproducción** |
|----------|-------------------|--------------|-------------------|
| `APP_ENV` | `local` | `testing` | `staging` |
| `APP_DEBUG` | `true` | `true` | **`false`** |
| `APP_KEY` | propia | generada en cada ejecución | propia, generada en el servidor |
| `DB_CONNECTION` | mysql/sqlite | sqlite | mysql |
| `DB_DATABASE` | `laravel` | `database.sqlite` | `laravel_preprod` |
| `LOG_LEVEL` | `debug` | `debug` | `info` |
| `MAIL_MAILER` | `log` | `array` | `log` (no envía correos reales) |
| `SESSION_DRIVER` / `CACHE_STORE` | `file` | `array` | `database` |

Secretos del pipeline (GitHub → *Settings → Environments → preproduccion*):

| Nombre | Tipo | Contenido |
|--------|------|-----------|
| `STAGING_HOST` | Secret | IP o dominio del servidor |
| `STAGING_USER` | Secret | `deployer` |
| `STAGING_PORT` | Secret (opcional) | `22` |
| `STAGING_SSH_KEY` | Secret | Llave privada **dedicada** al despliegue |
| `STAGING_KNOWN_HOSTS` | Secret (recomendado) | Salida de `ssh-keyscan <host>` |
| `STAGING_PATH` | Variable | `/var/www/laravel-preprod` |

> Si la VM está en tu red local (detrás de NAT), GitHub no puede alcanzarla: deja los secretos vacíos y usa la **entrega manual** que el workflow describe en el resumen de la ejecución.

## 3.5 Permisos de `storage/` y `bootstrap/cache/`

| Ruta | Propietario | Permisos | Motivo |
|------|-------------|----------|--------|
| `releases/*` (código) | `deployer:www-data` | `755` dirs / `644` archivos | El servidor web solo lee el código |
| `shared/storage/` | `deployer:www-data` | `2775` + ACL `g:www-data:rwX` | PHP-FPM escribe logs, sesiones, caché, uploads |
| `releases/*/bootstrap/cache/` | `deployer:www-data` | `775` | Laravel escribe la caché de configuración/rutas |
| `shared/.env` | `deployer:www-data` | `640` | Solo lectura para el servidor web; no legible por otros |

Comandos aplicados (en `install-release.sh` y `setup-preprod-server.sh`):

```bash
sudo chown -R deployer:www-data /var/www/laravel-preprod
sudo chmod 2775 /var/www/laravel-preprod/shared/storage
sudo setfacl -R -m g:www-data:rwX -m d:g:www-data:rwX /var/www/laravel-preprod/shared/storage
chmod -R ug+rwX storage bootstrap/cache
```

## 3.6 Comandos para preparar el entorno

```bash
# 1. En la VM/servidor (una sola vez): copiar la carpeta deploy/ y ejecutar
sudo DB_PASSWORD='<contraseña-segura>' SERVER_NAME='<IP o dominio>' bash deploy/setup-preprod-server.sh

# 2. Llave de despliegue para GitHub Actions (en tu equipo)
ssh-keygen -t ed25519 -C "github-actions-preprod" -f ./deploy_key -N ""
#   - contenido de deploy_key.pub  -> /home/deployer/.ssh/authorized_keys (servidor)
#   - contenido de deploy_key      -> secreto STAGING_SSH_KEY (GitHub)
#   - después borra ambos archivos de tu equipo local

# 3. Instalar una versión manualmente (si no hay entrega por SSH)
APP_DIR=/var/www/laravel-preprod bash install-release.sh /tmp/laravel-release-v1.0.0.tar.gz

# 4. Revertir a la versión anterior
cd /var/www/laravel-preprod && ln -sfn "$(ls -1dt releases/*/ | sed -n 2p)" current && sudo systemctl reload php8.3-fpm
```
