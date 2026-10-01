#!/usr/bin/env bash
# dsh-pm-mode 驗證腳本（macOS / Linux，含 Windows 的 Git Bash）。
#
#   驗收項 1–3：
#     1. patch 檔 YAML 語法有效（有 node + profile 內 yaml 套件時）
#     2. marker 區塊與 preset id 各只有一個、placeholder 已渲染且指向存在的技能目錄
#     3. `dsh --profile <p> --dump-config` 與 baseline 的差異沒有移除任何既有行
#
#   另外檢查安裝到 <DSH_HOME>/pm-mode/skills 的技能 frontmatter 與長度。
#
#   用法：
#     bash scripts/verify.sh -Snapshot   # 安裝前：存 baseline
#     bash scripts/verify.sh             # 安裝後：完整檢查
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-pm-mode.sh
. "$SCRIPT_DIR/lib-pm-mode.sh"

SNAPSHOT=0
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -Snapshot|--snapshot) SNAPSHOT=1; shift ;;
        *) ARGS+=("$1"); shift ;;
    esac
done
if [ "${#ARGS[@]}" -gt 0 ]; then pm_parse_args "${ARGS[@]}"; else pm_parse_args; fi

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS="$REPO_ROOT/.artifacts"
mkdir -p "$ARTIFACTS"

pm_resolve_profile

MODE_DIR="$DSH_HOME/pm-mode"
SKILLS_DIR="$MODE_DIR/skills"
MANIFEST="$MODE_DIR/install.json"
# 給 dsh 用的 home：在 Windows Git Bash 要轉成 C:/… 形式，否則 dsh 解析不到
DSH_HOME_FOR_DSH="$(pm_render_path "$DSH_HOME")"
FAILURES=0

ok()   { printf '  [OK]   %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

dump_config() {
    local out="$1"
    if ! command -v dsh >/dev/null 2>&1; then
        warn '找不到 dsh 指令，跳過 dump-config'
        return 1
    fi
    if DSH_HOME="$DSH_HOME_FOR_DSH" dsh --profile "$PROFILE" --dump-config > "$out" 2>/dev/null; then
        return 0
    fi
    warn 'dump-config 執行失敗'
    return 1
}

if [ "$SNAPSHOT" = "1" ]; then
    printf '== 建立 baseline（安裝前）==\n'
    if dump_config "$ARTIFACTS/dump-baseline.txt"; then
        printf '%s' "$DSH_HOME_FOR_DSH" > "$ARTIFACTS/dump-baseline.home"
        printf '已寫入 %s（%s 行，DSH home = %s）\n' "$ARTIFACTS/dump-baseline.txt" \
            "$(wc -l < "$ARTIFACTS/dump-baseline.txt" | tr -d ' ')" "$DSH_HOME_FOR_DSH"
    fi
    exit 0
fi

printf '== dsh-pm-mode 驗證 ==\n'
printf 'DSH home  : %s\n' "$DSH_HOME"
printf 'profile   : %s\n' "$PROFILE"

# --- 1. YAML ----------------------------------------------------------------
printf '[1/4] YAML 語法\n'
if [ ! -f "$PATCH" ]; then
    bad "找不到 patch 檔：$PATCH"
elif command -v node >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/check-yaml.mjs" ]; then
    if node "$(pm_render_path "$SCRIPT_DIR/check-yaml.mjs")" \
            "$(pm_render_path "$PATCH")" \
            "$(pm_render_path "$DSH_HOME/profiles/$PROFILE")"; then
        :
    else
        bad 'YAML 解析失敗'
    fi
else
    warn '找不到 node 或 check-yaml.mjs，跳過 YAML 解析（改由 dump-config 把關）'
fi

# --- 2. marker / id / 渲染 --------------------------------------------------
printf '[2/4] marker、preset id、skills 路徑\n'
rendered=""
if [ -f "$PATCH" ]; then
    counts="$(pm_counts "$PATCH")"
    printf '%s\n' "$counts"
    begin_n="$(printf '%s' "$counts" | sed -n 's/.*begin=\([0-9]*\).*/\1/p')"
    end_n="$(printf '%s' "$counts" | sed -n 's/.*end=\([0-9]*\).*/\1/p')"
    pm_n="$(printf '%s' "$counts" | sed -n 's/.*pm_ids=\([0-9]*\).*/\1/p')"
    row_n="$(printf '%s' "$counts" | sed -n 's/.*preset_pm_rows=\([0-9]*\).*/\1/p')"
    ph_n="$(printf '%s' "$counts" | sed -n 's/.*placeholders=\([0-9]*\).*/\1/p')"
    [ "$begin_n" = "1" ] && [ "$end_n" = "1" ] && ok 'marker 區塊恰好 1 組' || bad "marker 數量異常（begin=$begin_n, end=$end_n）"
    [ "$pm_n" = "1" ]  && ok 'preset id `pm` 恰好 1 個'   || bad "id: pm 出現 $pm_n 次（應為 1）"
    [ "$row_n" = "1" ] && ok '宣告行 `preset-pm` 恰好 1 個' || bad "preset-pm 宣告行出現 $row_n 次（應為 1）"
    if [ "$ph_n" != "0" ]; then
        bad "仍有 $ph_n 處 {{PM_SKILLS_DIR}} 未渲染（請重跑 install）"
    else
        rendered="$(grep -oE "[- ]'?[A-Za-z]:/[^']*/pm-mode/skills'?" "$PATCH" | tr -d "'" | sed 's/^[- ]*//' | head -n 1 || true)"
        if [ -z "$rendered" ]; then
            rendered="$(grep -oE "[- ]'?/[^']*pm-mode/skills'?" "$PATCH" | tr -d "'" | sed 's/^[- ]*//' | head -n 1 || true)"
        fi
        if [ -n "$rendered" ]; then ok "skills 路徑已渲染：$rendered"; else bad '找不到渲染後的 customSkillDirs 路徑'; fi
    fi
fi

# --- 3. 已安裝的 skills -----------------------------------------------------
printf '[3/4] 已安裝的 skills\n'
if [ ! -d "$SKILLS_DIR" ]; then
    bad "找不到已安裝的 skills 目錄：$SKILLS_DIR（請先跑 install）"
else
    if [ -n "$rendered" ]; then
        if [ "$rendered" = "$(pm_render_path "$SKILLS_DIR")" ]; then
            ok 'preset 指向的目錄與實際安裝位置一致'
        else
            bad "preset 指向 $rendered，實際在 $(pm_render_path "$SKILLS_DIR")"
        fi
    fi
    n=0
    for dir in "$SKILLS_DIR"/*/; do
        [ -d "$dir" ] || continue
        n=$((n + 1))
        name="$(basename "$dir")"
        file="$dir/SKILL.md"
        if [ ! -f "$file" ]; then bad "$name：缺少 SKILL.md"; continue; fi
        chars="$(wc -c < "$file" | tr -d ' ')"
        problems=""
        grep -qE "^name:[[:space:]]*$name[[:space:]]*$" "$file" || problems="$problems frontmatter-name不符"
        grep -qE '^description:[[:space:]]*[^[:space:]]' "$file" || problems="$problems 缺description"
        case "$name" in *[!a-z0-9-]*) problems="$problems 非kebab-case" ;; esac
        [ "$chars" -le 8000 ] || problems="$problems 長度 $chars 超過 8000"
        if [ -z "$problems" ]; then ok "$name（$chars 字元）"; else bad "$name：$problems"; fi
    done
    [ "$n" -gt 0 ] || bad "skills 目錄是空的：$SKILLS_DIR"
fi

if [ -f "$MANIFEST" ]; then ok "manifest 存在：$MANIFEST"; else warn "找不到 manifest：$MANIFEST"; fi

TEMPLATES_DIR="$MODE_DIR/templates"
if [ -f "$TEMPLATES_DIR/project/README.md" ]; then
    ok "templates 已安裝：$TEMPLATES_DIR"
else
    warn "找不到已安裝的 templates（$TEMPLATES_DIR）；PM 開新專案時會改用手動結構（見 pm-scaffold skill）"
fi

# --- 4. dump diff -----------------------------------------------------------
printf '[4/4] dump-config 差異\n'
BASELINE="$ARTIFACTS/dump-baseline.txt"
BASELINE_HOME=""
[ -f "$ARTIFACTS/dump-baseline.home" ] && BASELINE_HOME="$(cat "$ARTIFACTS/dump-baseline.home")"
if [ ! -f "$BASELINE" ]; then
    warn '沒有 baseline；請在安裝前先跑 verify.sh -Snapshot。仍會存下本次 dump。'
    dump_config "$ARTIFACTS/dump-after.txt" || true
elif [ -n "$BASELINE_HOME" ] && [ "$BASELINE_HOME" != "$DSH_HOME_FOR_DSH" ]; then
    warn "baseline 是針對 $BASELINE_HOME 取的，與目前 $DSH_HOME_FOR_DSH 不同；跳過差異比對（仍會存下本次 dump）"
    dump_config "$ARTIFACTS/dump-after.txt" || true
elif dump_config "$ARTIFACTS/dump-after.txt"; then
    # 基準檔可能是別的平台／別的腳本寫的（BOM、CRLF 不同），先正規化再比對
    tr -d '\357\273\277\r' < "$BASELINE" > "$ARTIFACTS/.baseline.lf"
    tr -d '\357\273\277\r' < "$ARTIFACTS/dump-after.txt" > "$ARTIFACTS/.after.lf"
    added="$(diff "$ARTIFACTS/.baseline.lf" "$ARTIFACTS/.after.lf" | grep -c '^>' || true)"
    removed="$(diff "$ARTIFACTS/.baseline.lf" "$ARTIFACTS/.after.lf" | grep -c '^<' || true)"
    printf '  新增 %s 行、移除 %s 行\n' "$added" "$removed"
    if [ "$removed" -gt 0 ]; then
        printf '  --- 移除（前 20 行）---\n'
        diff "$ARTIFACTS/.baseline.lf" "$ARTIFACTS/.after.lf" | grep '^<' | head -n 20 | sed 's/^/   /'
        bad "有 $removed 行被移除，請檢查是否影響其他 preset"
    else
        ok '沒有任何既有行被移除（無回歸）'
    fi
fi

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
    printf '全部檢查通過。\n'
    exit 0
fi
printf '有 %s 項失敗。\n' "$FAILURES"
exit 1
