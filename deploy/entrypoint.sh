#!/usr/bin/env bash
set -e
cd /var/www/html
php artisan key:generate --force || true
php artisan storage:link || true
if [[ -z "$DB_HOST" ]]; then
  if [[ -n "$POSTGRESQL_HOST" ]]; then
    DB_HOST="$POSTGRESQL_HOST"
    DB_PORT="${POSTGRESQL_PORT:-5432}"
    DB_DATABASE="$POSTGRESQL_DBNAME"
    DB_USERNAME="$POSTGRESQL_USER"
    DB_PASSWORD="$POSTGRESQL_PASSWORD"
    export DB_HOST DB_PORT DB_DATABASE DB_USERNAME DB_PASSWORD
  elif [[ -n "$DATABASE_URL" ]]; then
    eval $(php -r '$p=parse_url(getenv("DATABASE_URL")); printf("DB_HOST=%s\nDB_PORT=%s\nDB_DATABASE=%s\nDB_USERNAME=%s\nDB_PASSWORD=%s\n", $p["host"], $p["port"], ltrim($p["path"], "/"), $p["user"], $p["pass"]);')
    export DB_HOST DB_PORT DB_DATABASE DB_USERNAME DB_PASSWORD
  fi
fi
if [[ -n "$DB_HOST" && -n "$DB_DATABASE" && -n "$DB_USERNAME" ]]; then
  echo "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT:-5432}..."
  # Database initialization disabled during startup; remove or uncomment
  # the lines below to restore waiting for the database and running migrations.
  # until php -r "
  #   try {
  #     new PDO(
  #       'pgsql:host=' . getenv('DB_HOST') . ';port=' . (getenv('DB_PORT') ?: '5432') . ';dbname=' . getenv('DB_DATABASE'),
  #       getenv('DB_USERNAME'),
  #       getenv('DB_PASSWORD')
  #     );
  #   } catch (Exception $e) { exit(1); }"; do sleep 2; done
  # php artisan migrate --force || true
fi
php artisan config:cache || true
php artisan route:cache || true
php artisan view:cache || true
exec "$@"
