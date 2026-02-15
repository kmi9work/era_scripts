#!/bin/bash
# seed-artel.sh - Заливка сидов плагина artel

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

echo -e "${BLUE}=== Заливка сидов Artel ===${NC}\n"

# Check if we're in the right directory
if [ ! -d "$PROJECT_DIR/eraofchange" ]; then
    echo -e "${RED}Ошибка: директория eraofchange не найдена${NC}"
    echo -e "${YELLOW}Убедитесь, что скрипт запущен из корня проекта${NC}"
    exit 1
fi

cd "$PROJECT_DIR/eraofchange"

# Check if RVM is available
if command -v rvm &> /dev/null; then
    echo -e "${YELLOW}Использование RVM...${NC}"
    rvm use
fi

# Set environment variable for artel
export ACTIVE_GAME="artel"

echo -e "${GREEN}Загрузка сидов плагина Artel...${NC}\n"

# Run the rake task to load all artel seeds (db:seed:artel из custom_seed.rake)
if bundle exec rake db:seed:artel; then
    echo ""
    echo -e "${GREEN}✓ Сиды Artel успешно загружены!${NC}"
else
    echo ""
    echo -e "${RED}✗ Ошибка при загрузке сидов Artel${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}=== Готово ===${NC}"


