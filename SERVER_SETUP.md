# Инструкция по настройке сервера Ubuntu 24 для ERA проекта

Полная инструкция по настройке production сервера для деплоя фронтенда и бэкенда ERA проекта.

## Требования

- Ubuntu 24.04 LTS
- Пользователь с правами sudo
- Доступ к интернету для установки пакетов
- SSH доступ к серверу

## 1. Подготовка системы и создание пользователя

### 1.1 Обновление системы

```bash
sudo apt update && sudo apt upgrade -y
```

### 1.2 Создание пользователя deploy

```bash
# Создание пользователя
sudo adduser deploy

# Добавление в группу sudo
sudo usermod -aG sudo deploy

# Переключение на пользователя deploy
su - deploy
```

### 1.3 Настройка SSH ключей

```bash
# Создание директории для SSH ключей
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Добавление публичного ключа для доступа к GitHub
# Скопируйте ваш публичный SSH ключ в ~/.ssh/authorized_keys
nano ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Или добавьте ключ с локальной машины:
# ssh-copy-id deploy@SERVER_IP
```

## 2. Установка Ruby 3.2.2 через rbenv

### 2.1 Установка зависимостей

```bash
sudo apt install -y git curl libssl-dev libreadline-dev zlib1g-dev \
  autoconf bison build-essential libyaml-dev libreadline-dev \
  libncurses5-dev libffi-dev libgdbm-dev libpq-dev
```

### 2.2 Установка rbenv

```bash
# От пользователя deploy
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash

# Добавление в ~/.bashrc
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init - bash)"' >> ~/.bashrc

# Перезагрузка конфигурации
source ~/.bashrc
```

### 2.3 Установка Ruby 3.2.2

```bash
# Установка Ruby
rbenv install 3.2.2
rbenv global 3.2.2

# Проверка
ruby -v  # Должно показать: ruby 3.2.2...
```

## 3. Установка PostgreSQL

### 3.1 Установка PostgreSQL

```bash
sudo apt install -y postgresql postgresql-contrib

# Проверка статуса
sudo systemctl status postgresql
```

### 3.2 Настройка базы данных

```bash
# Переключение на пользователя postgres
sudo -u postgres psql

# Создание пользователя и базы данных
CREATE USER deploy WITH PASSWORD 'your_secure_password_here';
ALTER USER deploy CREATEDB;
\q
```

**Важно:** Сохраните пароль базы данных - он понадобится для файла `config/database.key` в проекте.

## 4. Установка Passenger + Nginx

### 4.1 Установка Passenger

```bash
# Установка ключа репозитория
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 561F9B9CAC40B2F7

# Установка репозитория (для Ubuntu 24.04 / focal)
sudo sh -c 'echo deb https://oss-binaries.phusionpassenger.com/apt/passenger focal main > /etc/apt/sources.list.d/passenger.list'

# Обновление списка пакетов
sudo apt update

# Установка Passenger и Nginx
sudo apt install -y nginx-extras passenger
```

### 4.2 Настройка Passenger в Nginx

```bash
# Редактирование конфигурации Nginx
sudo nano /etc/nginx/nginx.conf
```

Найдите секцию `http` и добавьте (или раскомментируйте):

```nginx
http {
    ...
    passenger_root /usr/lib/ruby/vendor_ruby/phusion_passenger/locations.ini;
    passenger_ruby /home/deploy/.rbenv/shims/ruby;
    ...
}
```

### 4.3 Создание systemd service для Passenger

```bash
sudo nano /etc/systemd/system/passenger.service
```

Добавьте содержимое:

```ini
[Unit]
Description=Phusion Passenger
After=network.target

[Service]
Type=forking
PIDFile=/var/run/passenger.pid
ExecStart=/usr/sbin/passenger start
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s TERM $MAINPID
TimeoutStopSec=30
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Активация сервиса:

```bash
sudo systemctl daemon-reload
sudo systemctl enable passenger
```

## 5. Настройка Nginx для приложения

### 5.1 Создание конфигурации Nginx

```bash
sudo nano /etc/nginx/sites-available/eraofchange
```

Добавьте конфигурацию:

```nginx
server {
    listen 80;
    server_name epoha.igroteh.su;  # или ваш домен
    
    # Корневая директория для статических файлов фронтенда
    root /opt/era/era_front/current;
    
    # Конфигурация для бэкенда (Rails)
    location /backend {
        alias /opt/era/eraofchange/current/public;
        passenger_base_uri /backend;
        passenger_app_root /opt/era/eraofchange/current;
        passenger_enabled on;
        passenger_ruby /home/deploy/.rbenv/shims/ruby;
        passenger_app_env production;
    }
    
    # Обработка статических файлов фронтенда
    location / {
        alias /opt/era/era_front/current/;
        try_files $uri $uri/ /index.html;
    }
    
    # Статические файлы Rails (assets)
    location ~ ^/backend/assets/ {
        alias /opt/era/eraofchange/current/public/assets;
        expires 1y;
        add_header Cache-Control public;
        add_header ETag "";
        break;
    }
    
    # Логи
    access_log /var/log/nginx/eraofchange_access.log;
    error_log /var/log/nginx/eraofchange_error.log;
}
```

### 5.2 Активация сайта

```bash
# Создание симлинка
sudo ln -s /etc/nginx/sites-available/eraofchange /etc/nginx/sites-enabled/

# Проверка конфигурации
sudo nginx -t

# Перезагрузка Nginx
sudo systemctl restart nginx
```

## 6. Установка Node.js v22 через nvm (для Capistrano деплоя фронтенда, опционально)

Если вы планируете использовать Capistrano для деплоя фронтенда (старый способ), установите Node.js:

```bash
# От пользователя deploy
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Добавление в ~/.bashrc
echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc

# Перезагрузка конфигурации
source ~/.bashrc

# Установка Node.js v22
nvm install v22
nvm use v22
nvm alias default v22

# Проверка
node --version  # Должно показать: v22.x.x
```

**Примечание:** Если вы используете новый скрипт `deploy-frontend.sh`, Node.js на сервере не нужен.

### 6.1 Установка pnpm (опционально, только для Capistrano деплоя)

```bash
curl -fsSL https://get.pnpm.io/install.sh | sh -

# Проверка
~/.local/share/pnpm/pnpm --version
```

## 7. Создание директорий для деплоя

```bash
# Создание директорий
sudo mkdir -p /opt/era/eraofchange
sudo mkdir -p /opt/era/era_front

# Установка прав доступа
sudo chown -R deploy:deploy /opt/era

# Создание поддиректорий для бэкенда
mkdir -p /opt/era/eraofchange/shared/config
mkdir -p /opt/era/eraofchange/shared/tmp/sockets
mkdir -p /opt/era/eraofchange/shared/tmp/pids
mkdir -p /opt/era/eraofchange/shared/public/uploads
mkdir -p /opt/era/eraofchange/shared/log

# Создание поддиректорий для фронтенда
mkdir -p /opt/era/era_front/releases
```

## 8. Настройка секретов и конфигурации

### 8.1 Подготовка файлов на локальной машине

На вашей локальной машине должны быть следующие файлы:

```
eraofchange/
├── config/
│   ├── master.key          # Rails master key
│   ├── database.key        # Пароль базы данных (строка с паролем)
│   └── database_prod.yml   # Конфигурация базы данных для production
```

Эти файлы будут автоматически загружены на сервер при первом деплое через Capistrano.

### 8.2 Ручная загрузка секретов (альтернатива)

Если нужно загрузить вручную:

```bash
# С локальной машины
scp eraofchange/config/master.key deploy@SERVER_IP:/opt/era/eraofchange/shared/config/
scp eraofchange/config/database_prod.yml deploy@SERVER_IP:/opt/era/eraofchange/shared/config/database.yml

# На сервере
chmod 640 /opt/era/eraofchange/shared/config/master.key
```

## 9. Настройка firewall (опционально)

```bash
# Установка UFW (если не установлен)
sudo apt install -y ufw

# Разрешение SSH
sudo ufw allow 22/tcp

# Разрешение HTTP и HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Включение firewall
sudo ufw enable

# Проверка статуса
sudo ufw status
```

## 10. Настройка SSL сертификата (Let's Encrypt, опционально)

```bash
# Установка Certbot
sudo apt install -y certbot python3-certbot-nginx

# Получение сертификата
sudo certbot --nginx -d epoha.igroteh.su

# Автоматическое обновление (настроено автоматически)
```

## 11. Проверка настройки

### 11.1 Проверка Ruby

```bash
ruby -v
which ruby  # Должно показать: /home/deploy/.rbenv/shims/ruby
```

### 11.2 Проверка PostgreSQL

```bash
# Проверка подключения
psql -U deploy -d postgres -c "SELECT version();"
```

### 11.3 Проверка Passenger

```bash
sudo systemctl status passenger
```

### 11.4 Проверка Nginx

```bash
sudo systemctl status nginx
sudo nginx -t
```

## 12. Первый деплой

### 12.1 Деплой бэкенда

С локальной машины:

```bash
cd eraofchange
cap production backend:deploy
```

### 12.2 Деплой фронтенда (новый способ)

С локальной машины:

```bash
./era_scripts/deploy-frontend.sh
```

### 12.3 Деплой фронтенда (старый способ через Capistrano)

С локальной машины:

```bash
cd eraofchange
cap production frontend:deploy          # для base-game
cap production frontend:deploy_vassals  # для vassals-and-robbers
```

## 13. Полезные команды для управления

### 13.1 Управление Passenger

```bash
# Статус
sudo systemctl status passenger

# Остановка
sudo systemctl stop passenger

# Запуск
sudo systemctl start passenger

# Перезапуск
sudo systemctl restart passenger
```

### 13.2 Управление Nginx

```bash
# Статус
sudo systemctl status nginx

# Перезапуск
sudo systemctl restart nginx

# Перезагрузка конфигурации
sudo nginx -s reload
```

### 13.3 Просмотр логов

```bash
# Логи бэкенда
tail -f /opt/era/eraofchange/shared/log/production.log

# Логи Nginx
sudo tail -f /var/log/nginx/eraofchange_error.log
sudo tail -f /var/log/nginx/eraofchange_access.log

# Логи Passenger
sudo journalctl -u passenger -f
```

## 14. Настройка автоматических бэкапов (рекомендуется)

### 14.1 Бэкап базы данных

```bash
# Создание скрипта бэкапа
sudo nano /usr/local/bin/backup-db.sh
```

Содержимое скрипта:

```bash
#!/bin/bash
BACKUP_DIR="/opt/backups/db"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="eraofchange_production"

mkdir -p "$BACKUP_DIR"
pg_dump -U deploy "$DB_NAME" | gzip > "$BACKUP_DIR/eraofchange_${DATE}.sql.gz"

# Удаление бэкапов старше 7 дней
find "$BACKUP_DIR" -name "eraofchange_*.sql.gz" -mtime +7 -delete
```

```bash
chmod +x /usr/local/bin/backup-db.sh

# Добавление в crontab (каждый день в 2:00)
sudo crontab -e
# Добавить строку:
# 0 2 * * * /usr/local/bin/backup-db.sh
```

## 15. Мониторинг (опционально)

### 15.1 Установка htop для мониторинга системы

```bash
sudo apt install -y htop
htop
```

### 15.2 Проверка использования дискового пространства

```bash
df -h
du -sh /opt/era/*
```

## 16. Решение проблем

### 16.1 Passenger не запускается

```bash
# Проверка логов
sudo journalctl -u passenger -n 50

# Проверка прав доступа
ls -la /opt/era/eraofchange/current
```

### 16.2 Nginx выдает 502 Bad Gateway

```bash
# Проверка, что Passenger запущен
sudo systemctl status passenger

# Проверка прав на директорию приложения
sudo chown -R deploy:deploy /opt/era/eraofchange/current
```

### 16.3 Проблемы с базой данных

```bash
# Проверка подключения
psql -U deploy -d eraofchange_production

# Проверка существования базы
psql -U deploy -d postgres -c "\l"
```

## 17. Проверочный список

После настройки убедитесь, что:

- [ ] Ruby 3.2.2 установлен через rbenv
- [ ] PostgreSQL установлен и настроен пользователь deploy
- [ ] Passenger и Nginx установлены и настроены
- [ ] Директории `/opt/era/eraofchange` и `/opt/era/era_front` созданы
- [ ] Пользователь deploy имеет права на эти директории
- [ ] SSH ключи настроены для доступа к GitHub
- [ ] Systemd service для Passenger создан и активирован
- [ ] Nginx конфигурация создана и активирована
- [ ] Firewall настроен (если используется)
- [ ] SSL сертификат установлен (если используется)
- [ ] Первый деплой выполнен успешно

## Контакты и дополнительная информация

- Документация Capistrano: https://capistranorb.com/
- Документация Passenger: https://www.phusionpassenger.com/docs/
- Документация Nginx: https://nginx.org/en/docs/

