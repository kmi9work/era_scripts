#!/bin/bash
# update-certificate.sh - Обновляет SSL сертификат для домена epoha.igroteh.su

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

echo -e "${BLUE}=== SSL Certificate Update ===${NC}\n"

# Configuration
SERVER="${BACKEND_DEPLOY_SERVER:-62.173.148.168}"
USER="deploy"
DOMAIN="epoha.igroteh.su"

echo -e "${BLUE}=== Обновление SSL сертификата ===${NC}"
echo -e "${YELLOW}Сервер: ${USER}@${SERVER}${NC}"
echo -e "${YELLOW}Домен: ${DOMAIN}${NC}\n"

# Step 1: Update certificate on server
echo -e "${BLUE}Шаг 1: Обновление сертификата на сервере...${NC}"

ssh "${USER}@${SERVER}" "
    echo 'Running certbot to update certificate...'
    sudo certbot --nginx -d ${DOMAIN} || {
        echo 'Error: Failed to update certificate'
        exit 1
    }
    
    echo '✓ Certificate updated successfully'
    
    # Reload nginx to apply changes
    echo 'Reloading nginx...'
    sudo systemctl reload nginx || {
        echo 'Warning: Failed to reload nginx, trying restart...'
        sudo systemctl restart nginx || {
            echo 'Error: Failed to restart nginx'
            exit 1
        }
    }
    
    echo '✓ Nginx reloaded successfully'
"

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Ошибка при обновлении сертификата${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Сертификат обновлен успешно${NC}\n"

# Step 2: Verify certificate status
echo -e "${BLUE}Шаг 2: Проверка статуса сертификата...${NC}"

ssh "${USER}@${SERVER}" "
    echo 'Checking certificate expiration date...'
    sudo certbot certificates | grep -A 5 '${DOMAIN}' || {
        echo 'Warning: Could not find certificate info'
    }
    
    echo ''
    echo 'Checking nginx status...'
    sudo systemctl status nginx --no-pager -l | head -n 10 || true
"

echo ""
echo -e "${GREEN}=== Обновление сертификата завершено успешно ===${NC}"
echo -e "${BLUE}Домен: ${DOMAIN}${NC}"
echo ""






