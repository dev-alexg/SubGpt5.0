#!/usr/bin/env bash
set -euo pipefail

# ==== Настройки (поменяй под себя, если хочешь автопуш в GitHub) ====
GIT_INIT=${GIT_INIT:-1}          # 1 = сделать git init
GIT_PUSH=${GIT_PUSH:-0}          # 1 = сразу создать удалённый и push (нужен gh или уже созданный репозиторий)
REPO_NAME=${REPO_NAME:-laravel-vue-monorepo}
GITHUB_USER=${GITHUB_USER:-your-gh-user}   # если GIT_PUSH=1 и используешь gh CLI
REMOTE_URL=${REMOTE_URL:-}       # если хочешь явно задать удалённый, например: git@github.com:user/repo.git

# ==== Структура ====
mkdir -p backend/routes backend/app/Providers backend/public frontend/src deploy

# ---- Dockerfile ----
cat > Dockerfile <<'EOF'
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
EOF

# ---- .dockerignore ----
cat > .dockerignore <<'EOF'
.git
.gitignore
node_modules
frontend/node_modules
backend/vendor
dist
deploy/*.example
EOF

# ---- deploy/nginx.conf ----
cat > deploy/nginx.conf <<'EOF'
server {
    listen 80 default_server;
    server_name _;

    root /var/www/html/public;
    index index.php index.html;

    location ~* \.(?:js|css|png|jpg|jpeg|gif|svg|ico|woff2?)$ {
        try_files $uri =404;
        expires 7d;
        add_header Cache-Control "public, max-age=604800, immutable";
    }

    location ^~ /api {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        try_files $uri =404;
        include fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_read_timeout 120;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt  { log_not_found off; access_log off; }
}
EOF

# ---- deploy/supervisord.conf ----
cat > deploy/supervisord.conf <<'EOF'
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log

[program:php-fpm]
command=/usr/local/sbin/php-fpm -F
autostart=true
autorestart=true
priority=10
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
priority=20
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
EOF

# ---- deploy/entrypoint.sh ----
cat > deploy/entrypoint.sh <<'EOF'
#!/usr/bin/env bash
set -e

cd /var/www/html

php artisan key:generate --force || true
php artisan storage:link || true

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

exec "$@"
EOF
chmod +x deploy/entrypoint.sh

# ---- backend/.env.example ----
cat > backend/.env.example <<'EOF'
APP_NAME="Timweb App"
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=https://example.com
APP_FORCE_HTTPS=true

LOG_CHANNEL=stack
LOG_LEVEL=info

DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=app
DB_USERNAME=app
DB_PASSWORD=secret

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120
EOF

# ---- backend/routes/api.php ----
cat > backend/routes/api.php <<'EOF'
<?php

use Illuminate\Support\Facades\Route;

Route::get('/health', fn () => [
    'status' => 'ok',
    'time' => now()->toISOString(),
]);

Route::get('/env', fn () => [
    'app' => config('app.name'),
    'url' => config('app.url'),
]);
EOF

# ---- backend/routes/web.php ----
cat > backend/routes/web.php <<'EOF'
<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return response('<h1>Laravel API</h1><p>Фронт (Vue) отдается из /public.</p>', 200);
});
EOF

# ---- backend/app/Providers/AppServiceProvider.php ----
mkdir -p backend/app/Providers
cat > backend/app/Providers/AppServiceProvider.php <<'EOF'
<?php

namespace App\Providers;

use Illuminate\Support\Facades\URL;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        if (env('APP_FORCE_HTTPS', true)) {
            URL::forceScheme('https');
        }
    }
}
EOF

# ---- frontend/package.json ----
cat > frontend/package.json <<'EOF'
{
  "name": "frontend",
  "private": true,
  "version": "0.0.1",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview --port 4173"
  },
  "dependencies": {
    "axios": "^1.7.0",
    "vue": "^3.4.0"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^5.0.0",
    "typescript": "^5.4.0",
    "vite": "^5.0.0",
    "vue-tsc": "^1.8.0"
  }
}
EOF

# ---- frontend/vite.config.ts ----
cat > frontend/vite.config.ts <<'EOF'
import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'node:path'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  return {
    plugins: [vue()],
    resolve: { alias: { '@': path.resolve(__dirname, 'src') } },
    server: {
      port: 5173,
      strictPort: true,
      proxy: {
        '/api': {
          target: env.VITE_PROXY_API || 'http://localhost:8000',
          changeOrigin: true
        }
      }
    },
    build: { outDir: 'dist', sourcemap: false, emptyOutDir: true }
  }
})
EOF

# ---- frontend/index.html ----
cat > frontend/index.html <<'EOF'
<!doctype html>
<html lang="ru">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Vue App</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.ts"></script>
  </body>
</html>
EOF

# ---- frontend/src/main.ts ----
cat > frontend/src/main.ts <<'EOF'
import { createApp } from 'vue'
import App from './App.vue'

createApp(App).mount('#app')
EOF

# ---- frontend/src/App.vue ----
cat > frontend/src/App.vue <<'EOF'
<script setup lang="ts">
import { onMounted, ref } from 'vue'
import axios from 'axios'

const apiBase = import.meta.env.VITE_API_URL || ''
const health = ref<any>(null)
const error = ref<string>('')

onMounted(async () => {
  try {
    const { data } = await axios.get(`${apiBase}/api/health`)
    health.value = data
  } catch (e: any) {
    error.value = e?.message || 'Request failed'
  }
})
</script>

<template>
  <main style="font-family: system-ui; padding: 2rem; max-width: 720px; margin: auto;">
    <h1>Vue + Laravel</h1>
    <p>API base: <code>{{ import.meta.env.VITE_API_URL || '(same origin)' }}</code></p>

    <section v-if="health">
      <h2>Health</h2>
      <pre>{{ health }}</pre>
    </section>
    <section v-else-if="error">
      <h2>Ошибка запроса</h2>
      <pre>{{ error }}</pre>
    </section>
    <section v-else>
      <em>Загрузка...</em>
    </section>
  </main>
</template>

<style scoped>
pre {
  background: #f6f8fa;
  padding: 12px;
  border-radius: 8px;
  overflow: auto;
}
</style>
EOF

# ---- frontend/src/env.d.ts ----
cat > frontend/src/env.d.ts <<'EOF'
/// <reference types="vite/client" />
EOF

# ---- frontend/tsconfig.json ----
cat > frontend/tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "jsx": "preserve",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "lib": ["ES2020", "DOM"],
    "baseUrl": ".",
    "paths": { "@/*": ["src/*"] }
  },
  "include": ["src"]
}
EOF

# ---- git init / первый коммит ----
if [[ "$GIT_INIT" == "1" ]]; then
  git init
  git add .
  git commit -m "Bootstrap Laravel+Vue monorepo for Timeweb Apps"
  git branch -M main
  if [[ "$GIT_PUSH" == "1" ]]; then
    if [[ -n "$REMOTE_URL" ]]; then
      git remote add origin "$REMOTE_URL"
      git push -u origin main
    else
      if command -v gh >/dev/null 2>&1; then
        gh repo create "$GITHUB_USER/$REPO_NAME" --public --source=. --remote=origin --push
      else
        echo "⚠️  gh CLI не найден. Либо установи gh, либо задай REMOTE_URL=git@github.com:user/repo.git и запусти повторно с GIT_PUSH=1."
      fi
    fi
  fi
fi

echo "✅ Готово. Файлы созданы."
echo "Дальше: добавь переменные окружения в Timeweb Apps (пример ниже) и деплой."
