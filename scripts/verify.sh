#!/usr/bin/env bash
# dsh-pm-mode 驗證腳本（macOS / Linux，含 Windows 的 Git Bash）。
#
#   驗收項 1–3（對每個目標 profile 各做一次）：
#     1. patch 檔 YAML 語法有效（有 node + profile 內 yaml 套件時）
#     2. marker 區塊與 preset id 各只有一個、placeholder 已渲染且指向存在的技能目錄
#     3. `dsh --profile <p> --dump-config` 與該 profile 的 baseline 差異沒有移除任何既有行
#   另外檢查安裝到 <DSH_HOME>/pm-mode 的技能、樣板與 manifest。
#
#   用法：
#     bash scripts/verify.sh -Snapshot   # 安裝前：對每個 profile 存 baseline
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

pm_resolve_targets

MODE_DIR="$DSH_HOME/pm-mode"
SKILLS_DIR="$MODE_DIR/skills"
TEMPLATES_DIR="$MODE_DIR/templates"
MANIFEST="$MODE_DIR/install.json"
# 給 dsh 用的 home：在 Windows Git Bash 要轉成 C:/… 形式，否則 dsh 解析不到
DSH_HOME_FOR_DSH="$(pm_render_path "$DSH_HOME")"
FAILURES=0

ok()   { printf '  [OK]   %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

dump_config() {
    local profile="$1" out="$2"
    if ! command -v dsh >/dev/null 2>&1; then
        warn '找不到 dsh 指令，跳過 dump-config'
        return 1
    fi
    if DSH_HOME="$DSH_HOME_FOR_DSH" dsh --profile "$profile" --dump-config > "$out" 2>/dev/null; then
        return 0
    fi
    warn 'dump-config 執行失敗'
    return 1
}

if [ "$SNAPSHOT" = "1" ]; then
    printf '== 建立 baseline（安裝前）==\n'
    for name in "${PM_TARGETS[@]}"; do
        if dump_config "$name" "$ARTIFACTS/dump-baseline-$name.txt"; then
            printf '%s' "$DSH_HOME_FOR_DSH" > "$ARTIFACTS/dump-baseline-$name.home"
            printf '  已寫入 dump-baseline-%s.txt（%s 行，DSH home = %s）\n' "$name" \
                "$(wc -l < "$ARTIFACTS/dump-baseline-$name.txt" | tr -d ' ')" "$DSH_HOME_FOR_DSH"
        fi
    done
    exit 0
fi

printf '== dsh-pm-mode 驗證 ==\n'
printf 'DSH home  : %s\n' "$DSH_HOME"
printf 'profiles  : %s\n' "${PM_TARGETS[*]}"

# --- 1. YAML（逐 profile）----------------------------------------------------
printf '[1/4] YAML 語法（逐 profile）\n'
for name in "${PM_TARGETS[@]}"; do
    PATCH="$DSH_HOME/profiles/$name/cordis.patch.yml"
    printf '  --- %s ---\n' "$name"
    if [ ! -f "$PATCH" ]; then
        bad "[$name] 找不到 patch 檔：$PATCH"
    elif command -v node >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/check-yaml.mjs" ]; then
        if ! node "$(pm_render_path "$SCRIPT_DIR/check-yaml.mjs")" \
                "$(pm_render_path "$PATCH")" \
                "$(pm_render_path "$DSH_HOME/profiles/$name")"; then
            bad "[$name] YAML 解析失敗"
        fi
    else
        warn '找不到 node 或 check-yaml.mjs，跳過 YAML 解析（改由 dump-config 把關）'
    fi
done

# --- 2. marker / id / 渲染（逐 profile）-------------------------------------
printf '[2/4] marker、preset id、skills 路徑（逐 profile）\n'
declare -A RENDERED=()
for name in "${PM_TARGETS[@]}"; do
    PATCH="$DSH_HOME/profiles/$name/cordis.patch.yml"
    [ -f "$PATCH" ] || continue
    printf '  --- %s ---\n' "$name"
    counts="$(pm_counts "$PATCH")"
    printf '%s\n' "$counts"
    begin_n="$(printf '%s' "$counts" | sed -n 's/.*begin=\([0-9]*\).*/\1/p')"
    end_n="$(printf '%s' "$counts" | sed -n 's/.*end=\([0-9]*\).*/\1/p')"
    pm_n="$(printf '%s' "$counts" | sed -n 's/.*pm_ids=\([0-9]*\).*/\1/p')"
    row_n="$(printf '%s' "$counts" | sed -n 's/.*preset_pm_rows=\([0-9]*\).*/\1/p')"
    ph_n="$(printf '%s' "$counts" | sed -n 's/.*placeholders=\([0-9]*\).*/\1/p')"
    [ "$begin_n" = "1" ] && [ "$end_n" = "1" ] && ok 'marker 區塊恰好 1 組' || bad "[$name] marker 數量異常（begin=$begin_n, end=$end_n）"
    [ "$pm_n" = "1" ]  && ok 'preset id `pm` 恰好 1 個'   || bad "[$name] id: pm 出現 $pm_n 次（應為 1）"
    [ "$row_n" = "1" ] && ok '宣告行 `preset-pm` 恰好 1 個' || bad "[$name] preset-pm 宣告行出現 $row_n 次（應為 1）"
    if [ "$ph_n" != "0" ]; then
        bad "[$name] 仍有 $ph_n 處 {{PM_SKILLS_DIR}} 未渲染（請重跑 install）"
    else
        rendered="$(grep -oE "[- ]'?[A-Za-z]:/[^']*/pm-mode/skills'?" "$PATCH" | tr -d "'" | sed 's/^[- ]*//' | head -n 1 || true)"
        if [ -z "$rendered" ]; then
            rendered="$(grep -oE "[- ]'?/[^']*pm-mode/skills'?" "$PATCH" | tr -d "'" | sed 's/^[- ]*//' | head -n 1 || true)"
        fi
        if [ -n "$rendered" ]; then
            RENDERED["$name"]="$rendered"
            ok "skills 路徑已渲染：$rendered"
        else
            bad "[$name] 找不到渲染後的 customSkillDirs 路徑"
        fi
    fi
done

# --- 3. 已安裝的 skills / templates / manifest ------------------------------
printf '[3/4] 已安裝的 skills、templates、manifest\n'
if [ ! -d "$SKILLS_DIR" ]; then
    bad "找不到已安裝的 skills 目錄：$SKILLS_DIR（請先跑 install）"
else
    normalized="$(pm_render_path "$SKILLS_DIR")"
    for name in "${PM_TARGETS[@]}"; do
        r="${RENDERED[$name]:-}"
        [ -n "$r" ] || continue
        if [ "$r" = "$normalized" ]; then ok "[$name] preset 指向的目錄與實際安裝位置一致"
        else bad "[$name] preset 指向 $r，實際在 $normalized"; fi
    done
    n=0
    for dir in "$SKILLS_DIR"/*/; do
        [ -d "$dir" ] || continue
        n=$((n + 1))
        sname="$(basename "$dir")"
        file="$dir/SKILL.md"
        if [ ! -f "$file" ]; then bad "$sname：缺少 SKILL.md"; continue; fi
        chars="$(wc -c < "$file" | tr -d ' ')"
        problems=""
        grep -qE "^name:[[:space:]]*$sname[[:space:]]*$" "$file" || problems="$problems frontmatter-name不符"
        grep -qE '^description:[[:space:]]*[^[:space:]]' "$file" || problems="$problems 缺description"
        case "$sname" in *[!a-z0-9-]*) problems="$problems 非kebab-case" ;; esac
        [ "$chars" -le 8000 ] || problems="$problems 長度 $chars 超過 8000"
        if [ -z "$problems" ]; then ok "$sname（$chars 位元組）"; else bad "$sname：$problems"; fi
    done
    [ "$n" -gt 0 ] || bad "skills 目錄是空的：$SKILLS_DIR"
fi
if [ -f "$TEMPLATES_DIR/project/README.md" ]; then ok "templates 已安裝：$TEMPLATES_DIR"
else warn "找不到已安裝的 templates（$TEMPLATES_DIR）；PM 開新專案時會改用手動結構（見 pm-scaffold skill）"; fi
if [ -f "$MANIFEST" ]; then ok "manifest 存在：$MANIFEST"; else warn "找不到 manifest：$MANIFEST"; fi

# --- 4. dump diff（逐 profile）----------------------------------------------
printf '[4/4] dump-config 差異（逐 profile）\n'
for name in "${PM_TARGETS[@]}"; do
    printf '  --- %s ---\n' "$name"
    BASELINE="$ARTIFACTS/dump-baseline-$name.txt"
    BASELINE_HOME=""
    [ -f "$ARTIFACTS/dump-baseline-$name.home" ] && BASELINE_HOME="$(cat "$ARTIFACTS/dump-baseline-$name.home")"
    AFTER="$ARTIFACTS/dump-after-$name.txt"

    if [ ! -f "$BASELINE" ]; then
        warn "沒有 $name 的 baseline；請在安裝前先跑 verify.sh -Snapshot。仍會存下本次 dump。"
        dump_config "$name" "$AFTER" || true
        continue
    fi
    if [ -n "$BASELINE_HOME" ] && [ "$BASELINE_HOME" != "$DSH_HOME_FOR_DSH" ]; then
        warn "baseline 是針對 $BASELINE_HOME 取的，與目前 $DSH_HOME_FOR_DSH 不同；跳過比對（仍會存下本次 dump）"
        dump_config "$name" "$AFTER" || true
        continue
    fi
    if ! dump_config "$name" "$AFTER"; then continue; fi

    # 基準檔可能是別的平台／別的腳本寫的（BOM、CRLF 不同），先正規化再比對
    tr -d '\357\273\277\r' < "$BASELINE" > "$ARTIFACTS/.baseline.lf"
    tr -d '\357\273\277\r' < "$AFTER" > "$ARTIFACTS/.after.lf"
    added="$(diff "$ARTIFACTS/.baseline.lf" "$ARTIFACTS/.after.lf" | grep -c '^>' || true)"
    removed="$(diff "$ARTIFACTS/.baseline.lf" "$ARTIFACTS/.after.lf" | grep -c '^<' || true)"
    printf '    新增 %s 行、移除 %s 行\n' "$added" "$removed"
    if [ "$removed" -gt 0 ]; then
        printf '    --- 移除（前 12 行）---\n'
        diff "$ARTIFACTS/.baseline.lf" "$ARTIFACTS/.after.lf" | grep '^<' | head -n 12 | sed 's/^/     /'
        bad "[$name] 有 $removed 行被移除，請檢查是否影響其他 preset"
    else
        ok "[$name] 沒有任何既有行被移除（無回歸）"
    fi
done

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
    printf '全部檢查通過。\n'
    exit 0
fi
printf '有 %s 項失敗。\n' "$FAILURES"
exit 1
