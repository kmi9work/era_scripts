#!/bin/bash
# deploy-frontend.sh - Деплой фронтенда era_front на production сервер
# Сборка происходит локально, на сервер загружается готовый dist
# Игры не захардкожены: список плагинов берётся из era_front/src/plugins/game-plugins

set -e

# Get the directory where this script is located (era_scripts/)
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Get the project root directory (one level up)
PROJECT_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# Реестр игр: движки eraofchange/engines/* + плагины клиентов
# shellcheck source=lib/era-games.sh
source "$SCRIPTS_DIR/lib/era-games.sh"
era_build_registry

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FRONTEND_DIR="$PROJECT_DIR/era_front"
SERVER="${FRONTEND_DEPLOY_SERVER:-62.173.148.168}"
USER="deploy"
DEPLOY_PATH="/opt/era/era_front"
PROXY_URL="https://epoha.igroteh.su/backend"
# Mobile helper будет на new.igroteh.su и должен обращаться к epoha.igroteh.su/backend
# ВАЖНО: На бэкенде нужно настроить CORS, чтобы разрешить запросы с new.igroteh.su
MOBILE_PROXY_URL="https://epoha.igroteh.su/backend"
# Noble helper будет на noble.igroteh.su и должен обращаться к epoha.igroteh.su/backend
NOBLE_PROXY_URL="https://epoha.igroteh.su/backend"

# Check if era_front directory exists
if [ ! -d "$FRONTEND_DIR" ]; then
    echo -e "${RED}Error: era_front directory not found at $FRONTEND_DIR${NC}"
    exit 1
fi

# Parse optional command-line arguments
# Usage: ./deploy-frontend.sh [--game=<ключ|номер>] [--plugin=<имя плагина>] [--list]
#   ./deploy-frontend.sh                        # интерактивный выбор игры
#   ./deploy-frontend.sh --game=many-teams      # сразу нужная игра/плагин
#   ./deploy-frontend.sh --list                 # все движки и плагины
ANSWER_GAME=""
LIST_GAMES=0

usage() {
    cat <<'USAGE'
Usage: deploy-frontend.sh [--game=<ключ|номер>] [--plugin=<имя плагина>] [--list]

  Без аргументов — интерактивный выбор игры.
  --game    ключ игры (many-teams) или номер из меню
  --plugin  имя каталога плагина в era_front/src/plugins/game-plugins
  --list    показать все найденные движки, плагины и игры

Примеры:
  deploy-frontend.sh
  deploy-frontend.sh --game=many-teams
  deploy-frontend.sh --plugin=many_teams
USAGE
}

POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --list)      LIST_GAMES=1; shift ;;
        --game=*)    ANSWER_GAME="${1#*=}"; shift ;;
        --plugin=*)  ANSWER_GAME="${1#*=}"; shift ;;
        --engine=*)  ANSWER_GAME="${1#*=}"; shift ;;
        --game|--plugin|--engine)
                     ANSWER_GAME="${2:-}"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        --)          shift; POSITIONAL+=("$@"); break ;;
        -*)          echo "Неизвестный флаг: $1"; usage; exit 1 ;;
        *)           POSITIONAL+=("$1"); shift ;;
    esac
done
if [ ${#POSITIONAL[@]} -gt 0 ]; then
    set -- "${POSITIONAL[@]}"
else
    set --
fi

if [ "$LIST_GAMES" = "1" ]; then
    era_report
    exit 0
fi

echo -e "${BLUE}=== ERA Frontend Deployment ===${NC}\n"

# Ask user to choose game version (or use argument if provided)
if [ -n "$ANSWER_GAME" ]; then
    if ! era_resolve_game "$ANSWER_GAME"; then
        echo -e "${RED}Неизвестная игра: ${ANSWER_GAME}${NC}"
        echo ""
        era_list_games
        exit 1
    fi
else
    echo -e "${YELLOW}Выберите игру для деплоя:${NC}"
    era_list_games
    echo ""
    read -p "Выбор [1-${#ERA_GAME_KEYS[@]}]: " GAME_CHOICE
    if ! era_resolve_game "$GAME_CHOICE"; then
        echo -e "${RED}Неверный выбор игры.${NC}"
        exit 1
    fi
fi

GAME_VERSION="$ERA_GAME_KEY"

echo ""
echo -e "${GREEN}Выбрана игра: ${GAME_VERSION}${NC}"

# Плагин игры в era_front: сборка идёт из локального дерева, поэтому плагин
# обязан лежать в рабочей копии. Если он есть в другой ветке — это ошибка
# (соберётся ядро вместо игры), если его нет нигде — предупреждение (artel и т. п.).
PLUGIN_DIR="$(era_plugin_dir "$FRONTEND_DIR" "$GAME_VERSION" || true)"
if [ -n "$PLUGIN_DIR" ]; then
    echo -e "${GREEN}Плагин era_front: ${PLUGIN_DIR}${NC}\n"
elif [ "$GAME_VERSION" = "base-game" ]; then
    echo -e "${BLUE}Плагин не нужен: базовая игра${NC}\n"
else
    PLUGIN_BRANCH=""
    for CANDIDATE in "$GAME_VERSION" "${GAME_VERSION//-/_}"; do
        HEAD_BRANCH="$(git -C "$FRONTEND_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)"
        if FOUND="$(era_branch_for_path "$FRONTEND_DIR" "src/plugins/game-plugins/$CANDIDATE" "$HEAD_BRANCH" 2>/dev/null)"; then
            if era_branch_has_path "$FRONTEND_DIR" "$FOUND" "src/plugins/game-plugins/$CANDIDATE"; then
                PLUGIN_BRANCH="$FOUND"
                break
            fi
        fi
    done
    if [ -n "$PLUGIN_BRANCH" ]; then
        echo -e "${RED}Плагина игры ${GAME_VERSION} нет в рабочей копии era_front, но он есть в ветке ${PLUGIN_BRANCH}.${NC}"
        echo -e "${YELLOW}Переключите era_front на эту ветку (или выберите другую игру) и повторите деплой.${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Плагина игры ${GAME_VERSION} нет в era_front ни в одной ветке — фронт соберётся на ядре.${NC}\n"
fi

# Step 1: Install dependencies
echo -e "${BLUE}=== Шаг 1: Установка зависимостей ===${NC}"
cd "$FRONTEND_DIR"

# Install dependencies if needed
if [ ! -d "node_modules" ] || [ "package.json" -nt "node_modules" ]; then
    echo -e "${YELLOW}Установка зависимостей через pnpm...${NC}"
    pnpm install --ignore-scripts
    echo -e "${GREEN}✓ Зависимости установлены${NC}"
else
    echo -e "${GREEN}✓ Зависимости уже установлены${NC}"
fi

# Create timestamp for releases (used for both main app and mobile helper)
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# Step 2: Build mobile helper with separate proxy URL
echo -e "${BLUE}=== Шаг 2: Сборка merchant_mobile_helper с отдельным proxy ===${NC}"
MOBILE_DEPLOY_DIR="${FRONTEND_DIR}/dist_mobile_deploy"
MOBILE_DEPLOY_PATH="/opt/era/mer_calc"

# Create temporary directory for mobile deployment
rm -rf "${MOBILE_DEPLOY_DIR}"
mkdir -p "${MOBILE_DEPLOY_DIR}"

# Configure .env file for mobile helper build
echo -e "${YELLOW}Настройка .env файла для mobile helper...${NC}"
rm -f .env.local .env.development .env.production
cat > .env <<EOF
VITE_PROXY=${MOBILE_PROXY_URL}
VITE_ACTIVE_GAME=${GAME_VERSION}
EOF
cat > .env.production <<EOF
VITE_PROXY=${MOBILE_PROXY_URL}
VITE_ACTIVE_GAME=${GAME_VERSION}
EOF
echo -e "${GREEN}✓ .env файлы для mobile helper настроены${NC}"
echo -e "${BLUE}VITE_PROXY=${MOBILE_PROXY_URL}${NC}"

# Build mobile helper (Vite will process merchant_mobile_helper.html entry point)
echo -e "${YELLOW}Сборка mobile helper...${NC}"
rm -rf dist
NODE_ENV=production pnpm build

# Check if merchant_mobile_helper.html exists in dist
if [ ! -f "dist/merchant_mobile_helper.html" ]; then
    echo -e "${RED}Error: merchant_mobile_helper.html not found in dist after mobile build${NC}"
    exit 1
fi

# Copy merchant_mobile_helper.html and rename to index.html
cp "dist/merchant_mobile_helper.html" "${MOBILE_DEPLOY_DIR}/index.html"
echo -e "${GREEN}✓ merchant_mobile_helper.html скопирован${NC}"

# Copy all assets (JS, CSS, images, etc.) - these will have correct VITE_PROXY embedded
if [ -d "dist/assets" ]; then
    cp -r "dist/assets" "${MOBILE_DEPLOY_DIR}/assets"
    echo -e "${GREEN}✓ Assets скопированы${NC}"
fi

# Copy other static files that might be needed (favicon, images, etc.)
if [ -d "dist/images" ]; then
    cp -r "dist/images" "${MOBILE_DEPLOY_DIR}/images"
fi
if [ -f "dist/favicon.ico" ]; then
    cp "dist/favicon.ico" "${MOBILE_DEPLOY_DIR}/"
fi
if [ -f "dist/loader.css" ]; then
    cp "dist/loader.css" "${MOBILE_DEPLOY_DIR}/"
fi
if [ -f "dist/logo.png" ]; then
    cp "dist/logo.png" "${MOBILE_DEPLOY_DIR}/"
fi

# PWA-файлы (манифест, service worker, иконки) — без них calc.igroteh.su
# не сможет предложить установку приложения на экран
if [ -f "dist/manifest.webmanifest" ]; then
    cp "dist/manifest.webmanifest" "${MOBILE_DEPLOY_DIR}/"
fi
if [ -f "dist/sw.js" ]; then
    cp "dist/sw.js" "${MOBILE_DEPLOY_DIR}/"
fi
if [ -f "dist/pwa-192x192.png" ]; then
    cp "dist/pwa-192x192.png" "${MOBILE_DEPLOY_DIR}/"
fi
if [ -f "dist/pwa-512x512.png" ]; then
    cp "dist/pwa-512x512.png" "${MOBILE_DEPLOY_DIR}/"
fi

echo -e "${GREEN}✓ Mobile helper собран и подготовлен${NC}\n"

# Step 2.5: Build noble helper with separate proxy URL
echo -e "${BLUE}=== Шаг 2.5: Сборка noble_helper с отдельным proxy ===${NC}"
NOBLE_DEPLOY_DIR="${FRONTEND_DIR}/dist_noble_deploy"
NOBLE_DEPLOY_PATH="/opt/era/noble_helper"

# Create temporary directory for noble deployment
rm -rf "${NOBLE_DEPLOY_DIR}"
mkdir -p "${NOBLE_DEPLOY_DIR}"

# Configure .env file for noble helper build
echo -e "${YELLOW}Настройка .env файла для noble helper...${NC}"
rm -f .env.local .env.development .env.production
cat > .env <<EOF
VITE_PROXY=${NOBLE_PROXY_URL}
VITE_ACTIVE_GAME=${GAME_VERSION}
EOF
cat > .env.production <<EOF
VITE_PROXY=${NOBLE_PROXY_URL}
VITE_ACTIVE_GAME=${GAME_VERSION}
EOF
echo -e "${GREEN}✓ .env файлы для noble helper настроены${NC}"
echo -e "${BLUE}VITE_PROXY=${NOBLE_PROXY_URL}${NC}"

# Build noble helper (Vite will process noble_helper.html entry point)
echo -e "${YELLOW}Сборка noble helper...${NC}"
rm -rf dist
NODE_ENV=production pnpm build

# Check if noble_helper.html exists in dist
if [ ! -f "dist/noble_helper.html" ]; then
    echo -e "${RED}Error: noble_helper.html not found in dist after noble build${NC}"
    exit 1
fi

# Copy noble_helper.html and rename to index.html
cp "dist/noble_helper.html" "${NOBLE_DEPLOY_DIR}/index.html"
echo -e "${GREEN}✓ noble_helper.html скопирован${NC}"

# Copy all assets (JS, CSS, images, etc.) - these will have correct VITE_PROXY embedded
if [ -d "dist/assets" ]; then
    cp -r "dist/assets" "${NOBLE_DEPLOY_DIR}/assets"
    echo -e "${GREEN}✓ Assets скопированы${NC}"
fi

# Copy other static files that might be needed (favicon, images, etc.)
if [ -d "dist/images" ]; then
    cp -r "dist/images" "${NOBLE_DEPLOY_DIR}/images"
fi
if [ -f "dist/favicon.ico" ]; then
    cp "dist/favicon.ico" "${NOBLE_DEPLOY_DIR}/"
fi
if [ -f "dist/loader.css" ]; then
    cp "dist/loader.css" "${NOBLE_DEPLOY_DIR}/"
fi
if [ -f "dist/logo.png" ]; then
    cp "dist/logo.png" "${NOBLE_DEPLOY_DIR}/"
fi

echo -e "${GREEN}✓ Noble helper собран и подготовлен${NC}\n"

# Step 3: Build main app with correct proxy URL
echo -e "${BLUE}=== Шаг 3: Сборка основного приложения ===${NC}"

# Configure .env file for main app
echo -e "${YELLOW}Настройка .env файла для основного приложения...${NC}"
cat > .env <<EOF
VITE_PROXY=${PROXY_URL}
VITE_ACTIVE_GAME=${GAME_VERSION}
EOF
cat > .env.production <<EOF
VITE_PROXY=${PROXY_URL}
VITE_ACTIVE_GAME=${GAME_VERSION}
EOF
echo -e "${GREEN}✓ .env файлы для основного приложения настроены${NC}"
echo -e "${BLUE}VITE_PROXY=${PROXY_URL}${NC}"

# Build main app
echo -e "${YELLOW}Сборка основного приложения...${NC}"
rm -rf dist
if ! grep -q "VITE_PROXY" .env; then
    echo -e "${RED}Ошибка: VITE_PROXY не найден в .env файле${NC}"
    exit 1
fi
echo -e "${BLUE}VITE_PROXY установлен в: $(grep VITE_PROXY .env)${NC}"
NODE_ENV=production pnpm build

# Check if dist directory exists
if [ ! -d "dist" ]; then
    echo -e "${RED}Error: dist directory not found after build${NC}"
    exit 1
fi

if [ ! -f "dist/index.html" ]; then
    echo -e "${RED}Error: index.html not found in dist${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Основное приложение собрано успешно${NC}\n"

# Step 4: Deploy main app to server
echo -e "${BLUE}=== Шаг 4: Загрузка основного приложения на сервер ===${NC}"
echo -e "${YELLOW}Сервер: ${USER}@${SERVER}${NC}"
echo -e "${YELLOW}Путь: ${DEPLOY_PATH}${NC}\n"

# Create release directory with timestamp
RELEASE_DIR="${DEPLOY_PATH}/releases/${TIMESTAMP}"

echo -e "${YELLOW}Создание release директории на сервере...${NC}"
ssh "${USER}@${SERVER}" "mkdir -p ${RELEASE_DIR}"

# Upload dist to server using rsync
echo -e "${YELLOW}Загрузка dist на сервер...${NC}"
rsync -avz --delete \
    --exclude='.git' \
    --exclude='node_modules' \
    "${FRONTEND_DIR}/dist/" \
    "${USER}@${SERVER}:${RELEASE_DIR}/"

echo -e "${GREEN}✓ Файлы загружены на сервер${NC}"

# Create symlink current -> release
echo -e "${YELLOW}Создание симлинка current...${NC}"
ssh "${USER}@${SERVER}" "
    mkdir -p ${DEPLOY_PATH}
    # Удаляем старую директорию или симлинк, если они существуют
    rm -rf ${DEPLOY_PATH}/current
    # Создаем новый симлинк
    ln -sfn ${RELEASE_DIR} ${DEPLOY_PATH}/current
    # APK для планшетов лежат ВНЕ релизов (загружает era_scripts/build-prod.sh),
    # внутри релиза держим только симлинк на каталог загрузок, иначе файлы пропадут при деплое
    mkdir -p ${DEPLOY_PATH}/downloads
    ln -sfn ../../downloads ${RELEASE_DIR}/apk
"

echo -e "${GREEN}✓ Симлинк создан${NC}\n"

# Step 5: Deploy mobile helper to separate directory
echo -e "${BLUE}=== Шаг 5: Загрузка merchant_mobile_helper на сервер ===${NC}"
echo -e "${YELLOW}Сервер: ${USER}@${SERVER}${NC}"
echo -e "${YELLOW}Путь: ${MOBILE_DEPLOY_PATH}${NC}\n"

# Create release directory with timestamp for mobile
MOBILE_RELEASE_DIR="${MOBILE_DEPLOY_PATH}/releases/${TIMESTAMP}"

echo -e "${YELLOW}Создание release директории для mobile helper на сервере...${NC}"
ssh "${USER}@${SERVER}" "mkdir -p ${MOBILE_RELEASE_DIR}"

# Upload mobile deployment files to server using rsync
echo -e "${YELLOW}Загрузка merchant_mobile_helper на сервер...${NC}"
rsync -avz --delete \
    "${MOBILE_DEPLOY_DIR}/" \
    "${USER}@${SERVER}:${MOBILE_RELEASE_DIR}/"

echo -e "${GREEN}✓ Файлы merchant_mobile_helper загружены на сервер${NC}"

# Create symlink current -> release for mobile
echo -e "${YELLOW}Создание симлинка current для mobile helper...${NC}"
ssh "${USER}@${SERVER}" "
    mkdir -p ${MOBILE_DEPLOY_PATH}
    # Удаляем старую директорию или симлинк, если они существуют
    rm -rf ${MOBILE_DEPLOY_PATH}/current
    # Создаем новый симлинк
    ln -sfn ${MOBILE_RELEASE_DIR} ${MOBILE_DEPLOY_PATH}/current
"

echo -e "${GREEN}✓ Симлинк для mobile helper создан${NC}"

# Cleanup old releases for mobile (keep last 3)
echo -e "${YELLOW}Очистка старых releases для mobile helper...${NC}"
ssh "${USER}@${SERVER}" "
    cd ${MOBILE_DEPLOY_PATH}/releases 2>/dev/null || exit 0
    ls -t | tail -n +4 | xargs -r rm -rf
    echo '✓ Старые releases удалены (оставлено последних 3)'
"

# Cleanup local temporary directory for mobile
rm -rf "${MOBILE_DEPLOY_DIR}"
echo -e "${GREEN}✓ Временная директория для mobile helper очищена${NC}\n"

# Step 6: Deploy noble helper to separate directory
echo -e "${BLUE}=== Шаг 6: Загрузка noble_helper на сервер ===${NC}"
echo -e "${YELLOW}Сервер: ${USER}@${SERVER}${NC}"
echo -e "${YELLOW}Путь: ${NOBLE_DEPLOY_PATH}${NC}\n"

# Create release directory with timestamp for noble
NOBLE_RELEASE_DIR="${NOBLE_DEPLOY_PATH}/releases/${TIMESTAMP}"

echo -e "${YELLOW}Создание release директории для noble helper на сервере...${NC}"
ssh "${USER}@${SERVER}" "mkdir -p ${NOBLE_RELEASE_DIR}"

# Upload noble deployment files to server using rsync
echo -e "${YELLOW}Загрузка noble_helper на сервер...${NC}"
rsync -avz --delete \
    "${NOBLE_DEPLOY_DIR}/" \
    "${USER}@${SERVER}:${NOBLE_RELEASE_DIR}/"

echo -e "${GREEN}✓ Файлы noble_helper загружены на сервер${NC}"

# Create symlink current -> release for noble
echo -e "${YELLOW}Создание симлинка current для noble helper...${NC}"
ssh "${USER}@${SERVER}" "
    mkdir -p ${NOBLE_DEPLOY_PATH}
    # Удаляем старую директорию или симлинк, если они существуют
    rm -rf ${NOBLE_DEPLOY_PATH}/current
    # Создаем новый симлинк
    ln -sfn ${NOBLE_RELEASE_DIR} ${NOBLE_DEPLOY_PATH}/current
"

echo -e "${GREEN}✓ Симлинк для noble helper создан${NC}"

# Cleanup old releases for noble (keep last 3)
echo -e "${YELLOW}Очистка старых releases для noble helper...${NC}"
ssh "${USER}@${SERVER}" "
    cd ${NOBLE_DEPLOY_PATH}/releases 2>/dev/null || exit 0
    ls -t | tail -n +4 | xargs -r rm -rf
    echo '✓ Старые releases удалены (оставлено последних 3)'
"

# Cleanup local temporary directory for noble
rm -rf "${NOBLE_DEPLOY_DIR}"
echo -e "${GREEN}✓ Временная директория для noble helper очищена${NC}\n"

# Cleanup old releases (keep last 3)
echo -e "${YELLOW}Очистка старых releases...${NC}"
ssh "${USER}@${SERVER}" "
    cd ${DEPLOY_PATH}/releases 2>/dev/null || exit 0
    ls -t | tail -n +4 | xargs -r rm -rf
    echo '✓ Старые releases удалены (оставлено последних 3)'
"

echo ""
echo -e "${GREEN}=== Деплой завершен успешно ===${NC}"
echo -e "${BLUE}Release: ${TIMESTAMP}${NC}"
echo -e "${BLUE}Версия игры: ${GAME_VERSION}${NC}"
echo -e "${BLUE}Плагин era_front: ${PLUGIN_DIR:-<ядро>}${NC}"
echo -e "${BLUE}Основное приложение: ${DEPLOY_PATH}/current${NC}"
echo -e "${BLUE}Mobile helper: ${MOBILE_DEPLOY_PATH}/current${NC}"
echo -e "${BLUE}Noble helper: ${NOBLE_DEPLOY_PATH}/current${NC}"
echo ""

