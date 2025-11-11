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

# Step 1: Local build
echo -e "${BLUE}=== Шаг 1: Локальная сборка ===${NC}"
cd "$FRONTEND_DIR"

# Configure .env file
echo -e "${YELLOW}Настройка .env файла...${NC}"
# Удаляем все старые .env файлы, которые могут переопределять переменные
rm -f .env.local .env.development .env.production
# Создаем новый .env файл с правильными значениями
cat > .env <<EOF
VITE_PROXY=${PROXY_URL}
VITE_ACTIVE_GAME=${GAME_VERSION}
EOF
# Также создаем .env.production для явного указания production режима
cat > .env.production <<EOF
VITE_PROXY=${PROXY_URL}
VITE_ACTIVE_GAME=${GAME_VERSION}
EOF
echo -e "${GREEN}✓ .env файлы настроены${NC}"
echo -e "${BLUE}VITE_PROXY=${PROXY_URL}${NC}"
echo -e "${BLUE}VITE_ACTIVE_GAME=${GAME_VERSION}${NC}"

# Install dependencies if needed
if [ ! -d "node_modules" ] || [ "package.json" -nt "node_modules" ]; then
    echo -e "${YELLOW}Установка зависимостей через pnpm...${NC}"
    pnpm install --ignore-scripts
    echo -e "${GREEN}✓ Зависимости установлены${NC}"
else
    echo -e "${GREEN}✓ Зависимости уже установлены${NC}"
fi

# Build project
echo -e "${YELLOW}Сборка проекта...${NC}"
# Очистка старой сборки для гарантии свежей
rm -rf dist
# Проверка что .env файл существует и содержит нужные переменные
if ! grep -q "VITE_PROXY" .env; then
    echo -e "${RED}Ошибка: VITE_PROXY не найден в .env файле${NC}"
    exit 1
fi
# Вывод значения для отладки
echo -e "${BLUE}VITE_PROXY установлен в: $(grep VITE_PROXY .env)${NC}"
# Сборка с явным указанием режима production
NODE_ENV=production pnpm build

# Check if dist directory exists
if [ ! -d "dist" ]; then
    echo -e "${RED}Error: dist directory not found after build${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Сборка завершена успешно${NC}\n"

# Step 2: Deploy to server
echo -e "${BLUE}=== Шаг 2: Загрузка на сервер ===${NC}"
echo -e "${YELLOW}Сервер: ${USER}@${SERVER}${NC}"
echo -e "${YELLOW}Путь: ${DEPLOY_PATH}${NC}\n"

# Create release directory with timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)
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

echo -e "${GREEN}✓ Симлинк создан${NC}"

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
echo -e "${BLUE}Путь на сервере: ${DEPLOY_PATH}/current${NC}"
echo ""

