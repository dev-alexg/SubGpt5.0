# ---------- 1) FRONTEND BUILD ----------
FROM node:20-alpine AS front
WORKDIR /frontend
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# ---------- 2) BACKEND (composer) ----------
FROM composer:2 AS vendor
WORKDIR /app
# Сначала зависимости — кэш слоёв
COPY backend/composer.json backend/composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --prefer-dist --no-scripts
# Затем код и перегенерация автозагрузки (если есть post-* скрипты)
COPY backend/ ./
RUN composer install --no-dev --no-interaction --no-progress --prefer-dist \
 && composer dump-autoload -o

# ---------- 3) RUNTIME: PHP-FPM + NGINX + SUPERVISORD ----------
FROM php:8.3-fpm-alpine AS runtime

# Пакеты и расширения PHP
RUN apk add --no-cache \
      nginx supervisor curl git bash icu-dev libpq-dev oniguruma-dev \
  && docker-php-ext-configure intl \
  && docker-php-ext-install intl pdo_pgsql bcmath opcache

# Рабочие директории и права
WORKDIR /var/www/html
RUN mkdir -p /run/nginx /var/log/supervisor /var/cache/nginx
# Кладём Laravel
COPY --from=vendor /app /var/www/html
# Кладём собранный фронт как статику SPA в public/
COPY --from=front /frontend/dist /var/www/html/public

# Конфиги
COPY deploy/nginx.conf /etc/nginx/http.d/default.conf
COPY deploy/supervisord.conf /etc/supervisord.conf
COPY deploy/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
 && chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord","-n","-c","/etc/supervisord.conf"]
