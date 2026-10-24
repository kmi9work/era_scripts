# Исправление конфигурации Nginx для фронтенда

## Проблема

После деплоя фронтенда через `deploy-frontend.sh` сервер возвращает 404 ошибку.

## Причина

В конфигурации Nginx (`/etc/nginx/sites-available/epoha.igroteh.su`) указан неправильный путь `root /var/www/era;`, а файлы загружены в `/opt/era/era_front/current`.

## Решение

### 1. Отредактировать конфигурацию Nginx

```bash
sudo nano /etc/nginx/sites-available/epoha.igroteh.su
```

### 2. Изменить секцию для фронтенда

Найти:
```nginx
        root /var/www/era;

        location / {
           index index.html;
        }
```

Заменить на:
```nginx
        root /opt/era/era_front/current;

        location / {
           index index.html;
           try_files $uri $uri/ /index.html;
        }
```

### 3. Полная рекомендуемая конфигурация

Если нужно полностью обновить конфигурацию:

```nginx
server {
   listen  62.173.148.168:80;
   server_name  epoha.igroteh.su;

   location / {
      return 301 https://epoha.igroteh.su$request_uri;
   }
}

server {
        listen          62.173.148.168:443 ssl;
        server_name     epoha.igroteh.su;
        server_name_in_redirect  off;

        auth_basic "Restricted area";
        auth_basic_user_file /etc/nginx/auth/passwd;

        access_log  /var/log/nginx/epoha.igroteh.su.log;

        ssl_certificate      /etc/letsencrypt/live/epoha.igroteh.su/fullchain.pem;
        ssl_certificate_key  /etc/letsencrypt/live/epoha.igroteh.su/privkey.pem;
        add_header Strict-Transport-Security 'max-age=15552000';

        # Исправленный путь к фронтенду
        root /opt/era/era_front/current;

        # Обработка статических файлов фронтенда
        location / {
           index index.html;
           try_files $uri $uri/ /index.html;
        }

        # Конфигурация для бэкенда (Rails через Passenger)
        location /backend {
            alias /opt/era/eraofchange/current/public;
            passenger_base_uri /backend;
            passenger_app_root /opt/era/eraofchange/current;
            passenger_enabled on;
            passenger_ruby /home/deploy/.rbenv/shims/ruby;
            passenger_app_env production;
        }

        # Статические файлы Rails (assets)
        location ~ ^/backend/assets/ {
            alias /opt/era/eraofchange/current/public/assets;
            expires 1y;
            add_header Cache-Control public;
            add_header ETag "";
            break;
        }
}
```

### 4. Проверить и перезагрузить Nginx

```bash
# Проверка конфигурации
sudo nginx -t

# Перезагрузка Nginx
sudo systemctl reload nginx
# или
sudo nginx -s reload
```

### 5. Проверить права доступа

```bash
# Убедиться, что Nginx может читать файлы
sudo chmod -R 755 /opt/era/era_front/current
sudo chown -R deploy:deploy /opt/era/era_front/current

# Проверить, что файлы доступны
ls -la /opt/era/era_front/current/index.html
```

### 6. Проверить логи при необходимости

```bash
# Логи ошибок Nginx
sudo tail -f /var/log/nginx/error.log

# Логи доступа
sudo tail -f /var/log/nginx/epoha.igroteh.su.log
```

## Быстрое исправление одной командой

Если нужно только изменить `root` путь:

```bash
sudo sed -i 's|root /var/www/era;|root /opt/era/era_front/current;|' /etc/nginx/sites-available/epoha.igroteh.su
sudo nginx -t && sudo systemctl reload nginx
```

## Проверка после исправления

Откройте в браузере `https://epoha.igroteh.su/` - должна открыться главная страница фронтенда.

## Раздача APK (`/apk/`)

APK для планшетов лежат в `/opt/era/era_front/downloads` (их загружает `build-prod.sh`), а внутри
текущего релиза на каталог указывает симлинк `apk -> ../../downloads`, который пересоздаёт
`deploy-frontend.sh`. Это работает без правки nginx, но у `location /` есть SPA-заглушка
(`try_files $uri $uri/ /index.html`): на несуществующий `/apk/era-vassals.apk` сервер отвечает
`200 text/html` вместо `404`. Браузер в этом случае скачает HTML-файл с именем `.apk`.

Чтобы отсутствующий файл давал честный 404 и правильный MIME-тип, добавьте в `server`-блок
`epoha.igroteh.su` (после `location /backend`) отдельную локацию:

```nginx
    # APK для планшетов: файлы вне релизов фронта
    location ^~ /apk/ {
        alias /opt/era/era_front/downloads/;
        types { application/vnd.android.package-archive apk; }
    }
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Проверка (Basic Auth сайта сохраняется — она задана на уровне всего `server`):

```bash
curl -u Anton:<пароль> -I https://epoha.igroteh.su/apk/era-base.apk        # 200, content-type: application/vnd.android.package-archive
curl -u Anton:<пароль> -I https://epoha.igroteh.su/apk/era-vassals.apk    # 404, если версия не загружена
```

Приложение era_front не зависит от этой правки: перед показом ссылки оно делает HEAD-запрос и
помечает пункт «не опубликовано», если по ссылке отдаётся HTML.

