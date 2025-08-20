#!/usr/bin/env bash
set -e
cd /var/www/html
if grep -q '^APP_KEY=$' .env 2>/dev/null; then
  php artisan key:generate --force || true
fi
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

    DB_HOST="$(php -r 'echo parse_url(getenv("DATABASE_URL"), PHP_URL_HOST);')"
    DB_PORT="$(php -r 'echo parse_url(getenv("DATABASE_URL"), PHP_URL_PORT);')"
    DB_DATABASE="$(php -r 'echo ltrim(parse_url(getenv("DATABASE_URL"), PHP_URL_PATH), "/");')"
    DB_USERNAME="$(php -r 'echo parse_url(getenv("DATABASE_URL"), PHP_URL_USER);')"
    DB_PASSWORD="$(php -r 'echo parse_url(getenv("DATABASE_URL"), PHP_URL_PASS);')"

    export DB_HOST DB_PORT DB_DATABASE DB_USERNAME DB_PASSWORD
  fi
fi
if [[ -n "$DB_HOST" && -n "$DB_DATABASE" && -n "$DB_USERNAME" ]]; then
  echo "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT:-5432}..."

fi
php artisan config:cache || true
php artisan route:cache || true
php artisan view:cache || true
exec "$@"
