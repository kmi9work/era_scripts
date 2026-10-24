#!/bin/bash
# era-games.sh — единый реестр игровых движков и плагинов платформы Era.
#
# Подключается из deploy-скриптов:
#     source "$SCRIPTS_DIR/lib/era-games.sh"
#
# Ничего не знает «наизусть»: движки берутся из eraofchange/engines/*,
# плагины — из <клиент>/src/plugins/game-plugins/*. Ключ игры (то, что уходит
# в ACTIVE_GAME / VITE_ACTIVE_GAME) выводится из кода:
#   1) engines/<движок>/era_game.conf   — манифест движка (key=...), если заведён;
#   2) engines/<движок>/lib/<движок>.rb — константа ACTIVE_GAME = "...";
#   3) engines/<движок>/lib/<движок>/engine.rb — сравнение ENV['ACTIVE_GAME'] == '...';
#   4) иначе — имя каталога движка, подчёркивания заменяются дефисами.
# Для плагина: GAME_KEY = '...' или GAME_CONFIG.isActive('...') в index.js/index.ts,
# иначе — имя каталога плагина.
#
# Публичные функции:
#   era_build_registry                 — собрать реестр (обязательный первый вызов)
#   era_list_games [--verbose]         — пронумерованный список игр
#   era_resolve_game <номер|ключ|имя>  — выставить ERA_GAME_KEY/ERA_GAME_ENGINE/ERA_GAME_SEEDS
#   era_plugin_dir <репо> <ключ>       — каталог плагина игры в клиенте (или код 1)
#   era_engine_names                   — имена всех движков
#   era_engine_key <движок>            — ключ игры движка
#   era_plugin_names <репо>            — имена всех плагинов клиента
#   era_plugin_key <репо> <плагин>     — ключ игры плагина
#   era_branch_has_engine <репо> <ветка> <движок>   — 0/1/2 (2 — не git-репозиторий)
#   era_branch_for_engine <репо> <движок> <ветка-по-умолчанию>
#   era_branch_has_path <репо> <ветка> <путь>       — 0/1/2
#   era_branch_for_path <репо> <путь> <ветка-по-умолчанию>

# ← корень проекта (eraofchange, era_front, era_native, era_players лежат рядом)
ERA_ROOT="${ERA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ERA_BACKEND_DIR="${ERA_BACKEND_DIR:-$ERA_ROOT/eraofchange}"
ERA_FRONT_DIR="${ERA_FRONT_DIR:-$ERA_ROOT/era_front}"
ERA_NATIVE_DIR="${ERA_NATIVE_DIR:-$ERA_ROOT/era_native}"
ERA_PLAYERS_DIR="${ERA_PLAYERS_DIR:-$ERA_ROOT/era_players}"

# Клиенты фронта в порядке показа
ERA_CLIENTS=(era_front era_native era_players)

era_client_dir() {
    case "$1" in
        era_front)   printf '%s\n' "$ERA_FRONT_DIR" ;;
        era_native)  printf '%s\n' "$ERA_NATIVE_DIR" ;;
        era_players) printf '%s\n' "$ERA_PLAYERS_DIR" ;;
        *)           printf '%s\n' "$1" ;;
    esac
}

# Нормализация ключа: регистр не важен, «-» и «_» равнозначны.
era_key_norm() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '_-'
}

# --- Движки (eraofchange/engines) -------------------------------------------

era_engine_names() {
    local dir name
    for dir in "$ERA_BACKEND_DIR"/engines/*/; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        if [ -f "$dir/lib/$name/engine.rb" ]; then
            printf '%s\n' "$name"
        fi
    done
}

# Ветки локального репозитория, где лежит движок (через пробел).
era_engine_branches() {
    local repo="$1" engine="$2"
    local branch out=""
    while IFS= read -r branch; do
        [ -n "$branch" ] || continue
        [ "$branch" = "HEAD" ] && continue
        if era_branch_has_path "$repo" "$branch" "engines/$engine"; then
            out="$out ${branch}"
        fi
    done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
    printf '%s\n' "${out# }"
}

era_engine_key() {
    local engine="$1"
    local dir="$ERA_BACKEND_DIR/engines/$engine"
    local key=""

    # 1) манифест движка: engines/<name>/era_game.conf, строка «key = ...»
    if [ -f "$dir/era_game.conf" ]; then
        key="$(sed -n 's/^[[:space:]]*key[[:space:]]*=[[:space:]]*//p' "$dir/era_game.conf" | head -1 | tr -d '"'\''[:space:]')"
        if [ -n "$key" ]; then
            printf '%s\n' "$key"
            return 0
        fi
    fi

    # 2) константа ACTIVE_GAME = "..." в lib/<name>.rb
    if [ -f "$dir/lib/$engine.rb" ]; then
        key="$(sed -n 's/.*ACTIVE_GAME[[:space:]]*=[[:space:]]*["'\'']\([^"'\'']*\)["'\''].*/\1/p' "$dir/lib/$engine.rb" | head -1)"
    fi

    # 3) сравнение ENV['ACTIVE_GAME'] == '...' в lib/<name>/engine.rb
    if [ -z "$key" ] && [ -f "$dir/lib/$engine/engine.rb" ]; then
        key="$(sed -n "s/.*ENV\[['\"]ACTIVE_GAME['\"]\][[:space:]]*==[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" "$dir/lib/$engine/engine.rb" | head -1)"
    fi

    # 4) фолбэк — имя каталога движка
    if [ -z "$key" ]; then
        key="${engine//_/-}"
    fi

    printf '%s\n' "$key"
}

# --- Плагины (<клиент>/src/plugins/game-plugins) -----------------------------

era_plugin_names() {
    local repo="$1" dir name
    for dir in "$repo"/src/plugins/game-plugins/*/; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        printf '%s\n' "$name"
    done
}

era_plugin_key() {
    local repo="$1" plugin="$2"
    local dir="$repo/src/plugins/game-plugins/$plugin"
    local file key=""

    for file in "$dir/index.js" "$dir/index.jsx" "$dir/index.ts" "$dir/index.tsx"; do
        [ -f "$file" ] || continue
        key="$(sed -n 's/.*GAME_KEY[[:space:]]*=[[:space:]]*["'\'']\([^"'\'']*\)["'\''].*/\1/p' "$file" | head -1)"
        [ -n "$key" ] && break
        key="$(sed -n "s/.*isActive(['\"]\([^'\"]*\)['\"]).*/\1/p" "$file" | head -1)"
        [ -n "$key" ] && break
    done

    if [ -z "$key" ]; then
        key="${plugin//_/-}"
    fi

    printf '%s\n' "$key"
}

# Каталог плагина игры <ключ> в клиенте <репо>; код 1, если плагина нет.
era_plugin_dir() {
    local repo="$1" key="$2"
    local norm dir name
    norm="$(era_key_norm "$key")"
    [ -n "$norm" ] || return 1
    for dir in "$repo"/src/plugins/game-plugins/*/; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        if [ "$(era_key_norm "$name")" = "$norm" ]; then
            printf '%s\n' "$name"
            return 0
        fi
        if [ "$(era_key_norm "$(era_plugin_key "$repo" "$name")")" = "$norm" ]; then
            printf '%s\n' "$name"
            return 0
        fi
    done
    return 1
}

# --- Реестр игр --------------------------------------------------------------

era_build_registry() {
    declare -ga ERA_GAME_KEYS=()
    declare -gA ERA_ENGINE_BY_KEY=()
    declare -gA ERA_SEEDS_BY_KEY=()
    local -a engines=() keys=()
    local engine key i p

    ERA_GAME_KEYS=("base-game")
    ERA_ENGINE_BY_KEY["base-game"]=""
    ERA_SEEDS_BY_KEY["base-game"]=""

    for engine in $(era_engine_names); do
        engines+=("$engine")
        keys+=("$(era_engine_key "$engine")")
    done

    # 1) ключи, которые обязаны сохранить прежнюю нумерацию (2 — vassals, 3 — artel)
    for p in vassals-and-robbers artel; do
        for i in "${!engines[@]}"; do
            [ "${keys[$i]}" = "$p" ] || continue
            [ -n "${ERA_ENGINE_BY_KEY[${keys[$i]}]:-}" ] && continue
            ERA_GAME_KEYS+=("${keys[$i]}")
            ERA_ENGINE_BY_KEY["${keys[$i]}"]="${engines[$i]}"
        done
    done

    # 2) остальные движки — по алфавиту имён каталогов
    for i in "${!engines[@]}"; do
        key="${keys[$i]}"
        [ -n "${ERA_ENGINE_BY_KEY[$key]:-}" ] && continue
        ERA_GAME_KEYS+=("$key")
        ERA_ENGINE_BY_KEY["$key"]="${engines[$i]}"
    done

    # 3) игры, у которых есть только плагин (движка нет в этом чекауте)
    local client repo pdir pkey dup known
    for client in "${ERA_CLIENTS[@]}"; do
        repo="$(era_client_dir "$client")"
        [ -d "$repo" ] || continue
        for pdir in $(era_plugin_names "$repo"); do
            pkey="$(era_plugin_key "$repo" "$pdir")"
            dup=0
            for known in "${ERA_GAME_KEYS[@]}"; do
                if [ "$(era_key_norm "$known")" = "$(era_key_norm "$pkey")" ]; then
                    dup=1
                    break
                fi
            done
            if [ "$dup" = "0" ]; then
                ERA_GAME_KEYS+=("$pkey")
                ERA_ENGINE_BY_KEY["$pkey"]=""
            fi
        done
    done

    local seeds
    for key in "${ERA_GAME_KEYS[@]}"; do
        engine="${ERA_ENGINE_BY_KEY[$key]:-}"
        seeds=""
        if [ -n "$engine" ] && [ -d "$ERA_BACKEND_DIR/engines/$engine/db/seeds" ]; then
            seeds="engines/$engine/db/seeds"
        fi
        ERA_SEEDS_BY_KEY["$key"]="$seeds"
    done
}

# Строка описания игры для меню: движок + плагины клиентов.
era_game_description() {
    local key="$1" engine plugin out
    engine="${ERA_ENGINE_BY_KEY[$key]:-}"
    local client repo
    if [ -n "$engine" ]; then
        out="движок: $engine"
        for client in "${ERA_CLIENTS[@]}"; do
            repo="$(era_client_dir "$client")"
            [ -d "$repo" ] || continue
            plugin="$(era_plugin_dir "$repo" "$key" || true)"
            out="$out; $client: ${plugin:-—}"
        done
        printf '%s\n' "$out"
        return 0
    fi
    # движка нет — показываем хотя бы плагины
    out=""
    for client in "${ERA_CLIENTS[@]}"; do
        repo="$(era_client_dir "$client")"
        [ -d "$repo" ] || continue
        plugin="$(era_plugin_dir "$repo" "$key" || true)"
        if [ -n "$plugin" ]; then
            out="${out:+$out; }$client: $plugin"
        fi
    done
    printf '%s\n' "${out:-ядро без движков и плагинов}"
}

era_list_games() {
    local i=1 key
    for key in "${ERA_GAME_KEYS[@]}"; do
        printf '  %d) %-20s %s\n' "$i" "$key" "$(era_game_description "$key")"
        i=$((i + 1))
    done
}

# Полный отчёт об обнаруженном (для --list).
era_report() {
    local engine key client repo plugin branches
    echo "eraofchange/engines ($ERA_BACKEND_DIR):"
    for engine in $(era_engine_names); do
        key="$(era_engine_key "$engine")"
        branches="$(era_engine_branches "$ERA_BACKEND_DIR" "$engine" || true)"
        printf '  - %-22s ключ: %-18s сиды: %s\n' "$engine" "$key" \
            "$([ -d "$ERA_BACKEND_DIR/engines/$engine/db/seeds" ] && echo "engines/$engine/db/seeds" || echo "—")"
        printf '    ветки: %s\n' "${branches:-—}"
    done
    for client in "${ERA_CLIENTS[@]}"; do
        repo="$(era_client_dir "$client")"
        if [ ! -d "$repo" ]; then
            echo "$client: каталог не найден ($repo)"
            continue
        fi
        echo "$client/src/plugins/game-plugins:"
        local found=0
        for plugin in $(era_plugin_names "$repo"); do
            found=1
            printf '  - %-22s ключ игры: %s\n' "$plugin" "$(era_plugin_key "$repo" "$plugin")"
        done
        [ "$found" = "1" ] || echo "  (плагинов нет)"
    done
    echo ""
    echo "Игры для деплоя (номер → ключ ACTIVE_GAME):"
    era_list_games
}

# Разбор выбора пользователя: номер из меню, ключ игры, имя движка или плагина.
# Выставляет ERA_GAME_KEY, ERA_GAME_ENGINE, ERA_GAME_SEEDS. Код 1 — не найдено.
era_resolve_game() {
    local answer="$1"
    local key engine client repo norm i pdir plugin_key
    [ -n "$answer" ] || return 1

    ERA_GAME_KEY=""

    if [[ "$answer" =~ ^[0-9]+$ ]]; then
        i=$((answer - 1))
        if [ "$i" -ge 0 ] && [ "$i" -lt "${#ERA_GAME_KEYS[@]}" ]; then
            ERA_GAME_KEY="${ERA_GAME_KEYS[$i]}"
        fi
    else
        norm="$(era_key_norm "$answer")"
        for key in "${ERA_GAME_KEYS[@]}"; do
            if [ "$(era_key_norm "$key")" = "$norm" ]; then
                ERA_GAME_KEY="$key"
                break
            fi
        done

        # имя каталога движка
        if [ -z "$ERA_GAME_KEY" ]; then
            for key in "${ERA_GAME_KEYS[@]}"; do
                engine="${ERA_ENGINE_BY_KEY[$key]:-}"
                if [ -n "$engine" ] && [ "$(era_key_norm "$engine")" = "$norm" ]; then
                    ERA_GAME_KEY="$key"
                    break
                fi
            done
        fi

        # имя каталога плагина в любом клиенте
        if [ -z "$ERA_GAME_KEY" ]; then
            for client in "${ERA_CLIENTS[@]}"; do
                repo="$(era_client_dir "$client")"
                [ -d "$repo" ] || continue
                for pdir in $(era_plugin_names "$repo"); do
                    [ "$(era_key_norm "$pdir")" = "$norm" ] || continue
                    plugin_key="$(era_plugin_key "$repo" "$pdir")"
                    for key in "${ERA_GAME_KEYS[@]}"; do
                        if [ "$(era_key_norm "$key")" = "$(era_key_norm "$plugin_key")" ]; then
                            ERA_GAME_KEY="$key"
                            break 2
                        fi
                    done
                done
            done
        fi
    fi

    [ -n "$ERA_GAME_KEY" ] || return 1

    ERA_GAME_ENGINE="${ERA_ENGINE_BY_KEY[$ERA_GAME_KEY]:-}"
    ERA_GAME_SEEDS="${ERA_SEEDS_BY_KEY[$ERA_GAME_KEY]:-}"
    return 0
}

# --- Ветки git: где лежит движок/плагин --------------------------------------

# 0 — путь есть в ветке, 1 — нет, 2 — репозиторий не git.
era_branch_has_path() {
    local repo="$1" branch="$2" path="$3"
    local found
    git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 2
    [ -n "$branch" ] || return 1
    found="$(git -C "$repo" ls-tree --name-only "$branch" "$path" 2>/dev/null | head -1)"
    if [ -z "$found" ]; then
        found="$(git -C "$repo" ls-tree --name-only "origin/$branch" "$path" 2>/dev/null | head -1)"
    fi
    [ -n "$found" ]
}

era_branch_has_engine() {
    local repo="$1" branch="$2" engine="$3"
    [ -n "$engine" ] || return 0
    era_branch_has_path "$repo" "$branch" "engines/$engine"
}

# Первая локальная ветка, где есть путь (ветка по умолчанию — первой).
era_branch_for_path() {
    local repo="$1" path="$2" default="$3"
    local branch rc=0
    era_branch_has_path "$repo" "$default" "$path" || rc=$?
    if [ "$rc" = "0" ] || [ "$rc" = "2" ]; then
        printf '%s\n' "$default"
        return 0
    fi
    while IFS= read -r branch; do
        [ -n "$branch" ] || continue
        [ "$branch" = "HEAD" ] && continue
        if era_branch_has_path "$repo" "$branch" "$path"; then
            printf '%s\n' "$branch"
            return 0
        fi
    done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
    return 1
}

era_branch_for_engine() {
    era_branch_for_path "$1" "engines/$2" "$3"
}
