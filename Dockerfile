# ---------- 1) FRONTEND BUILD ----------
FROM node:20-alpine AS front
WORKDIR /frontend
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# ---------- 2) BACKEND (создаём Laravel skeleton) ----------
FROM composer:2 AS vendor
WORKDIR /app
ARG LARAVEL_VERSION=11.*
RUN composer create-project --no-dev --prefer-dist laravel/laravel:"${LARAVEL_VERSION}" .
# Накатываем поверх твои файлы (если есть)
COPY backend/ /app/
RUN composer install --no-dev --no-interaction --optimize-autoloader

# ---------- 3) RUNTIME: PHP-FPM + NGINX + SUPERVISORD ----------
FROM php:8.3-fpm-alpine AS runtime

RUN apk add --no-cache \
      nginx supervisor curl git bash icu-dev libpq-dev oniguruma-dev \
  && docker-php-ext-configure intl \
  && docker-php-ext-install intl pdo_pgsql bcmath opcache

WORKDIR /var/www/html
RUN mkdir -p /run/nginx /var/log/supervisor /var/cache/nginx

# Laravel скелет и твои оверлеи
COPY --from=vendor /app /var/www/html
# Готовая сборка фронта -> public/
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
