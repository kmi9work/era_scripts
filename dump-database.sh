#!/bin/bash
# dump-database.sh - Создает дамп базы данных на сервере и копирует его локально

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

echo -e "${BLUE}=== Database Dump Script ===${NC}\n"

# Configuration
SERVER="${BACKEND_DEPLOY_SERVER:-62.173.148.168}"
USER="deploy"
DEPLOY_PATH="/opt/era/eraofchange"
CURRENT_DIR="${DEPLOY_PATH}/current"
DUMP_DIR="/home/mic/learn/era/dumps"

# Database configuration
DB_NAME="eraofchange_production"
DB_USER="deploy"

# Get database password from local config/database.key file
DB_KEY_FILE="${PROJECT_DIR}/eraofchange/config/database.key"
if [ ! -f "$DB_KEY_FILE" ]; then
    echo -e "${RED}✗ Ошибка: файл database.key не найден${NC}"
    echo -e "${YELLOW}Ожидаемый путь: ${DB_KEY_FILE}${NC}"
    exit 1
fi

DB_PASSWORD=$(cat "$DB_KEY_FILE" | tr -d '[:space:]')
if [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}✗ Ошибка: файл database.key пуст${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Пароль базы данных загружен из ${DB_KEY_FILE}${NC}\n"

# Create local dump directory if it doesn't exist
echo -e "${YELLOW}Создание локальной директории для дампов...${NC}"
mkdir -p "$DUMP_DIR"
echo -e "${GREEN}✓ Директория создана: ${DUMP_DIR}${NC}\n"

# Generate timestamp for dump filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DUMP_FILENAME="eraofchange_production_${TIMESTAMP}.sql"
REMOTE_DUMP_PATH="/tmp/${DUMP_FILENAME}"
LOCAL_DUMP_PATH="${DUMP_DIR}/${DUMP_FILENAME}"

echo -e "${BLUE}=== Создание дампа базы данных ===${NC}"
echo -e "${YELLOW}Сервер: ${USER}@${SERVER}${NC}"
echo -e "${YELLOW}База данных: ${DB_NAME}${NC}"
echo -e "${YELLOW}Файл дампа: ${DUMP_FILENAME}${NC}\n"

# Step 1: Create dump on server
echo -e "${BLUE}Шаг 1: Создание дампа на сервере...${NC}"

ssh "${USER}@${SERVER}" "
    cd ${CURRENT_DIR}
    
    # Use password from environment variable (passed from local script)
    export PGPASSWORD=\"${DB_PASSWORD}\"
    echo '✓ Database password loaded from local config/database.key'
    
    # Create SQL dump
    echo 'Creating SQL dump...'
    pg_dump -U ${DB_USER} -h localhost -d ${DB_NAME} -F p -f ${REMOTE_DUMP_PATH} || {
        echo 'Error: Failed to create database dump'
        exit 1
    }
    
    echo '✓ Database dump created successfully'
    ls -lh ${REMOTE_DUMP_PATH}
"

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Ошибка при создании дампа на сервере${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Дамп создан на сервере${NC}\n"

# Step 2: Copy dump from server to local machine
echo -e "${BLUE}Шаг 2: Копирование дампа с сервера...${NC}"

# Copy SQL dump
scp "${USER}@${SERVER}:${REMOTE_DUMP_PATH}" "${LOCAL_DUMP_PATH}" || {
    echo -e "${RED}✗ Ошибка при копировании дампа${NC}"
    exit 1
}

echo -e "${GREEN}✓ Дамп скопирован локально${NC}\n"

# Step 3: Cleanup remote dump files
echo -e "${BLUE}Шаг 3: Очистка временных файлов на сервере...${NC}"

ssh "${USER}@${SERVER}" "
    rm -f ${REMOTE_DUMP_PATH}
    echo '✓ Temporary files removed'
"

echo -e "${GREEN}✓ Временные файлы удалены${NC}\n"

# Display summary
echo -e "${GREEN}=== Дамп завершен успешно ===${NC}"
echo -e "${BLUE}Локальный файл:${NC}"
if [ -f "${LOCAL_DUMP_PATH}" ]; then
    echo -e "  ${GREEN}SQL дамп:${NC} ${LOCAL_DUMP_PATH}"
    echo -e "    Размер: $(du -h "${LOCAL_DUMP_PATH}" | cut -f1)"
fi
echo ""

# Show how to restore
echo -e "${YELLOW}Для восстановления базы данных используйте:${NC}"
if [ -f "${LOCAL_DUMP_PATH}" ]; then
    echo -e "  ${GREEN}psql -U ${DB_USER} -d ${DB_NAME} < ${LOCAL_DUMP_PATH}${NC}"
fi
echo ""

