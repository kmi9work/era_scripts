# ERA Scripts

Скрипты для управления разработкой проекта ERA.

## Доступные скрипты

### 1. `start-dev.sh` - Интерактивный запуск

Запускает все компоненты системы с выбором игры и настройками.

```bash
./era_scripts/start-dev.sh
```

**Интерактивные опции:**
1. Выбор игры (base-game или vassals-and-robbers)
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

### 4. `stop-dev.sh` - Остановка всех сервисов

Останавливает tmux сессию со всеми запущенными сервисами.

```bash
./era_scripts/stop-dev.sh
```

### 5. `get-ip.sh` - Определение IP адреса

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
- `era_native/src/config.ts` - с `BACKEND_URL`

### Ручная настройка

Если нужно запустить приложения отдельно:

**Backend:**
```bash
cd eraofchange
ACTIVE_GAME=vassals-and-robbers rails server
```

**Frontend:**
```bash
cd era_front
VITE_ACTIVE_GAME=vassals-and-robbers pnpm dev
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

### Пример 3: Только backend и frontend (без mobile)

```bash
# Базовая игра без mobile
./era_scripts/start-base-game.sh --skip-mobile

# Vassals game без mobile
./era_scripts/start-vassals-game.sh --skip-mobile

# Интерактивно
./era_scripts/start-dev.sh
# Выбрать игру, затем выбрать: 2 (не запускать mobile)
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

