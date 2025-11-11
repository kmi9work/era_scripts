#!/bin/bash
# deploy-backend.sh - Деплой бэкенда eraofchange на production сервер
# Поддерживает обе версии: base-game и vassals-and-robbers

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

echo -e "${BLUE}=== ERA Backend Deployment ===${NC}\n"

# Configuration
SERVER="${BACKEND_DEPLOY_SERVER:-62.173.148.168}"
USER="deploy"
DEPLOY_PATH="/opt/era/eraofchange"
REPO_URL="git@github.com:kmi9work/eraofchange.git"
BRANCH="depl"
RBENV_RUBY="3.2.2"
PASSENGER_RUBY="/home/deploy/.rbenv/shims/ruby"
KEEP_RELEASES=3

# Ask user to choose game version
echo -e "${YELLOW}Выберите версию игры для деплоя:${NC}"
echo "  1) base-game"
echo "  2) vassals-and-robbers"
echo ""
read -p "Выбор [1-2]: " GAME_CHOICE

case "$GAME_CHOICE" in
    1)
        GAME_VERSION="base-game"
        RUN_VASSALS_SEEDS=false
        ;;
    2)
        GAME_VERSION="vassals-and-robbers"
        RUN_VASSALS_SEEDS=true
        ;;
    *)
        echo -e "${RED}Неверный выбор. Используется base-game по умолчанию.${NC}"
        GAME_VERSION="base-game"
        RUN_VASSALS_SEEDS=false
        ;;
esac

echo ""
echo -e "${GREEN}Выбрана версия: ${GAME_VERSION}${NC}\n"

# Check if master.key exists locally (for database password)
if [ ! -f "$PROJECT_DIR/eraofchange/config/master.key" ]; then
    echo -e "${YELLOW}Предупреждение: config/master.key не найден локально${NC}"
    echo -e "${YELLOW}Убедитесь, что файл существует на сервере в shared/config/${NC}"
fi

# Step 1: Connect to server and deploy
echo -e "${BLUE}=== Шаг 1: Подключение к серверу ===${NC}"
echo -e "${YELLOW}Сервер: ${USER}@${SERVER}${NC}"
echo -e "${YELLOW}Путь: ${DEPLOY_PATH}${NC}\n"

# Create timestamp for release
TIMESTAMP=$(date +%Y%m%d%H%M%S)
RELEASE_DIR="${DEPLOY_PATH}/releases/${TIMESTAMP}"
SHARED_DIR="${DEPLOY_PATH}/shared"
CURRENT_DIR="${DEPLOY_PATH}/current"

echo -e "${YELLOW}Создание директорий на сервере...${NC}"
ssh "${USER}@${SERVER}" "
    # Create directory structure
    mkdir -p ${DEPLOY_PATH}/releases
    mkdir -p ${SHARED_DIR}/config
    mkdir -p ${SHARED_DIR}/tmp/sockets
    mkdir -p ${SHARED_DIR}/tmp/pids
    mkdir -p ${SHARED_DIR}/tmp/cache
    mkdir -p ${SHARED_DIR}/public/uploads
    mkdir -p ${SHARED_DIR}/log
    mkdir -p ${SHARED_DIR}/vendor
    mkdir -p ${SHARED_DIR}/storage
    mkdir -p ${SHARED_DIR}/public/system
"

echo -e "${GREEN}✓ Директории созданы${NC}\n"

# Step 2: Clone/update code
echo -e "${BLUE}=== Шаг 2: Получение кода ===${NC}"
echo -e "${YELLOW}Клонирование репозитория в ${RELEASE_DIR}...${NC}"

ssh "${USER}@${SERVER}" "
    if [ -d ${RELEASE_DIR} ]; then
        echo 'Release directory already exists, removing...'
        rm -rf ${RELEASE_DIR}
    fi
    
    # Clone repository
    git clone --depth 1 --branch ${BRANCH} ${REPO_URL} ${RELEASE_DIR} || {
        echo 'Error: Failed to clone repository'
        exit 1
    }
"

echo -e "${GREEN}✓ Код получен${NC}\n"

# Step 3: Setup environment and install dependencies
echo -e "${BLUE}=== Шаг 3: Установка зависимостей ===${NC}"

ssh "${USER}@${SERVER}" "
    cd ${RELEASE_DIR}
    
    # Setup rbenv environment
    export RBENV_ROOT=\$HOME/.rbenv
    export PATH=\"\$RBENV_ROOT/bin:\$PATH\"
    eval \"\$(rbenv init - bash)\"
    
    # Ensure correct Ruby version is installed
    if ! rbenv versions | grep -q ${RBENV_RUBY}; then
        echo 'Installing Ruby ${RBENV_RUBY}...'
        rbenv install ${RBENV_RUBY} || true
        rbenv global ${RBENV_RUBY}
    fi
    
    rbenv local ${RBENV_RUBY}
    
    # Install bundler if not present
    if ! gem list bundler -i; then
        gem install bundler
    fi
    
    # Configure bundler for deployment
    bundle config set --local deployment 'true'
    bundle config set --local without 'development test'
    bundle config set --local path 'vendor/bundle'
    
    # Install gems
    echo 'Installing gems...'
    bundle install || {
        echo 'Error: Failed to install gems'
        exit 1
    }
"

echo -e "${GREEN}✓ Зависимости установлены${NC}\n"

# Step 4: Setup configuration files
echo -e "${BLUE}=== Шаг 4: Настройка конфигурации ===${NC}"

# Upload config files if they exist locally
if [ -f "$PROJECT_DIR/eraofchange/config/database_prod.yml" ]; then
    echo -e "${YELLOW}Загрузка database_prod.yml...${NC}"
    scp "$PROJECT_DIR/eraofchange/config/database_prod.yml" "${USER}@${SERVER}:${SHARED_DIR}/config/database.yml"
    echo -e "${GREEN}✓ database.yml загружен${NC}"
fi

if [ -f "$PROJECT_DIR/eraofchange/config/master.key" ]; then
    echo -e "${YELLOW}Загрузка master.key...${NC}"
    scp "$PROJECT_DIR/eraofchange/config/master.key" "${USER}@${SERVER}:${SHARED_DIR}/config/master.key"
    ssh "${USER}@${SERVER}" "chmod 640 ${SHARED_DIR}/config/master.key"
    echo -e "${GREEN}✓ master.key загружен${NC}"
fi

# Create .env.production file
echo -e "${YELLOW}Создание .env.production...${NC}"
ssh "${USER}@${SERVER}" "
    echo 'ACTIVE_GAME=${GAME_VERSION}' > ${SHARED_DIR}/.env.production
    chmod 644 ${SHARED_DIR}/.env.production
"

echo -e "${GREEN}✓ .env.production создан с ACTIVE_GAME=${GAME_VERSION}${NC}\n"

# Step 5: Create symlinks
echo -e "${BLUE}=== Шаг 5: Создание симлинков ===${NC}"

ssh "${USER}@${SERVER}" "
    cd ${RELEASE_DIR}
    
    # Create symlinks to shared files
    ln -sfn ${SHARED_DIR}/config/database.yml config/database.yml 2>/dev/null || true
    ln -sfn ${SHARED_DIR}/config/master.key config/master.key 2>/dev/null || true
    ln -sfn ${SHARED_DIR}/.env.production .env.production
    
    # Create symlinks to shared directories
    rm -rf log && ln -sfn ${SHARED_DIR}/log log
    rm -rf tmp/pids && mkdir -p tmp && ln -sfn ${SHARED_DIR}/tmp/pids tmp/pids
    rm -rf tmp/cache && mkdir -p tmp && ln -sfn ${SHARED_DIR}/tmp/cache tmp/cache
    rm -rf tmp/sockets && mkdir -p tmp && ln -sfn ${SHARED_DIR}/tmp/sockets tmp/sockets
    # Note: vendor/bundle should stay in release, not be symlinked
    # Only vendor (if used for other purposes) can be symlinked
    # rm -rf vendor && ln -sfn ${SHARED_DIR}/vendor vendor 2>/dev/null || true
    rm -rf storage && ln -sfn ${SHARED_DIR}/storage storage 2>/dev/null || true
    rm -rf public/system && mkdir -p public && ln -sfn ${SHARED_DIR}/public/system public/system 2>/dev/null || true
"

echo -e "${GREEN}✓ Симлинки созданы${NC}\n"

# Step 6: Stop Passenger
echo -e "${BLUE}=== Шаг 6: Остановка Passenger ===${NC}"
ssh "${USER}@${SERVER}" "sudo systemctl stop passenger || true"
echo -e "${GREEN}✓ Passenger остановлен${NC}\n"

# Step 7: Migrations and seeds are not run automatically
# They should be run separately when needed:
# - For migrations: ssh deploy@server "cd /opt/era/eraofchange/current && bundle exec rake db:migrate"
# - For seeds: ssh deploy@server "cd /opt/era/eraofchange/current && bundle exec rake db:seed:all"
echo -e "${BLUE}=== Шаг 7: Миграции и сиды пропущены ===${NC}"
echo -e "${YELLOW}Миграции и сиды не выполняются автоматически при деплое${NC}"
echo -e "${YELLOW}Выполните их вручную при необходимости${NC}\n"

# Step 8: Update Passenger configuration
echo -e "${BLUE}=== Шаг 8: Обновление конфигурации Passenger ===${NC}"

ssh "${USER}@${SERVER}" "
    ENV_FILE=${CURRENT_DIR}/.env.production
    
    # Update systemd service if it exists
    SERVICE_FILE=\"/etc/systemd/system/passenger.service\"
    if [ -f \${SERVICE_FILE} ]; then
        # Check if EnvironmentFile is already set
        if ! sudo grep -q \"EnvironmentFile=\" \${SERVICE_FILE}; then
            # Add EnvironmentFile after [Service]
            sudo sed -i '/^\\[Service\\]$/a EnvironmentFile='\${ENV_FILE} \${SERVICE_FILE}
            sudo systemctl daemon-reload
            echo 'Added EnvironmentFile to systemd service'
        else
            # Update EnvironmentFile path if different
            CURRENT_ENV_FILE=\$(sudo grep \"^EnvironmentFile=\" \${SERVICE_FILE} | cut -d'=' -f2)
            if [ \"\${CURRENT_ENV_FILE}\" != \"\${ENV_FILE}\" ]; then
                sudo sed -i \"s|^EnvironmentFile=.*|EnvironmentFile=\${ENV_FILE}|\" \${SERVICE_FILE}
                sudo systemctl daemon-reload
                echo 'Updated EnvironmentFile path in systemd service'
            fi
        fi
    fi
"

echo -e "${GREEN}✓ Конфигурация Passenger обновлена${NC}\n"

# Step 9: Switch current symlink
echo -e "${BLUE}=== Шаг 9: Переключение на новый релиз ===${NC}"

ssh "${USER}@${SERVER}" "
    # Remove old current symlink or directory
    rm -rf ${CURRENT_DIR}
    
    # Create new symlink
    ln -sfn ${RELEASE_DIR} ${CURRENT_DIR}
    
    # Ensure .env.production symlink exists in current
    ln -sfn ${SHARED_DIR}/.env.production ${CURRENT_DIR}/.env.production
"

echo -e "${GREEN}✓ Симлинк current обновлен${NC}\n"

# Step 10: Start Passenger
echo -e "${BLUE}=== Шаг 10: Запуск Passenger ===${NC}"
ssh "${USER}@${SERVER}" "
    sudo systemctl start passenger || {
        echo 'Error: Failed to start Passenger'
        exit 1
    }
    sleep 2
    sudo systemctl status passenger --no-pager -l || true
"
echo -e "${GREEN}✓ Passenger запущен${NC}\n"

# Check if Passenger is running
echo -e "${YELLOW}Проверка статуса Passenger...${NC}"
if ssh "${USER}@${SERVER}" "sudo systemctl is-active --quiet passenger"; then
    echo -e "${GREEN}✓ Passenger работает${NC}"
else
    echo -e "${RED}⚠ Предупреждение: Passenger может не работать${NC}"
    echo -e "${YELLOW}Проверьте логи: sudo journalctl -u passenger -n 50${NC}"
fi
echo ""

# Step 11: Cleanup old releases
echo -e "${BLUE}=== Шаг 11: Очистка старых releases ===${NC}"

ssh "${USER}@${SERVER}" "
    cd ${DEPLOY_PATH}/releases 2>/dev/null || exit 0
    ls -t | tail -n +$((KEEP_RELEASES + 1)) | xargs -r rm -rf
    echo '✓ Старые releases удалены (оставлено последних ${KEEP_RELEASES})'
"

echo ""
echo -e "${GREEN}=== Деплой завершен успешно ===${NC}"
echo -e "${BLUE}Release: ${TIMESTAMP}${NC}"
echo -e "${BLUE}Версия игры: ${GAME_VERSION}${NC}"
echo -e "${BLUE}Путь на сервере: ${CURRENT_DIR}${NC}"
echo ""

