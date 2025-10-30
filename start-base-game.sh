#!/bin/bash
# Quick start script for base-game (Era of Change)

# Get the directory where this script is located
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Quick Start: Base Game (Era of Change) ===${NC}\n"
echo -e "${GREEN}Запуск с игрой: base-game${NC}\n"

# Set game choice to 1 (base-game) and auto-confirm
export GAME_CHOICE=1

# Optionally skip mobile prompt
if [ "$1" = "--skip-mobile" ]; then
    export MOBILE_CHOICE=2
fi

# Run the main startup script
"$SCRIPTS_DIR/start-dev.sh"

