#!/usr/bin/env bash
set -e

cd /var/www/html

# Форсим https ссылки при работе за прокси (по желанию):
# php -r "file_exists('app/Providers/AppServiceProvider.php') && print('');"

# Генерация ключа, линк на storage, кеши
php artisan key:generate --force || true
php artisan storage:link || true

# Ждём БД (если переменные заданы) и накатываем миграции
if [[ -n "$DB_HOST" && -n "$DB_DATABASE" && -n "$DB_USERNAME" ]]; then
  echo "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT:-5432}..."
  until php -r "
    try {
      new PDO(
        'pgsql:host=' . getenv('DB_HOST') . ';port=' . (getenv('DB_PORT') ?: '5432') . ';dbname=' . getenv('DB_DATABASE'),
        getenv('DB_USERNAME'),
        getenv('DB_PASSWORD')
      );
    } catch (Exception \$e) { exit(1); }"; do
    sleep 2
  done
  php artisan migrate --force || true
fi

php artisan config:cache || true
php artisan route:cache || true
php artisan view:cache || true

exec \"$@\"
