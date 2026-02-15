# ERA Scripts

Скрипты для управления разработкой проекта ERA.

## Настройка сервера

📖 **[Полная инструкция по настройке сервера Ubuntu 24 для деплоя](./SERVER_SETUP.md)**

Инструкция включает:
- Установку Ruby 3.2.2 через rbenv
- Настройку PostgreSQL
- Установку Passenger + Nginx
- Настройку системы для деплоя фронтенда и бэкенда
- Конфигурацию SSL и firewall

## Доступные скрипты

### Деплой

- [`deploy-frontend.sh`](#7-deploy-frontendsh---деплой-фронтенда-на-production-сервер) - Деплой фронтенда на production (base-game / vassals-and-robbers / artel)
- [`deploy-backend.sh`](#8-deploy-backendsh---деплой-бэкенда-на-production-сервер) - Деплой бэкенда на production (base-game / vassals-and-robbers / artel)
- [`deploy-artel.sh`](deploy-artel.sh) - Деплой бэкенда с игрой Artel (без выбора версии)
- [`seed-artel.sh`](seed-artel.sh) - Заливка сидов движка Artel (локально или на сервере)

### Разработка

### 1. `start-dev.sh` - Интерактивный запуск

Запускает все компоненты системы с выбором игры и настройками.

```bash
./era_scripts/start-dev.sh
```

**Интерактивные опции:**
1. Выбор игры (base-game, vassals-and-robbers или artel)
2. Запуск мобильного приложения (да/нет)
3. Сборка на Android устройство (если выбран запуск мобильного)
4. Выбор Android устройства (если их несколько)

**Что запускается:**
- Backend (Rails) на `http://<IP>:3000`
- Frontend (Vite) на `http://<IP>:5173`
- Mobile (React Native Metro) - опционально

**Переменные окружения:**
- `ACTIVE_GAME` - активная игра для backend
- `VITE_ACTIVE_GAME` - активная игра для frontend
- `ACTIVE_GAME` (в era_native/.env) - активная игра для mobile

### 2. `start-base-game.sh` - Быстрый запуск базовой игры

Запускает систему с базовой игрой (Era of Change) без интерактивных вопросов.

```bash
./era_scripts/start-base-game.sh
```

**Опции:**
```bash
# Запустить без мобильного приложения
./era_scripts/start-base-game.sh --skip-mobile
```

### 3. `start-vassals-game.sh` - Быстрый запуск Vassals and Robbers

Запускает систему с игрой Vassals and Robbers без интерактивных вопросов.

```bash
./era_scripts/start-vassals-game.sh
```

**Опции:**
```bash
# Запустить без мобильного приложения
./era_scripts/start-vassals-game.sh --skip-mobile
```

### 4. `start-artel-game.sh` - Быстрый запуск Artel

Запускает систему с игрой Artel без интерактивных вопросов.

```bash
./era_scripts/start-artel-game.sh
```

**Опции:**
```bash
# Запустить без мобильного приложения
./era_scripts/start-artel-game.sh --skip-mobile
```

### 5. `build-prod.sh` - Сборка продакшн версии era_native

Собирает era_native приложение с продакшн-конфигурацией (подключение к https://epoha.igroteh.su/backend/ с Basic Auth).

```bash
./era_scripts/build-prod.sh
```

**Интерактивные опции:**
1. Тип сборки: Android APK/AAB или iOS
2. Для Android: Debug или Release APK, или AAB для Google Play

**Что делает:**
- Обновляет `era_native/src/config.ts` с продакшн-настройками
- Добавляет Basic Auth (Login: Anton, Password: aoFa4-cah)
- Запускает сборку выбранного типа

**Примечание:** После использования build-prod.sh для возврата к dev-режиму запустите `./era_scripts/start-dev.sh`

### 6. `stop-dev.sh` - Остановка всех сервисов

Останавливает tmux сессию со всеми запущенными сервисами.

```bash
./era_scripts/stop-dev.sh
```

### 7. `deploy-frontend.sh` - Деплой фронтенда на production сервер

Собирает фронтенд локально и загружает готовый `dist` на production сервер.

```bash
./era_scripts/deploy-frontend.sh
```

**Что делает:**
1. Интерактивный выбор версии игры (base-game, vassals-and-robbers или artel)
2. Локальная сборка фронтенда с правильной настройкой `.env`
3. Загрузка собранного `dist` на сервер через `rsync`
4. Создание release директории и симлинка `current`
5. Очистка старых releases (оставляет последние 3)

**Конфигурация:**
- Сервер задается через переменную окружения `FRONTEND_DEPLOY_SERVER` (по умолчанию `62.173.148.168`)
- Пользователь: `deploy`
- Путь на сервере: `/opt/era/era_front`
- Backend URL: `https://epoha.igroteh.su/backend`

**Примеры использования:**
```bash
# Использовать сервер по умолчанию
./era_scripts/deploy-frontend.sh

# Использовать другой сервер
FRONTEND_DEPLOY_SERVER=staging.example.com ./era_scripts/deploy-frontend.sh
```

**Примечание:** Существует альтернативный вариант деплоя через Capistrano:
```bash
cd eraofchange
cap production frontend:deploy          # для base-game
cap production frontend:deploy_vassals # для vassals-and-robbers
```

### 8. `deploy-backend.sh` - Деплой бэкенда на production сервер

Деплоит бэкенд (Rails приложение) на production сервер без использования Capistrano.

```bash
./era_scripts/deploy-backend.sh
```

**Что делает:**
1. Интерактивный выбор версии игры (base-game, vassals-and-robbers или artel)
2. Клонирование кода из репозитория на сервер (ветка `depl`)
3. Установка зависимостей через Bundler
4. Настройка конфигурационных файлов (database.yml, master.key, .env.production)
5. Создание симлинков для shared файлов и директорий
6. Остановка Passenger
7. Выполнение миграций базы данных
8. Запуск сидов (для vassals-and-robbers и artel — специфичные сиды выполняются вручную при необходимости, см. seed-artel.sh)
9. Обновление конфигурации Passenger (systemd)
10. Переключение на новый релиз через симлинк `current`
11. Запуск Passenger
12. Очистка старых releases (оставляет последние 3)

**Конфигурация:**
- Сервер задается через переменную окружения `BACKEND_DEPLOY_SERVER` (по умолчанию `62.173.148.168`)
- Пользователь: `deploy`
- Путь на сервере: `/opt/era/eraofchange`
- Ветка репозитория: `depl`
- Ruby версия: `3.2.2` (через rbenv)
- Passenger управляется через systemd

**Требования:**
- На сервере должны быть установлены: rbenv, Ruby 3.2.2, PostgreSQL
- Файлы `config/master.key` и `config/database_prod.yml` должны существовать локально (опционально, если они уже есть на сервере)
- SSH доступ к серверу с правами sudo для управления Passenger

**Примеры использования:**
```bash
# Использовать сервер по умолчанию
./era_scripts/deploy-backend.sh

# Использовать другой сервер
BACKEND_DEPLOY_SERVER=staging.example.com ./era_scripts/deploy-backend.sh
```

**Примечание:** Существует альтернативный вариант деплоя через Capistrano:
```bash
cd eraofchange
cap production backend:deploy          # для base-game
cap production backend:deploy_vassals   # для vassals-and-robbers
```

### 9. `get-ip.sh` - Определение IP адреса

Утилита для автоматического определения IP адреса системы.

```bash
source ./era_scripts/get-ip.sh
echo $DEV_IP
```

## Tmux управление

После запуска скриптов создаётся tmux сессия `era-dev` с разделёнными панелями:

**Структура панелей:**
```
┌─────────────────────────────┐
│   Backend (Rails)           │
├─────────────┬───────────────┤
│  Frontend   │   Mobile      │
│  (Vite)     │ (React Native)│
└─────────────┴───────────────┘
```

**Полезные команды tmux:**
```bash
# Подключиться к сессии
tmux attach -t era-dev

# Отключиться от сессии (не останавливая её)
Ctrl+B, затем D

# Переключение между панелями
Ctrl+B, затем стрелки

# Остановить сессию
tmux kill-session -t era-dev
# или используйте скрипт:
./era_scripts/stop-dev.sh
```

## Настройка переменных окружения

### Автоматическая настройка

Скрипты автоматически создают/обновляют следующие файлы:

**Backend (eraofchange/):**
- Переменная `ACTIVE_GAME` устанавливается через export в tmux

**Frontend (era_front/):**
- `era_front/.env.development` - с `VITE_ACTIVE_GAME`

**Mobile (era_native/):**
- `era_native/.env` - с `ACTIVE_GAME`
- `era_native/src/config.ts` - с `BACKEND_URL` и `BASIC_AUTH` (только в продакшн-режиме)

### Ручная настройка

Если нужно запустить приложения отдельно:

**Backend:**
```bash
cd eraofchange
ACTIVE_GAME=vassals-and-robbers rails server
# или для Artel:
ACTIVE_GAME=artel rails server
```

**Frontend:**
```bash
cd era_front
VITE_ACTIVE_GAME=vassals-and-robbers pnpm dev
# или для Artel:
VITE_ACTIVE_GAME=artel pnpm dev
```

**Mobile:**
```bash
cd era_native
# Создайте .env файл с ACTIVE_GAME=vassals-and-robbers
npm run android
```

## Примеры использования

### Пример 1: Разработка базовой игры

```bash
# Быстрый запуск базовой игры
./era_scripts/start-base-game.sh

# Или интерактивно
./era_scripts/start-dev.sh
# Выбрать: 1 (base-game)
```

### Пример 2: Разработка Vassals and Robbers

```bash
# Быстрый запуск новой игры
./era_scripts/start-vassals-game.sh

# Или интерактивно
./era_scripts/start-dev.sh
# Выбрать: 2 (vassals-and-robbers)
```

### Пример 2.1: Разработка Artel

```bash
# Быстрый запуск
./era_scripts/start-artel-game.sh

# Или интерактивно
./era_scripts/start-dev.sh
# Выбрать: 3 (artel)
```

Заливка сидов Artel (локально или на сервере):
```bash
./era_scripts/seed-artel.sh
```

### Пример 3: Только backend и frontend (без mobile)

```bash
# Базовая игра без mobile
./era_scripts/start-base-game.sh --skip-mobile

# Vassals game без mobile
./era_scripts/start-vassals-game.sh --skip-mobile

# Artel без mobile
./era_scripts/start-artel-game.sh --skip-mobile

# Интерактивно
./era_scripts/start-dev.sh
# Выбрать игру (1–3), затем выбрать: 2 (не запускать mobile)
```

### Пример 4: Запуск на конкретное Android устройство

```bash
./era_scripts/start-dev.sh
# Выбрать игру
# Выбрать: 1 (запустить mobile)
# Выбрать: 1 (запустить на Android)
# Выбрать номер устройства из списка
```

## Логи и отладка

### Просмотр логов в tmux

После подключения к сессии (`tmux attach -t era-dev`):

- **Backend (верхняя панель)** - логи Rails
- **Frontend (нижняя левая)** - логи Vite
- **Mobile (нижняя правая)** - логи Metro bundler

### Переключение между панелями

```
Ctrl+B, затем ↑  - перейти на backend
Ctrl+B, затем ↓  - перейти на frontend/mobile
Ctrl+B, затем ←  - перейти на frontend
Ctrl+B, затем →  - перейти на mobile
```

### Прокрутка истории в панели

```
Ctrl+B, затем [  - войти в режим прокрутки
↑↓ или PgUp/PgDn - прокрутка
q                 - выйти из режима прокрутки
```

## Порты по умолчанию

- Backend: `3000`
- Frontend: `5173`
- Mobile Metro: `8081` (автоматически)

Можно изменить через переменные окружения:
```bash
export BACKEND_PORT=4000
export FRONTEND_PORT=5174
./era_scripts/start-dev.sh
```

## Файлы конфигурации

После запуска скриптов автоматически создаются/обновляются:

```
era/
├── .env                                   # Общие переменные
├── era_front/
│   └── .env.development                   # VITE_ACTIVE_GAME, VITE_PROXY
├── era_native/
│   ├── .env                               # ACTIVE_GAME, BACKEND_URL
│   └── src/config.ts                      # BACKEND_URL (автоген)
```

## Требования

- **tmux** - для управления сессиями
- **rvm** - для backend (Ruby)
- **pnpm** - для frontend (или npm)
- **npm** - для mobile
- **Android SDK** - для запуска на Android (опционально)

## Устранение проблем

### Порт уже занят

```bash
# Остановите текущую сессию
./era_scripts/stop-dev.sh

# Или найдите и убейте процесс на порту
lsof -ti:3000 | xargs kill -9
lsof -ti:5173 | xargs kill -9
```

### Ошибка сборки Android

1. Проверьте подключение устройства: `adb devices`
2. Убедитесь, что отладка по USB включена
3. Попробуйте перезапустить adb: `adb kill-server && adb start-server`

### Плагин не загружается

1. Проверьте, что выбрали правильную игру при запуске
2. Просмотрите логи в соответствующей панели tmux
3. Проверьте переменные окружения в каждом приложении

