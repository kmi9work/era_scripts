#!/bin/bash
# deploy-to-tablets.sh - Устанавливает APK на все подключённые через USB Android-устройства
#
# Использование:
#   ./era_scripts/deploy-to-tablets.sh [APK_PATH]
#
# Если APK_PATH не указан, скрипт ищет последний собранный APK в android/app/build/outputs/apk/
#
# Требования:
#   - adb должен быть в PATH
#   - Планшеты должны быть подключены по USB с включённым USB-отладкой
#
# Скрипт автоматически:
#   - Разрешает установку из неизвестных источников на каждом планшете
#   - Отключает подтверждение установки (prompt)
#   - Устанавливает APK без вмешательства пользователя

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
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ERA: Массовая установка APK на планшеты ===${NC}\n"

# Check if adb is installed
if ! command -v adb &> /dev/null; then
    echo -e "${RED}Ошибка: adb не найден в PATH!${NC}"
    echo -e "${YELLOW}Установите Android SDK Platform-Tools или добавьте adb в PATH${NC}"
    echo -e "${YELLOW}Пример: sudo apt install android-sdk-platform-tools${NC}"
    exit 1
fi

echo -e "${GREEN}✓ adb найден: $(which adb)${NC}\n"

# Check if devices are connected
echo -e "${BLUE}=== Поиск подключённых устройств ===${NC}"
DEVICE_LIST=$(adb devices 2>/dev/null | grep -E '^\S+\s+device$' | awk '{print $1}')

if [ -z "$DEVICE_LIST" ]; then
    echo -e "${RED}Ошибка: Подключённые устройства не найдены!${NC}"
    echo -e "${YELLOW}Убедитесь, что:${NC}"
    echo -e "${YELLOW}  1. Планшеты подключены по USB${NC}"
    echo -e "${YELLOW}  2. Включена USB-отладка на планшетах${NC}"
    echo -e "${YELLOW}  3. На планшетах разрешена отладка с этого компьютера${NC}"
    echo -e "${YELLOW}  4. Драйверы установлены (при необходимости)${NC}"
    echo ""
    echo -e "${YELLOW}Подключённые устройства (всего):${NC}"
    adb devices 2>/dev/null | grep -E '^\S' | sed 's/^/  /'
    exit 1
fi

DEVICE_COUNT=$(echo "$DEVICE_LIST" | wc -l)
echo -e "${GREEN}✓ Найдено устройств: ${DEVICE_COUNT}${NC}\n"

# Show connected devices
echo -e "${CYAN}Подключённые устройства:${NC}"
for SERIAL in $DEVICE_LIST; do
    DEVICE_MODEL=$(adb -s "$SERIAL" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    DEVICE_ANDROID=$(adb -s "$SERIAL" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
    DEVICE_NAME=$(adb -s "$SERIAL" shell getprop ro.product.name 2>/dev/null | tr -d '\r')
    
    echo -e "  ${BLUE}${SERIAL}${NC} - ${DEVICE_MODEL} (Android ${DEVICE_ANDROID})"
    if [ -n "$DEVICE_NAME" ]; then
        echo -e "    Модель: ${DEVICE_NAME}"
    fi
done
echo ""

# Determine APK path
if [ -n "$1" ]; then
    # Use provided APK path
    APK_PATH="$1"
    if [ ! -f "$APK_PATH" ]; then
        echo -e "${RED}Ошибка: Файл APK не найден: ${APK_PATH}${NC}"
        exit 1
    fi
else
    # Auto-detect latest APK
    echo -e "${BLUE}=== Поиск последнего собранного APK ===${NC}"
    
    # Look for APKs in both era_native and era_players
    APK_SEARCH_DIRS=(
        "era_native/android/app/build/outputs/apk"
        "era_players/android/app/build/outputs/apk"
    )
    
    LATEST_APK=""
    LATEST_TIME=0
    
    for DIR in "${APK_SEARCH_DIRS[@]}"; do
        if [ -d "$PROJECT_DIR/$DIR" ]; then
            # Find the most recent APK file
            FOUND_APK=$(find "$PROJECT_DIR/$DIR" -name "*.apk" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
            if [ -n "$FOUND_APK" ]; then
                FILE_TIME=$(stat -c %Y "$FOUND_APK" 2>/dev/null || echo "0")
                if [ "$FILE_TIME" -gt "$LATEST_TIME" ]; then
                    LATEST_TIME=$FILE_TIME
                    LATEST_APK="$FOUND_APK"
                fi
            fi
        fi
    done
    
    if [ -z "$LATEST_APK" ]; then
        echo -e "${RED}Ошибка: APK файлы не найдены!${NC}"
        echo -e "${YELLOW}Сначала соберите APK: ./era_scripts/build-prod.sh${NC}"
        exit 1
    fi
    
    APK_PATH="$LATEST_APK"
    echo -e "${GREEN}✓ Найден APK: ${APK_PATH}${NC}"
    echo -e "${YELLOW}Размер: $(du -h "$APK_PATH" | cut -f1)${NC}\n"
fi

# Configure each device to allow installation without prompts
echo -e "${BLUE}=== Настройка разрешений на планшетах ===${NC}\n"

for SERIAL in $DEVICE_LIST; do
    echo -e "${CYAN}Настройка ${SERIAL}...${NC}"
    
    # Check Android version
    ANDROID_VERSION=$(adb -s "$SERIAL" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
    MAJOR_VERSION=$(echo "$ANDROID_VERSION" | grep -oE '^[0-9]+' || echo "0")
    
    echo -e "  Android версия: ${ANDROID_VERSION}"
    
    # Enable installation from unknown sources (works on most Android versions)
    # For Android 8.0+, this setting is per-app, but we enable it globally as fallback
    echo -e "  ${YELLOW}Разрешение установки из неизвестных источников...${NC}"
    adb -s "$SERIAL" shell settings put secure install_non_source_apps_allowed 1 2>/dev/null || true
    adb -s "$SERIAL" shell settings put global unknown_source_settings_allowed 1 2>/dev/null || true
    
    # Disable package verify (for faster installation)
    echo -e "  ${YELLOW}Отключение проверки пакетов...${NC}"
    adb -s "$SERIAL" shell settings put global package_verifier_enable 0 2>/dev/null || true
    adb -s "$SERIAL" shell pm verify-settings -r 2>/dev/null || true
    
    # For Android 8+ (Oreo+), allow unknown sources for specific app (ADB)
    if [ "$MAJOR_VERSION" -ge 8 ]; then
        echo -e "  ${YELLOW}Разрешение установки для ADB (Android ${MAJOR_VERSION}+)...${NC}"
        # This enables the "Install via USB" option in Developer Options
        adb -s "$SERIAL" shell settings put secure install_non_source_apps_allowed 1 2>/dev/null || true
    fi
    
    # Verify settings were applied
    INSTALL_ALLOWED=$(adb -s "$SERIAL" shell settings get secure install_non_source_apps_allowed 2>/dev/null | tr -d '\r')
    echo -e "  ${GREEN}✓ Настройки применены (install_non_source_apps_allowed=${INSTALL_ALLOWED:-неизменно})${NC}"
    echo ""
done

# Confirm deployment
echo -e "${YELLOW}Будет установлено на ${DEVICE_COUNT} устройств:${NC}"
for SERIAL in $DEVICE_LIST; do
    echo -e "  - ${SERIAL}"
done
echo -e "${YELLOW}APK: ${APK_PATH}${NC}\n"

read -p "Продолжить? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Отменено пользователем${NC}"
    exit 0
fi

# Install APK on each device
echo -e "\n${BLUE}=== Установка APK ===${NC}\n"

SUCCESS_COUNT=0
FAIL_COUNT=0
RESULTS=()

for SERIAL in $DEVICE_LIST; do
    echo -e "${CYAN}Установка на ${SERIAL}...${NC}"
    
    # Uninstall existing app (if any) - try both package names
    echo -e "  ${YELLOW}Откат старой версии...${NC}"
    adb -s "$SERIAL" uninstall su.era.of.change.base 2>/dev/null || true
    adb -s "$SERIAL" uninstall su.era.of.change.vassals 2>/dev/null || true
    adb -s "$SERIAL" uninstall su.era.of.change.artel 2>/dev/null || true
    
    # Install APK with replace flag
    echo -e "  ${YELLOW}Установка...${NC}"
    INSTALL_OUTPUT=$(adb -s "$SERIAL" install -r -d "$APK_PATH" 2>&1)
    INSTALL_RESULT=$?
    
    if [ $INSTALL_RESULT -eq 0 ] && echo "$INSTALL_OUTPUT" | grep -q "Success"; then
        echo -e "  ${GREEN}✓ Успешно установлено!${NC}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        RESULTS+=("${SERIAL}: OK")
    else
        echo -e "  ${RED}✗ Ошибка установки:${NC}"
        echo -e "  ${RED}${INSTALL_OUTPUT}${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        RESULTS+=("${SERIAL}: FAILED")
    fi
    
    echo ""
done

# Summary
echo -e "${BLUE}=== Итог ===${NC}\n"
echo -e "  ${GREEN}Успешно: ${SUCCESS_COUNT}${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "  ${RED}Ошибки: ${FAIL_COUNT}${NC}"
fi
echo -e "  Всего устройств: ${DEVICE_COUNT}\n"

echo -e "${CYAN}Детали:${NC}"
for RESULT in "${RESULTS[@]}"; do
    echo -e "  ${RESULT}"
done
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}=== Все устройства обновлены успешно! ===${NC}"
else
    echo -e "${YELLOW}=== Часть устройств не обновлена ===${NC}"
    exit 1
fi
