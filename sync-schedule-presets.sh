#!/bin/bash
# sync-schedule-presets.sh — двусторонняя синхронизация пресетов расписания
# между локальной машиной и сервером (shared/storage/schedule_presets).
#
# Логика: «побеждает» файл с более новым mtime.
#   1) сначала тянем с сервера файлы, которых нет локально или которые там новее;
#   2) затем отправляем на сервер файлы, которых нет на сервере или которые новее локально.
# По умолчанию файлы, удалённые на одной стороне, восстанавливаются с другой
# (ничего не теряется). Чтобы удаление файла распространялось на обе стороны —
# --mirror: список расхождений считается ДО копирования, удаление спрашивает подтверждение.
#
# Использование:
#   ./sync-schedule-presets.sh                 # обычная двусторонняя синхронизация
#   ./sync-schedule-presets.sh --dry-run       # показать, что будет сделано
#   ./sync-schedule-presets.sh --pull-only     # только с сервера на локалку
#   ./sync-schedule-presets.sh --push-only     # только с локалки на сервер
#   ./sync-schedule-presets.sh --list          # что лежит на каждой стороне
#   ./sync-schedule-presets.sh --mirror        # + удалить файлы, которых нет на другой стороне
#
# Переменные окружения: BACKEND_DEPLOY_SERVER, PRESETS_USER, PRESETS_DEPLOY_PATH,
#                       PRESETS_LOCAL_DIR, PRESETS_REMOTE_DIR, PRESETS_SSH_OPTS
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"

SERVER="${BACKEND_DEPLOY_SERVER:-62.173.148.168}"
REMOTE_USER="${PRESETS_USER:-deploy}"
DEPLOY_PATH="${PRESETS_DEPLOY_PATH:-/opt/era/eraofchange}"
REMOTE_DIR="${PRESETS_REMOTE_DIR:-${DEPLOY_PATH}/shared/storage/schedule_presets}"
LOCAL_DIR="${PRESETS_LOCAL_DIR:-$PROJECT_DIR/eraofchange/storage/schedule_presets}"
SSH_OPTS="${PRESETS_SSH_OPTS:--o ConnectTimeout=15}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

MODE="two-way"
DRY=""
MIRROR=0

for arg in "$@"; do
    case "$arg" in
        --dry-run)   DRY="--dry-run";;
        --pull-only) MODE="pull";;
        --push-only) MODE="push";;
        --list)      MODE="list";;
        --mirror)    MIRROR=1;;
        -h|--help)   sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0;;
        *) echo -e "${RED}Неизвестный аргумент: $arg${NC}"; exit 2;;
    esac
done

# -n: ssh не должен читать stdin скрипта (иначе съедает ответы на read)
remote() { ssh -n $SSH_OPTS "${REMOTE_USER}@${SERVER}" "$@"; }

require_dirs() {
    mkdir -p "$LOCAL_DIR"
    remote "mkdir -p '${REMOTE_DIR}'" >/dev/null
}

# Имена *.json на каждой стороне (по одному в строке)
list_local()  { (cd "$LOCAL_DIR" && ls -1 *.json 2>/dev/null) || true; }
list_remote() { remote "cd '${REMOTE_DIR}' 2>/dev/null && ls -1 *.json 2>/dev/null" || true; }

# Строки, которые есть только в первом списке
only_in_first() {
    comm -23 <(printf '%s\n' "$1" | grep -v '^$' | sort) <(printf '%s\n' "$2" | grep -v '^$' | sort) || true
}

# Проверка локальных файлов: печатает "<имя>\t<причина>" для некорректных пресетов
invalid_local_files() {
    python3 - "$LOCAL_DIR" <<'PY' || true
import json, os, sys
d = sys.argv[1]
for name in sorted(os.listdir(d)):
    if not name.endswith(".json"):
        continue
    try:
        data = json.load(open(os.path.join(d, name), encoding="utf-8"))
    except Exception as e:
        print(f"{name}\tне читается как JSON: {e}")
        continue
    if not isinstance(data.get("items"), list) or not data["items"]:
        print(f"{name}\tнет непустого массива items")
PY
}

# --- режим --list -------------------------------------------------------------
if [ "$MODE" = "list" ]; then
    require_dirs
    echo -e "${BLUE}Локально${NC} ($LOCAL_DIR):"
    list_local | sed 's/^/  /' || true
    echo -e "${BLUE}На сервере${NC} (${REMOTE_USER}@${SERVER}:${REMOTE_DIR}):"
    list_remote | sed 's/^/  /' || true
    exit 0
fi

echo -e "${BLUE}=== Синхронизация пресетов расписания ===${NC}"
echo -e "  локально:   ${LOCAL_DIR}"
echo -e "  сервер:     ${REMOTE_USER}@${SERVER}:${REMOTE_DIR}"
[ -n "$DRY" ] && echo -e "  ${YELLOW}режим: dry-run (ничего не меняется)${NC}"
echo ""

require_dirs

# Локальные файлы, которые нельзя отправлять на сервер
INVALID="$(invalid_local_files)"
if [ -n "$INVALID" ]; then
    echo -e "${YELLOW}Некорректные локальные пресеты (не загружаются на сервер):${NC}"
    while IFS= read -r line; do
        [ -n "$line" ] && echo -e "  ${YELLOW}$line${NC}"
    done <<< "$INVALID"
    echo ""
fi

RSYNC_FILTER=(--include='*.json' --exclude='*')
EXCLUDES=()
if [ -n "$INVALID" ]; then
    while IFS=$'\t' read -r name _rest; do
        [ -n "$name" ] && EXCLUDES+=(--exclude="$name")
    done <<< "$INVALID"
fi

# Снимок состояния ДО копирования: нужен для --mirror и для отчёта о расхождениях
LOCAL_BEFORE="$(list_local)"
REMOTE_BEFORE="$(list_remote)"
ONLY_LOCAL="$(only_in_first "$LOCAL_BEFORE" "$REMOTE_BEFORE")"
ONLY_REMOTE="$(only_in_first "$REMOTE_BEFORE" "$LOCAL_BEFORE")"

if [ "$MIRROR" = "1" ] && { [ -n "$ONLY_LOCAL" ] || [ -n "$ONLY_REMOTE" ]; }; then
    echo -e "${YELLOW}--mirror удалит файлы, которых нет на другой стороне:${NC}"
    [ -n "$ONLY_LOCAL" ] && echo -e "  ${YELLOW}есть только локально:${NC} $(printf '%s\n' "$ONLY_LOCAL" | paste -sd', ' -)"
    [ -n "$ONLY_REMOTE" ] && echo -e "  ${YELLOW}есть только на сервере:${NC} $(printf '%s\n' "$ONLY_REMOTE" | paste -sd', ' -)"
    MIRROR_ANSWER=""
    read -r -p "Удалить эти файлы с обеих сторон? [y/N]: " MIRROR_ANSWER || MIRROR_ANSWER=""
    if [[ "$MIRROR_ANSWER" =~ ^[Yy]$ ]]; then
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            rm -f "${LOCAL_DIR}/${f}"
            remote "rm -f '${REMOTE_DIR}/${f}'"
            echo -e "  ${RED}✗ удалён с обеих сторон: $f${NC}"
        done <<< "$(printf '%s\n%s\n' "$ONLY_LOCAL" "$ONLY_REMOTE")"
        ONLY_LOCAL=""
        ONLY_REMOTE=""
    else
        echo -e "${YELLOW}Зеркалирование отменено — обычная синхронизация${NC}"
    fi
    echo ""
fi

# rsync -i помечает переданные файлы '>f' (приём) или '<f' (отправка) — учитываем оба
changed() { printf '%s\n' "$1" | grep -E '^[<>]f' | awk '{print $2}' || true; }

PULLED=""
PUSHED=""

if [ "$MODE" != "push" ]; then
    echo -e "${BLUE}1. Сервер → локальная машина${NC}"
    PULL_OUT="$(rsync -a --update --itemize-changes $DRY "${RSYNC_FILTER[@]}" \
        "${REMOTE_USER}@${SERVER}:${REMOTE_DIR}/" "${LOCAL_DIR}/")"
    PULLED="$(changed "$PULL_OUT")"
    if [ -n "$PULLED" ]; then
        while IFS= read -r f; do echo -e "  ${GREEN}↓ $f${NC}"; done <<< "$PULLED"
    else
        echo "  изменений нет"
    fi
    echo ""
fi

if [ "$MODE" != "pull" ]; then
    echo -e "${BLUE}2. Локальная машина → сервер${NC}"
    PUSH_OUT="$(rsync -a --update --itemize-changes $DRY "${EXCLUDES[@]+"${EXCLUDES[@]}"}" "${RSYNC_FILTER[@]}" \
        "${LOCAL_DIR}/" "${REMOTE_USER}@${SERVER}:${REMOTE_DIR}/")"
    PUSHED="$(changed "$PUSH_OUT")"
    if [ -n "$PUSHED" ]; then
        while IFS= read -r f; do echo -e "  ${GREEN}↑ $f${NC}"; done <<< "$PUSHED"
    else
        echo "  изменений нет"
    fi
    echo ""
fi

# --- отчёт --------------------------------------------------------------------
if [ -z "$DRY" ]; then
    if [ -n "$ONLY_LOCAL" ] || [ -n "$ONLY_REMOTE" ]; then
        echo -e "${YELLOW}Были только на одной стороне — скопированы на другую:${NC}"
        [ -n "$ONLY_LOCAL" ] && echo -e "  ${YELLOW}загружено с локалки:${NC} $(printf '%s\n' "$ONLY_LOCAL" | paste -sd', ' -)"
        [ -n "$ONLY_REMOTE" ] && echo -e "  ${YELLOW}скачано с сервера:${NC} $(printf '%s\n' "$ONLY_REMOTE" | paste -sd', ' -)"
        echo -e "  Чтобы удаление файла на одной стороне удаляло его и на другой — ${YELLOW}--mirror${NC}"
        echo ""
    fi

    if [ -n "$INVALID" ]; then
        echo -e "${YELLOW}Не синхронизируются (некорректный пресет):${NC}"
        while IFS=$'\t' read -r name reason; do
            [ -n "$name" ] && echo -e "  ${YELLOW}$name — $reason${NC}"
        done <<< "$INVALID"
        echo ""
    fi
fi

echo -e "${BLUE}Итого:${NC}"
echo "  локальная папка: $(list_local | grep -c . || true) файл(ов)"
echo "  на сервере:      $(list_remote | grep -c . || true) файл(ов)"
[ -n "$PULLED" ] && echo -e "  ${GREEN}скачано с сервера: $(printf '%s\n' "$PULLED" | grep -c . || true)${NC}"
[ -n "$PUSHED" ] && echo -e "  ${GREEN}загружено на сервер: $(printf '%s\n' "$PUSHED" | grep -c . || true)${NC}"
echo ""
echo -e "${GREEN}✓ Синхронизация завершена${NC}"
