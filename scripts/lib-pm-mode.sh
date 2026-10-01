#!/usr/bin/env bash
# dsh-pm-mode 共用函式（給 install.sh / uninstall.sh / verify.sh 載入）。
# 只支援 bash 3.2+（macOS 內建版本亦可）。原則：內部一律用 LF 處理，最後再依原檔風格還原 EOL。

PM_VERSION="1.3"
PM_BEGIN='# >>> dsh-pm-mode:begin'
PM_END='# <<< dsh-pm-mode:end'

pm_usage() {
    cat <<EOF
用法: $1 [--dsh-home DIR] [--profile NAME]

  --dsh-home DIR   DSH home（預設 \$DSH_HOME，否則 ~/.dsh）
  --profile NAME   只處理這一個 profile（預設：所有支援 agent preset 的 profile 都裝）
  -h, --help       顯示這段說明
EOF
}

# 解析參數：設定 DSH_HOME / PROFILE（PROFILE 空 = 自動挑所有支援 preset 的 profile）
pm_parse_args() {
    DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
    PROFILE=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --dsh-home) DSH_HOME="${2:-}"; shift 2 ;;
            --profile)  PROFILE="${2:-}";  shift 2 ;;
            -h|--help)  pm_usage "$0"; exit 0 ;;
            *) printf '未知參數：%s\n' "$1" >&2; pm_usage "$0" >&2; exit 2 ;;
        esac
    done
    if [ -z "$DSH_HOME" ]; then printf 'DSH_HOME 不可為空\n' >&2; exit 2; fi
}

# 列出所有含 cordis.patch.yml 的 profile（每行一個）
pm_all_profiles() {
    local d
    [ -d "$DSH_HOME/profiles" ] || return 0
    for d in "$DSH_HOME"/profiles/*/; do
        [ -f "${d}cordis.patch.yml" ] || continue
        basename "$d"
    done
}

# 這個 profile 是否看得出支援 agent preset（bundle 含 dsh-web-app，或 patch 已提到 agent-preset）
pm_is_preset_capable() {
    local name="$1"
    local dir="$DSH_HOME/profiles/$name"
    if [ -f "$dir/package.json" ] && grep -q 'dsh-web-app' "$dir/package.json" 2>/dev/null; then
        return 0
    fi
    if grep -qE 'agent-preset|dsh-agent-preset' "$dir/cordis.patch.yml" 2>/dev/null; then
        return 0
    fi
    return 1
}

# 決定要處理哪些 profile。結果放進 PM_TARGETS 陣列；每個 profile 的 patch 為 $DSH_HOME/profiles/<name>/cordis.patch.yml
pm_resolve_targets() {
    PM_TARGETS=()
    local name
    if [ -n "${PROFILE:-}" ]; then
        if [ ! -f "$DSH_HOME/profiles/$PROFILE/cordis.patch.yml" ]; then
            printf '找不到 profile %s；可選：%s\n' "$PROFILE" "$(pm_all_profiles | tr '\n' ' ')" >&2
            exit 1
        fi
        PM_TARGETS=("$PROFILE")
        return 0
    fi
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        if pm_is_preset_capable "$name"; then
            PM_TARGETS+=("$name")
        fi
    done <<EOF
$(pm_all_profiles)
EOF
    if [ "${#PM_TARGETS[@]}" -eq 0 ]; then
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            PM_TARGETS+=("$name")
        done <<EOF
$(pm_all_profiles)
EOF
        printf '（沒有 profile 明顯支援 preset，仍對全部 profile 安裝）\n'
    fi
}

# 向後相容：只取第一個目標（舊呼叫端）
pm_resolve_profile() {
    pm_resolve_targets
    PROFILE="${PM_TARGETS[0]:-}"
    if [ -z "$PROFILE" ]; then
        printf '在 %s/profiles 找不到任何含 cordis.patch.yml 的 profile\n' "$DSH_HOME" >&2
        exit 1
    fi
    PATCH="$DSH_HOME/profiles/$PROFILE/cordis.patch.yml"
}

# 在 Windows（Git Bash / MSYS）把 MSYS 路徑轉成 C:/… 形式；其他平台原樣輸出
pm_render_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1"
    else
        printf '%s' "$1"
    fi
}

pm_backup() {
    local target="$1" stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    cp "$target" "$target.bak-pm-$stamp"
    printf '%s' "$target.bak-pm-$stamp"
}

# 原檔是否用 CRLF：0=是 1=否
pm_file_has_crlf() {
    if grep -q $'\r' "$1" 2>/dev/null; then return 0; else return 1; fi
}

# 移除 marker 區塊並去除尾端空行，一律輸出 LF。$1=來源 $2=輸出
pm_strip_block_lf() {
    local patch="$1" out="$2"
    awk -v b="$PM_BEGIN" -v e="$PM_END" '
        { line=$0; sub(/\r$/, "", line) }
        line == b { skip=1 }
        skip == 1 && line == e { skip=0; next }
        skip == 0 { print line }
    ' "$patch" | awk 'BEGIN { n=0 }
        { a[NR]=$0 }
        END { n=NR; while (n>0 && a[n] ~ /^[[:space:]]*$/) n--; for (i=1;i<=n;i++) print a[i] }' > "$out"
}

# 渲染 preset 區塊（含 marker），一律輸出 LF。$1=來源檔 $2=渲染後 skills 路徑 $3=輸出
pm_render_block_lf() {
    local source="$1" rendered="$2" out="$3"
    {
        printf '%s\n' "$PM_BEGIN"
        sed "s#{{PM_SKILLS_DIR}}#$rendered#g" "$source" | tr -d '\r'
        printf '%s\n' "$PM_END"
    } > "$out"
}

# 把 LF 檔寫成目標檔；$3=1 表示要 CRLF
pm_write_with_eol() {
    local src="$1" dst="$2" crlf="${3:-0}"
    if [ "$crlf" = "1" ]; then
        awk '{ printf "%s\r\n", $0 }' "$src" > "$dst"
    else
        cp "$src" "$dst"
    fi
}

# 統計檢查：印出 begin/end/pm_ids/rows/placeholders
pm_counts() {
    local f="$1"
    printf '  begin=%s end=%s pm_ids=%s preset_pm_rows=%s placeholders=%s\n' \
        "$(grep -c -- "$PM_BEGIN" "$f" || true)" \
        "$(grep -c -- "$PM_END" "$f" || true)" \
        "$(grep -cE '^[[:space:]]*id:[[:space:]]*pm[[:space:]]*$' "$f" || true)" \
        "$(grep -cE '^[[:space:]]*-[[:space:]]*id:[[:space:]]*preset-pm[[:space:]]*$' "$f" || true)" \
        "$(grep -c -- '{{PM_SKILLS_DIR}}' "$f" || true)"
}
