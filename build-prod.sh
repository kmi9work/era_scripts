#!/bin/bash
# Production build script for era_native / era_players
#
# Игры не зашиты в скрипт: список берётся из реестра era_scripts/lib/era-games.sh
# (base-game + все плагины из <клиент>/src/plugins/game-plugins, включая
# many_teams). Android-flavor определяется по значению buildConfigField
# ACTIVE_GAME в <клиент>/android/app/build.gradle, схема iOS — по имени
# .xcscheme. Новый плагин достаточно положить в game-plugins и добавить ему
# productFlavor — скрипт подхватит его сам.
#
# Использование:
#   ./era_scripts/build-prod.sh                      # интерактивно
#   ./era_scripts/build-prod.sh --list               # что можно собрать
#   ./era_scripts/build-prod.sh --project=era_native --game=many-teams --build=3
#     --project  era_native | era_players | 1 | 2
#     --game     номер из меню, ключ игры (many-teams), имя движка (many_teams)
#                или имя каталога плагина (many_teams)
#     --build    1 = Android, 2 = iOS, 3 = только конфигурация

set -e

# Get the directory where this script is located (era_scripts/)
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Get the project root directory (one level up)
PROJECT_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# Единый реестр игр/плагинов платформы (движки eraofchange/engines + плагины клиентов)
source "$SCRIPTS_DIR/lib/era-games.sh"
era_build_registry

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- Аргументы командной строки ---------------------------------------------
PROJECT_ARG=""
GAME_ARG=""
BUILD_ARG=""
LIST_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --project=*) PROJECT_ARG="${1#*=}" ;;
        --game=*)    GAME_ARG="${1#*=}" ;;
        --build=*)   BUILD_ARG="${1#*=}" ;;
        --list)      LIST_ONLY=1 ;;
        -h|--help)   usage; exit 0 ;;
        *) echo -e "${RED}Неизвестный аргумент: $1${NC}"; echo; usage; exit 1 ;;
    esac
    shift
done

echo -e "${BLUE}=== ERA Production Build ===${NC}\n"

# Production configuration
PROD_BACKEND_URL="https://epoha.igroteh.su/backend/"
PROD_BASIC_AUTH_USERNAME="Anton"
PROD_BASIC_AUTH_PASSWORD="aoFa4-cah"

echo -e "${GREEN}Production Configuration:${NC}"
echo -e "  Backend URL: ${PROD_BACKEND_URL}"
echo -e "  Basic Auth:  ${PROD_BASIC_AUTH_USERNAME}:***"
echo ""

# --- Выбор клиента ----------------------------------------------------------

# client_repo <era_native|era_players>
client_repo() {
    case "$1" in
        era_native)  printf '%s\n' "$ERA_NATIVE_DIR" ;;
        era_players) printf '%s\n' "$ERA_PLAYERS_DIR" ;;
        *)           printf '%s\n' "$1" ;;
    esac
}

if [ "$LIST_ONLY" = "1" ] && [ -z "$PROJECT_ARG" ]; then
    for _client in era_native era_players; do
        _repo="$(client_repo "$_client")"
        echo -e "${GREEN}${_client}:${NC}"
        if [ -d "$_repo/src/plugins/game-plugins" ]; then
            _i=1
            while IFS= read -r _key; do
                [ -n "$_key" ] || continue
                printf '  %d) %-20s %s\n' "$_i" "$_key" "$(era_client_game_description "$_repo" "$_key")"
                _i=$((_i + 1))
            done < <(era_client_games "$_repo")
        else
            echo "  (каталог плагинов не найден)"
        fi
        echo ""
    done
    echo -e "${BLUE}Все игры платформы (реестр era-games.sh):${NC}"
    era_list_games
    exit 0
fi

if [ -z "$PROJECT_ARG" ]; then
    echo -e "${YELLOW}Какой проект собирать?${NC}"
    echo "  1) era_native  (мастерское приложение)"
    echo "  2) era_players (приложение для игроков-купцов)"
    echo ""
    read -p "Выбор [1-2]: " PROJECT_ARG
fi

case "$PROJECT_ARG" in
    1|era_native)
        PROJECT_APP="era_native"
        PROJECT_LABEL="era_native (мастера)"
        ;;
    2|era_players)
        PROJECT_APP="era_players"
        PROJECT_LABEL="era_players (игроки)"
        ;;
    *)
        echo -e "${RED}Неизвестный проект: ${PROJECT_ARG} (ожидается era_native или era_players)${NC}"
        exit 1
        ;;
esac
PROJECT_REPO="$(client_repo "$PROJECT_APP")"

if [ ! -d "$PROJECT_REPO/src/plugins/game-plugins" ]; then
    echo -e "${RED}Не найден каталог плагинов: ${PROJECT_REPO}/src/plugins/game-plugins${NC}"
    exit 1
fi

# Список игр именно для этого клиента, порядок — как в реестре
# (1 base-game, 2 vassals-and-robbers, 3 artel, далее остальные плагины клиента).
GAME_LIST=()
while IFS= read -r _game_key; do
    [ -n "$_game_key" ] && GAME_LIST+=("$_game_key")
done < <(era_client_games "$PROJECT_REPO")

if [ "${#GAME_LIST[@]}" -eq 0 ]; then
    echo -e "${RED}В ${PROJECT_APP} не найдено ни одной игры (ни плагинов, ни base-game)${NC}"
    exit 1
fi

print_game_menu() {
    local i=1 key
    for key in "${GAME_LIST[@]}"; do
        printf '  %d) %-20s %s\n' "$i" "$key" "$(era_client_game_description "$PROJECT_REPO" "$key")"
        i=$((i + 1))
    done
}

if [ "$LIST_ONLY" = "1" ]; then
    echo -e "${GREEN}${PROJECT_LABEL} — доступные сборки:${NC}"
    print_game_menu
    echo ""
    echo -e "${BLUE}Все игры платформы (реестр era-games.sh):${NC}"
    era_list_games
    exit 0
fi

echo ""
echo -e "${GREEN}Выбран проект: ${PROJECT_LABEL}${NC}\n"

# --- Выбор игры -------------------------------------------------------------

GAME_FROM_ARG=0
if [ -n "$GAME_ARG" ]; then
    GAME_FROM_ARG=1
    GAME_CHOICE="$GAME_ARG"
else
    echo -e "${YELLOW}Для какой игры собрать приложение?${NC}"
    print_game_menu
    echo ""
    read -p "Выбор [1-${#GAME_LIST[@]}]: " GAME_CHOICE
fi

# Разбор выбора: номер из меню этого клиента, ключ игры, имя движка или плагина.
# Реализация — в реестре (era_resolve_client_game): 2 означает «игра есть в
# платформе, но плагина этого клиента нет».
RESOLVE_RC=0
era_resolve_client_game "$PROJECT_REPO" "$GAME_CHOICE" || RESOLVE_RC=$?

if [ "$RESOLVE_RC" != "0" ]; then
    if [ "$RESOLVE_RC" = "2" ]; then
        echo -e "${YELLOW}Игра «${ERA_GAME_KEY}» есть в платформе, но не в ${PROJECT_APP}:${NC}"
        echo -e "${YELLOW}нет каталога src/plugins/game-plugins с таким GAME_KEY.${NC}"
    fi
    if [ "$GAME_FROM_ARG" = "1" ]; then
        echo -e "${RED}Игра «${GAME_CHOICE}» недоступна для ${PROJECT_APP}.${NC}"
        echo -e "${YELLOW}Доступно:${NC}"
        print_game_menu
        exit 1
    fi
    echo -e "${YELLOW}Неверный выбор. Используется base-game.${NC}"
    ACTIVE_GAME="base-game"
else
    ACTIVE_GAME="$ERA_GAME_KEY"
fi

GAME_PLUGIN="$(era_plugin_dir "$PROJECT_REPO" "$ACTIVE_GAME" 2>/dev/null || true)"

# Плагин должен быть импортирован в загрузчик, иначе он не инициализируется
# даже при правильном ACTIVE_GAME.
if [ -n "$GAME_PLUGIN" ] && [ -f "$PROJECT_REPO/src/plugins/index.ts" ]; then
    if ! grep -q "game-plugins/${GAME_PLUGIN}" "$PROJECT_REPO/src/plugins/index.ts"; then
        echo -e "${RED}ВНИМАНИЕ: плагин ${GAME_PLUGIN} не импортирован в src/plugins/index.ts${NC}"
        echo -e "${YELLOW}Приложение соберётся, но плагин не активируется. Добавьте init-функцию в initializePlugins().${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Выбрана игра: ${ACTIVE_GAME}${NC}"
if [ -n "$GAME_PLUGIN" ]; then
    echo -e "${GREEN}Плагин: ${GAME_PLUGIN}${NC}"
else
    echo -e "${GREEN}Плагин: — (ядро)${NC}"
fi
echo -e "${GREEN}ACTIVE_GAME: ${ACTIVE_GAME}${NC}\n"

# --- Публикация APK на сайте ---
# Файл кладём в каталог ВНЕ релизов фронта (деплой фронта их перезаписывает),
# а внутри текущего релиза на этот каталог указывает симлинк apk -> ../../downloads
# (его пересоздаёт era_scripts/deploy-frontend.sh при каждом деплое).
APK_PUBLISH_SERVER="${APK_PUBLISH_SERVER:-${FRONTEND_DEPLOY_SERVER:-62.173.148.168}}"
APK_PUBLISH_USER="${APK_PUBLISH_USER:-deploy}"
APK_PUBLISH_DIR="/opt/era/era_front/downloads"
APK_PUBLIC_URL="https://epoha.igroteh.su/apk"
if [ "$PROJECT_APP" = "era_players" ]; then
    APK_NAME_PREFIX="era-players"
else
    APK_NAME_PREFIX="era"
fi

# publish_apk <путь к apk> <тип сборки: release|debug>
publish_apk() {
    local apk_path="$1"
    local build_type="$2"
    local remote_name="${APK_NAME_PREFIX}-${ANDROID_FLAVOR_DIR}.apk"
    local answer=""
    local local_size local_sha

    if [ ! -s "$apk_path" ]; then
        echo -e "${RED}Публикация пропущена: файл не найден или пуст — ${apk_path}${NC}"
        return 1
    fi

    local_size=$(stat -c%s "$apk_path")
    local_sha=$(sha256sum "$apk_path" | awk '{print $1}')

    echo ""
    echo -e "${YELLOW}Публикация на сайте:${NC}"
    echo -e "  файл:     ${apk_path}"
    echo -e "  на сервере: ${APK_PUBLISH_USER}@${APK_PUBLISH_SERVER}:${APK_PUBLISH_DIR}/${remote_name}"
    echo -e "  ссылка:   ${APK_PUBLIC_URL}/${remote_name}"
    echo -e "  размер:   $(( local_size / 1024 / 1024 )) МБ, sha256: ${local_sha}"

    if [ "$build_type" = "debug" ]; then
        read -p "Опубликовать DEBUG-сборку? Она перезапишет release-версию по этой ссылке [y/N]: " answer
        case "$answer" in [yYдД]*) ;; *) echo -e "${YELLOW}Публикация отменена${NC}"; return 0 ;; esac
    else
        read -p "Опубликовать APK на сайте? [Y/n]: " answer
        case "$answer" in [nNтТ]*) echo -e "${YELLOW}Публикация отменена${NC}"; return 0 ;; esac
    fi

    echo -e "${YELLOW}Каталог на сервере...${NC}"
    ssh "${APK_PUBLISH_USER}@${APK_PUBLISH_SERVER}" "mkdir -p ${APK_PUBLISH_DIR}" || {
        echo -e "${RED}Не удалось подготовить каталог на сервере${NC}"; return 1; }

    echo -e "${YELLOW}Загрузка (${local_size} байт)...${NC}"
    rsync -av --progress "$apk_path" \
        "${APK_PUBLISH_USER}@${APK_PUBLISH_SERVER}:${APK_PUBLISH_DIR}/${remote_name}" || {
        echo -e "${RED}Загрузка не удалась${NC}"; return 1; }

    # Симлинк внутри текущего релиза фронта: без него nginx отдаст на /apk/... index.html SPA
    ssh "${APK_PUBLISH_USER}@${APK_PUBLISH_SERVER}" "
        ls -l ${APK_PUBLISH_DIR}/${remote_name}
        if [ -e /opt/era/era_front/current ]; then
            ln -sfn ../../downloads /opt/era/era_front/current/apk
            echo 'симлинк current/apk -> ../../downloads обновлён'
        else
            echo 'ВНИМАНИЕ: /opt/era/era_front/current нет — ссылка заработает после деплоя фронта'
        fi
    " || echo -e "${YELLOW}Не удалось обновить симлинк, проверьте ссылку вручную${NC}"

    # Проверка отдачи: размер должен совпасть, content-type не должен быть text/html
    echo -e "${YELLOW}Проверка ссылки...${NC}"
    local headers
    headers=$(curl -sS -I -u "${PROD_BASIC_AUTH_USERNAME}:${PROD_BASIC_AUTH_PASSWORD}" \
        "${APK_PUBLIC_URL}/${remote_name}" 2>&1) || true
    echo "$headers" | sed 's/^/  /'

    local remote_size remote_type
    remote_size=$(echo "$headers" | awk 'tolower($1)=="content-length:"{gsub(/\r/,"",$2); print $2}')
    remote_type=$(echo "$headers" | awk 'tolower($1)=="content-type:"{gsub(/\r/,"",$2); print $2}')

    if [ "$remote_type" = "text/html" ]; then
        echo -e "${RED}ВНИМАНИЕ: по ссылке отдаётся HTML, а не APK.${NC}"
        echo -e "${YELLOW}Значит в nginx нет отдельной локации для /apk/ — нужен блок location ^~ /apk/ (см. era_scripts/NGINX_FIX.md).${NC}"
        return 1
    elif [ -n "$remote_size" ] && [ "$remote_size" != "$local_size" ]; then
        echo -e "${RED}ВНИМАНИЕ: размер на сервере (${remote_size}) не совпадает с локальным (${local_size})${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ APK опубликован: ${APK_PUBLIC_URL}/${remote_name}${NC}"
    return 0
}

# --- Android flavor и iOS схема для выбранной игры ---------------------------
# era_android_flavor живёт в реестре (lib/era-games.sh): по buildConfigField
# ACTIVE_GAME находит productFlavor, общий для build-prod.sh и start-dev.sh.


# Схема iOS по имени .xcscheme: сначала по ключу игры, затем по имени каталога
# плагина. Практически у плагинов вида vassals-and-robbers схема называется
# Vassals — такие исторические имена перечислены явно.
era_ios_scheme() {
    local repo="$1" key="$2" plugin="$3"
    local -a wanted=("$key")
    local scheme want

    [ -n "$plugin" ] && wanted+=("$plugin")
    case "$key" in
        base-game)           wanted+=("era_native") ;;
        vassals-and-robbers) wanted+=("Vassals") ;;
        artel)               wanted+=("Artel") ;;
    esac

    for scheme in "$repo"/ios/*.xcodeproj/xcshareddata/xcschemes/*.xcscheme; do
        [ -f "$scheme" ] || continue
        scheme="$(basename "$scheme" .xcscheme)"
        for want in "${wanted[@]}"; do
            if [ "$(era_key_norm "$scheme")" = "$(era_key_norm "$want")" ]; then
                printf '%s\n' "$scheme"
                return 0
            fi
        done
    done
    return 1
}

ANDROID_FLAVOR_RAW="$(era_android_flavor "$PROJECT_REPO" "$ACTIVE_GAME" || true)"
ANDROID_FLAVOR_TASK=""
ANDROID_FLAVOR_DIR=""
if [ -n "$ANDROID_FLAVOR_RAW" ]; then
    # Gradle: таск assemble<Flavor>Debug (первая буква заглавная),
    # каталог вывода — имя flavor в нижнем регистре.
    ANDROID_FLAVOR_TASK="${ANDROID_FLAVOR_RAW^}"
    ANDROID_FLAVOR_DIR="${ANDROID_FLAVOR_RAW,,}"
    echo -e "${GREEN}Android flavor: ${ANDROID_FLAVOR_RAW} (${ANDROID_FLAVOR_DIR})${NC}"
else
    echo -e "${YELLOW}Android flavor: нет — в ${PROJECT_APP}/android/app/build.gradle не найден productFlavor${NC}"
    echo -e "${YELLOW}  с buildConfigField \"String\", \"ACTIVE_GAME\", \"\\\"${ACTIVE_GAME}\\\"\".${NC}"
fi

IOS_SCHEME="$(era_ios_scheme "$PROJECT_REPO" "$ACTIVE_GAME" "$GAME_PLUGIN" || true)"
IOS_SCHEME_FALLBACK=0
if [ -z "$IOS_SCHEME" ]; then
    IOS_SCHEME="$(era_ios_scheme "$PROJECT_REPO" "base-game" "" || true)"
    IOS_SCHEME_FALLBACK=1
fi
if [ -n "$IOS_SCHEME" ]; then
    if [ "$IOS_SCHEME_FALLBACK" = "1" ]; then
        echo -e "${YELLOW}Схема iOS: ${IOS_SCHEME} (базовая — отдельной схемы для ${ACTIVE_GAME} нет;${NC}"
        echo -e "${YELLOW}  ACTIVE_GAME из config.ts всё равно включит плагин, но имя/bundle id будут базовыми)${NC}"
    else
        echo -e "${GREEN}Схема iOS: ${IOS_SCHEME}${NC}"
    fi
else
    echo -e "${YELLOW}Схема iOS не найдена — для iOS откройте проект в Xcode вручную${NC}"
fi
echo ""

# Update config.ts with production settings and selected game
echo -e "${YELLOW}Updating ${PROJECT_APP} configuration for production...${NC}"
cat > ${PROJECT_APP}/src/config.ts <<EOF
// This file is auto-generated by era_scripts/build-prod.sh on $(date)
// Production configuration with Basic Auth
// Game: ${ACTIVE_GAME}${GAME_PLUGIN:+ (plugin: ${GAME_PLUGIN})}
export const CONFIG = {
  ACTIVE_GAME: '${ACTIVE_GAME}',
  BACKEND_URL: '${PROD_BACKEND_URL}',
  BASIC_AUTH: {
    username: '${PROD_BASIC_AUTH_USERNAME}',
    password: '${PROD_BASIC_AUTH_PASSWORD}',
  },
};
EOF

echo -e "${GREEN}✓ Configuration updated${NC}\n"

# --- Что собирать -----------------------------------------------------------

if [ -n "$BUILD_ARG" ]; then
    BUILD_CHOICE="$BUILD_ARG"
else
    echo -e "${YELLOW}Что хотите собрать?${NC}"
    echo "  1) Android APK/AAB"
    echo "  2) iOS (требуется Mac)"
    echo "  3) Только обновить конфигурацию (без сборки)"
    echo ""
    read -p "Выбор [1-3]: " BUILD_CHOICE
fi

case "$BUILD_CHOICE" in
    1)
        echo ""
        echo -e "${YELLOW}=== Android Build ===${NC}"
        if [ -z "$ANDROID_FLAVOR_RAW" ]; then
            echo -e "${RED}Сборка невозможна: для игры ${ACTIVE_GAME} нет productFlavor в ${PROJECT_APP}/android/app/build.gradle.${NC}"
            echo -e "${YELLOW}Добавьте в productFlavors блок:${NC}"
            echo -e "${BLUE}        ${GAME_PLUGIN:-${ACTIVE_GAME}} {${NC}"
            echo -e "${BLUE}            dimension \"game\"${NC}"
            echo -e "${BLUE}            applicationIdSuffix \".${GAME_PLUGIN:-${ACTIVE_GAME}}\"${NC}"
            echo -e "${BLUE}            resValue \"string\", \"app_name\", \"${ACTIVE_GAME}\"${NC}"
            echo -e "${BLUE}            buildConfigField \"String\", \"ACTIVE_GAME\", \"\\\"${ACTIVE_GAME}\\\"\"${NC}"
            echo -e "${BLUE}        }${NC}"
            echo -e "${YELLOW}Конфигурация при этом уже обновлена (ACTIVE_GAME=${ACTIVE_GAME}).${NC}"
            exit 1
        fi
        echo -e "${BLUE}Выберите тип сборки:${NC}"
        echo "  1) APK (debug/release)"
        echo "  2) AAB (release для Google Play)"
        echo ""
        read -p "Выбор [1-2]: " ANDROID_TYPE

        cd "$PROJECT_DIR/${PROJECT_APP}"

        if [ "$ANDROID_TYPE" = "1" ]; then
            echo ""
            echo -e "${YELLOW}Создание APK...${NC}"
            echo -e "${BLUE}Выберите вариант:${NC}"
            echo "  1) Debug APK"
            echo "  2) Release APK"
            echo ""
            read -p "Выбор [1-2]: " APK_TYPE

            if [ "$APK_TYPE" = "1" ]; then
                echo -e "${GREEN}Сборка Debug APK...${NC}"
                cd android
                ./gradlew "assemble${ANDROID_FLAVOR_TASK}Debug"
                echo ""
                echo -e "${GREEN}✓ Debug APK создан${NC}"
                echo -e "${BLUE}Игра: ${ACTIVE_GAME}${NC}"
                echo -e "${BLUE}Flavor: ${ANDROID_FLAVOR_RAW}${NC}"
                echo -e "${BLUE}Путь: ${PROJECT_APP}/android/app/build/outputs/apk/${ANDROID_FLAVOR_DIR}/debug/${NC}"
                APK_BUILT="${PROJECT_DIR}/${PROJECT_APP}/android/app/build/outputs/apk/${ANDROID_FLAVOR_DIR}/debug/app-${ANDROID_FLAVOR_DIR}-debug.apk"
                publish_apk "$APK_BUILT" debug || PUBLISH_FAILED=1
            else
                echo -e "${GREEN}Сборка Release APK...${NC}"
                echo -e "${YELLOW}Примечание: требуется настроенный keystore${NC}"
                cd android
                ./gradlew "assemble${ANDROID_FLAVOR_TASK}Release"
                echo ""
                echo -e "${GREEN}✓ Release APK создан${NC}"
                echo -e "${BLUE}Игра: ${ACTIVE_GAME}${NC}"
                echo -e "${BLUE}Flavor: ${ANDROID_FLAVOR_RAW}${NC}"
                echo -e "${BLUE}Путь: ${PROJECT_APP}/android/app/build/outputs/apk/${ANDROID_FLAVOR_DIR}/release/${NC}"
                APK_BUILT="${PROJECT_DIR}/${PROJECT_APP}/android/app/build/outputs/apk/${ANDROID_FLAVOR_DIR}/release/app-${ANDROID_FLAVOR_DIR}-release.apk"
                publish_apk "$APK_BUILT" release || PUBLISH_FAILED=1
            fi
        else
            echo ""
            echo -e "${GREEN}Сборка AAB для Google Play...${NC}"
            echo -e "${YELLOW}Примечание: требуется настроенный keystore${NC}"
            cd android
            ./gradlew "bundle${ANDROID_FLAVOR_TASK}Release"
            echo ""
            echo -e "${GREEN}✓ AAB создан${NC}"
            echo -e "${BLUE}Игра: ${ACTIVE_GAME}${NC}"
            echo -e "${BLUE}Flavor: ${ANDROID_FLAVOR_RAW}${NC}"
            echo -e "${BLUE}Путь: ${PROJECT_APP}/android/app/build/outputs/bundle/${ANDROID_FLAVOR_DIR}Release/${NC}"
        fi

        cd "$PROJECT_DIR"
        ;;
    2)
        echo ""
        echo -e "${YELLOW}=== iOS Build ===${NC}"
        echo -e "${RED}Внимание: iOS сборка требует Mac и настроенный Xcode${NC}"

        cd "$PROJECT_DIR/${PROJECT_APP}/ios"

        echo -e "${GREEN}Установка Pods...${NC}"
        pod install

        echo ""
        if [ -n "$IOS_SCHEME" ]; then
            echo -e "${YELLOW}Откройте ${PROJECT_APP}/ios/${PROJECT_APP}.xcworkspace в Xcode для сборки${NC}"
            echo -e "${BLUE}Выбранная схема: ${IOS_SCHEME}${NC}"
            [ "$IOS_SCHEME_FALLBACK" = "1" ] && echo -e "${YELLOW}Схема базовая: app_name и bundle id останутся от неё, плагин включится через ACTIVE_GAME=${ACTIVE_GAME}${NC}"
            echo -e "${BLUE}Или выполните: xcodebuild -workspace ${PROJECT_APP}.xcworkspace -scheme ${IOS_SCHEME} -configuration Release${NC}"
        else
            echo -e "${YELLOW}Схема для ${ACTIVE_GAME} не найдена. Откройте ${PROJECT_APP}/ios/*.xcworkspace в Xcode,${NC}"
            echo -e "${YELLOW}создайте схему (Product → Scheme → Manage Schemes) и соберите с ACTIVE_GAME=${ACTIVE_GAME}.${NC}"
        fi

        cd "$PROJECT_DIR"
        ;;
    3)
        echo ""
        echo -e "${GREEN}✓ Конфигурация обновлена для продакшн${NC}"
        echo -e "${YELLOW}Вы можете собрать приложение позже используя стандартные команды React Native${NC}"
        ;;
    *)
        echo -e "${YELLOW}Неверный выбор. Только обновлена конфигурация.${NC}"
        ;;
esac

echo ""
echo -e "${GREEN}=== Готово ===${NC}"
if [ "${PUBLISH_FAILED:-0}" = "1" ]; then
    echo -e "${RED}Публикация APK на сайте не удалась (сборка при этом готова).${NC}"
    echo -e "${YELLOW}Проверьте ssh/rsync до ${APK_PUBLISH_USER}@${APK_PUBLISH_SERVER}, а затем повторите публикацию вручную:${NC}"
    echo -e "${BLUE}  rsync -av --progress ${APK_BUILT} ${APK_PUBLISH_USER}@${APK_PUBLISH_SERVER}:${APK_PUBLISH_DIR}/${APK_NAME_PREFIX}-${ANDROID_FLAVOR_DIR}.apk${NC}"
    echo -e "${BLUE}  ssh ${APK_PUBLISH_USER}@${APK_PUBLISH_SERVER} 'ln -sfn ../../downloads /opt/era/era_front/current/apk'${NC}"
    echo -e "${BLUE}Примечание: для возврата к dev-режиму запустите ./era_scripts/start-dev.sh${NC}"
    echo ""
    exit 1
fi
echo -e "${BLUE}Примечание: для возврата к dev-режиму запустите ./era_scripts/start-dev.sh${NC}"
echo ""
