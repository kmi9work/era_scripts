#!/bin/bash
# restore-database.sh - Загружает SQL файл на сервер и восстанавливает базу данных
#
# Usage:
#   ./era_scripts/restore-database.sh path/to/dump.sql
#
# Notes:
# - Скрипт использует пароль из eraofchange/config/database.key (локально)
# - Восстановление выполняется на сервере через psql в БД production

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

usage() {
  echo -e "${YELLOW}Использование:${NC}"
  echo -e "  ${GREEN}./era_scripts/restore-database.sh${NC} ${BLUE}<path/to/file.sql>${NC}"
  echo ""
  echo -e "${YELLOW}Переменные окружения (опционально):${NC}"
  echo -e "  ${GREEN}BACKEND_DEPLOY_SERVER${NC} - IP/host сервера (по умолчанию: 62.173.148.168)"
}

echo -e "${BLUE}=== Database Restore Script ===${NC}\n"

SQL_FILE="${1:-}"
if [ -z "$SQL_FILE" ]; then
  echo -e "${RED}✗ Ошибка: не указан путь к .sql файлу${NC}\n"
  usage
  exit 1
fi

if [ ! -f "$SQL_FILE" ]; then
  echo -e "${RED}✗ Ошибка: файл не найден: ${SQL_FILE}${NC}"
  exit 1
fi

# Normalize path for nicer output (keep original path for scp)
SQL_BASENAME="$(basename "$SQL_FILE")"

# Configuration
SERVER="${BACKEND_DEPLOY_SERVER:-62.173.148.168}"
USER="deploy"
DEPLOY_PATH="/opt/era/eraofchange"
CURRENT_DIR="${DEPLOY_PATH}/current"

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

# Remote temp path
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REMOTE_SQL_PATH="/tmp/restore_${TIMESTAMP}_${SQL_BASENAME}"

cleanup_remote_file() {
  # Best-effort cleanup; do not fail script on cleanup issues
  ssh "${USER}@${SERVER}" "rm -f ${REMOTE_SQL_PATH}" >/dev/null 2>&1 || true
}
trap cleanup_remote_file EXIT

echo -e "${BLUE}=== Восстановление базы данных ===${NC}"
echo -e "${YELLOW}Сервер: ${USER}@${SERVER}${NC}"
echo -e "${YELLOW}База данных: ${DB_NAME}${NC}"
echo -e "${YELLOW}Локальный файл: ${SQL_FILE}${NC}"
echo -e "${YELLOW}Временный файл на сервере: ${REMOTE_SQL_PATH}${NC}\n"

# Step 1: Upload SQL file to server
echo -e "${BLUE}Шаг 1: Загрузка SQL файла на сервер...${NC}"

scp "$SQL_FILE" "${USER}@${SERVER}:${REMOTE_SQL_PATH}" || {
  echo -e "${RED}✗ Ошибка при копировании файла на сервер${NC}"
  exit 1
}

echo -e "${GREEN}✓ Файл загружен на сервер${NC}\n"

# Step 2: Restore on server
echo -e "${BLUE}Шаг 2: Восстановление базы на сервере...${NC}"
echo -e "${YELLOW}Внимание: скрипт удалит и создаст заново production базу (${DB_NAME}) на сервере, затем применит SQL.${NC}\n"

ssh "${USER}@${SERVER}" "
  set -e
  cd ${CURRENT_DIR}

  export PGPASSWORD=\"${DB_PASSWORD}\"
  echo '✓ Database password loaded from local config/database.key'

  echo 'Dropping and recreating database...'
  psql -v ON_ERROR_STOP=1 -U ${DB_USER} -h localhost -d postgres \
    -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DB_NAME}' AND pid <> pg_backend_pid();\" \
    -c \"DROP DATABASE IF EXISTS ${DB_NAME};\" \
    -c \"CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};\"

  echo 'Running restore via psql...'
  psql -v ON_ERROR_STOP=1 -U ${DB_USER} -h localhost -d ${DB_NAME} -f ${REMOTE_SQL_PATH} || {
    echo 'Error: Restore failed'
    exit 1
  }

  echo '✓ Restore completed successfully'
"

if [ $? -ne 0 ]; then
  echo -e "${RED}✗ Ошибка при восстановлении базы на сервере${NC}"
  exit 1
fi

echo -e "${GREEN}✓ База восстановлена${NC}\n"

# Step 3: Cleanup remote temp file (handled by trap)
echo -e "${BLUE}Шаг 3: Удаление временного файла на сервере...${NC}"
cleanup_remote_file
echo -e "${GREEN}✓ Временный файл удалён${NC}\n"

echo -e "${GREEN}=== Восстановление завершено успешно ===${NC}"
echo ""

