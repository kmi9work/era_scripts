#!/bin/bash
# deploy-frontend.sh - Деплой фронтенда era_front на production сервер
# Сборка происходит локально, на сервер загружается готовый dist

set -e

# Get the directory where this script is located (era_scripts/)
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Get the project root directory (one level up)
PROJECT_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ERA Frontend Deployment ===${NC}\n"

# Configuration
FRONTEND_DIR="$PROJECT_DIR/era_front"
SERVER="${FRONTEND_DEPLOY_SERVER:-62.173.148.168}"
USER="deploy"
DEPLOY_PATH="/opt/era/era_front"
PROXY_URL="https://epoha.igroteh.su/backend"
# Mobile helper будет на new.igroteh.su и должен обращаться к epoha.igroteh.su/backend
# ВАЖНО: На бэкенде нужно настроить CORS, чтобы разрешить запросы с new.igroteh.su
MOBILE_PROXY_URL="https://epoha.igroteh.su/backend"

# Check if era_front directory exists
if [ ! -d "$FRONTEND_DIR" ]; then
    echo -e "${RED}Error: era_front directory not found at $FRONTEND_DIR${NC}"
    exit 1
fi

# Ask user to choose game version
echo -e "${YELLOW}Выберите версию игры для деплоя:${NC}"
echo "  1) base-game"
echo "  2) vassals-and-robbers"
echo ""
read -p "Выбор [1-2]: " GAME_CHOICE

case "$GAME_CHOICE" in
    1)
        GAME_VERSION="base-game"
        ;;
    2)
        GAME_VERSION="vassals-and-robbers"
        ;;
    *)
        echo -e "${RED}Неверный выбор. Используется base-game по умолчанию.${NC}"
        GAME_VERSION="base-game"
        ;;
esac

echo ""
echo -e "${GREEN}Выбрана версия: ${GAME_VERSION}${NC}\n"

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

echo -e "${GREEN}✓ Mobile helper собран и подготовлен${NC}\n"

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

# Cleanup local temporary directory
rm -rf "${MOBILE_DEPLOY_DIR}"
echo -e "${GREEN}✓ Временная директория очищена${NC}\n"

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
echo -e "${BLUE}Основное приложение: ${DEPLOY_PATH}/current${NC}"
echo -e "${BLUE}Mobile helper: ${MOBILE_DEPLOY_PATH}/current${NC}"
echo ""

