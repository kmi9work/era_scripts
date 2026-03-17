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
DOMAINS=("epoha.igroteh.su" "calc.igroteh.su" "noble.igroteh.su")

echo -e "${BLUE}=== Обновление SSL сертификатов ===${NC}"
echo -e "${YELLOW}Сервер: ${USER}@${SERVER}${NC}"
echo -e "${YELLOW}Домены: ${DOMAINS[*]}${NC}\n"

# Step 1: Update certificates on server for all domains
echo -e "${BLUE}Шаг 1: Обновление сертификатов на сервере...${NC}\n"

for DOMAIN in "${DOMAINS[@]}"; do
    echo -e "${BLUE}Обработка домена: ${DOMAIN}${NC}"
    
    ssh "${USER}@${SERVER}" "
        echo 'Running certbot to update certificate for ${DOMAIN}...'
        sudo certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos --email admin@igroteh.su || {
            echo 'Error: Failed to update certificate for ${DOMAIN}'
            exit 1
        }
        
        echo '✓ Certificate updated successfully for ${DOMAIN}'
    "
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Ошибка при обновлении сертификата для ${DOMAIN}${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ ${DOMAIN} обновлен${NC}\n"
done

# Reload nginx once after all certificates are updated
echo -e "${BLUE}Перезагрузка nginx для применения всех изменений...${NC}"
ssh "${USER}@${SERVER}" "
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
    echo -e "${RED}✗ Ошибка при перезагрузке nginx${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Все сертификаты обновлены успешно${NC}\n"

# Step 2: Verify certificate status for all domains
echo -e "${BLUE}Шаг 2: Проверка статуса сертификатов...${NC}\n"

ssh "${USER}@${SERVER}" "
    echo 'Checking certificate expiration dates...'
    sudo certbot certificates | grep -E '(${DOMAINS[0]}|${DOMAINS[1]}|${DOMAINS[2]})' || {
        echo 'Warning: Could not find certificate info'
    }
    
    echo ''
    echo 'Checking nginx status...'
    sudo systemctl status nginx --no-pager -l | head -n 10 || true
"

echo ""
echo -e "${GREEN}=== Обновление сертификатов завершено успешно ===${NC}"
echo -e "${BLUE}Обновленные домены:${NC}"
for DOMAIN in "${DOMAINS[@]}"; do
    echo -e "  - ${DOMAIN}"
done
echo ""






