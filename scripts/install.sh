#!/usr/bin/env bash
# dsh-pm-mode 安裝腳本（macOS / Linux，含 Windows 的 Git Bash）。
# 可重複執行；安裝後原 repo 可移動或刪除。
#
#   1. 自動找 DSH home（$DSH_HOME，否則 ~/.dsh），並對**所有支援 agent preset 的 profile**安裝
#      （desktop / web / …），可用 --profile 只裝一個。
#   2. 把 skills/ 與 templates/ 複製到 <DSH_HOME>/pm-mode/ 並寫入 manifest。
#   3. 把 presets/pm-preset.patch.yml 的 {{PM_SKILLS_DIR}} 換成該路徑，
#      冪等地寫進每個 <DSH_HOME>/profiles/<profile>/cordis.patch.yml 的 marker 區塊（先備份）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-pm-mode.sh
. "$SCRIPT_DIR/lib-pm-mode.sh"

pm_parse_args "$@"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_ROOT/presets/pm-preset.patch.yml"
SRC_SKILLS="$REPO_ROOT/skills"
SRC_TEMPLATES="$REPO_ROOT/templates"

printf '== dsh-pm-mode 安裝（v%s）==\n' "$PM_VERSION"
printf 'repo      : %s\n' "$REPO_ROOT"
printf 'DSH home  : %s\n' "$DSH_HOME"

[ -f "$SRC" ] || { printf '找不到來源檔：%s\n' "$SRC" >&2; exit 1; }
[ -d "$SRC_SKILLS" ] || { printf '找不到 skills 目錄：%s\n' "$SRC_SKILLS" >&2; exit 1; }

pm_resolve_targets
printf 'profiles  : %s\n' "${PM_TARGETS[*]}"

# --- 1. 複製 skills 到 DSH home --------------------------------------------
MODE_DIR="$DSH_HOME/pm-mode"
SKILLS_DST="$MODE_DIR/skills"
case "$SKILLS_DST" in
    */pm-mode/skills) ;;
    *) printf '拒絕非預期路徑：%s\n' "$SKILLS_DST" >&2; exit 1 ;;
esac

rm -rf "$SKILLS_DST"
mkdir -p "$SKILLS_DST"
cp -R "$SRC_SKILLS"/. "$SKILLS_DST"/

skill_names="$(cd "$SKILLS_DST" && ls -1 | grep -v '^\.' | tr '\n' ' ' | sed 's/ $//')"
skill_count="$(cd "$SKILLS_DST" && ls -1 | grep -vc '^\.' || true)"
printf 'skills    : %s 個 → %s\n' "$skill_count" "$SKILLS_DST"
printf '            %s\n' "$skill_names"

SKILLS_RENDERED="$(pm_render_path "$SKILLS_DST")"

# --- 2. 複製 templates（PM 開新專案用；複製後 repo 可刪）--------------------
TEMPLATES_DST="$MODE_DIR/templates"
if [ -d "$SRC_TEMPLATES" ]; then
    case "$TEMPLATES_DST" in
        */pm-mode/templates) ;;
        *) printf '拒絕非預期路徑：%s\n' "$TEMPLATES_DST" >&2; exit 1 ;;
    esac
    rm -rf "$TEMPLATES_DST"
    mkdir -p "$TEMPLATES_DST"
    cp -R "$SRC_TEMPLATES"/. "$TEMPLATES_DST"/
    printf 'templates : → %s\n' "$TEMPLATES_DST"
    TEMPLATES_RENDERED="$(pm_render_path "$TEMPLATES_DST")"
else
    printf 'templates : （repo 沒有 templates/，跳過）\n'
    TEMPLATES_RENDERED=""
fi

# --- 3. manifest ------------------------------------------------------------
dsh_version="$(dsh --version 2>/dev/null | tr -d '\r' | head -n 1 || true)"
{
    printf '{\n'
    printf '  "name": "dsh-pm-mode",\n'
    printf '  "version": "%s",\n' "$PM_VERSION"
    printf '  "installedAt": "%s",\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '  "dshHome": "%s",\n' "$DSH_HOME"
    printf '  "profiles": [%s],\n' "$(printf '"%s",' "${PM_TARGETS[@]}" | sed 's/,$//')"
    printf '  "skillsDir": "%s",\n' "$SKILLS_RENDERED"
    printf '  "skills": [%s],\n' "$(printf '"%s",' $skill_names | sed 's/,$//')"
    printf '  "templatesDir": "%s",\n' "$TEMPLATES_RENDERED"
    printf '  "repoRoot": "%s",\n' "$REPO_ROOT"
    printf '  "dshVersion": "%s"\n' "$dsh_version"
    printf '}\n'
} > "$MODE_DIR/install.json"
printf 'manifest  : %s\n' "$MODE_DIR/install.json"

# --- 4. 寫入每個 profile 的 patch 區塊 --------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pm_render_block_lf "$SRC" "$SKILLS_RENDERED" "$WORK/block.lf"

FAILED=0
for name in "${PM_TARGETS[@]}"; do
    PATCH="$DSH_HOME/profiles/$name/cordis.patch.yml"
    printf '\n[%s] %s\n' "$name" "$PATCH"

    BACKUP="$(pm_backup "$PATCH")"
    printf '  已備份    : %s\n' "$BACKUP"

    crlf=0
    pm_file_has_crlf "$PATCH" && crlf=1

    pm_strip_block_lf "$PATCH" "$WORK/base.lf"
    cat "$WORK/base.lf" "$WORK/block.lf" > "$WORK/new.lf"

    counts="$(pm_counts "$WORK/new.lf")"
    printf '  %s\n' "$counts"
    begin_n="$(printf '%s' "$counts" | sed -n 's/.*begin=\([0-9]*\).*/\1/p')"
    pm_n="$(printf '%s' "$counts" | sed -n 's/.*pm_ids=\([0-9]*\).*/\1/p')"
    if [ "$begin_n" != "1" ] || [ "$pm_n" != "1" ]; then
        printf '  防呆失敗（marker 或 preset id 數量異常）。此 profile 未寫入；備份於 %s\n' "$BACKUP" >&2
        FAILED=$((FAILED + 1))
        continue
    fi

    pm_write_with_eol "$WORK/new.lf" "$PATCH" "$crlf"
    printf '  已寫入    : %s\n' "$PATCH"
done

# --- 5. 下一步 --------------------------------------------------------------
printf '\n下一步：\n'
printf '  1) 驗證： bash %s/verify.sh\n' "$SCRIPT_DIR"
printf '  2) 完整重啟 DSH（preset 宣告在啟動時載入）\n'
printf '  3) 開新 session，在預設選擇器選「DSH PM 模式」\n'
if [ "$FAILED" -gt 0 ]; then
    printf '\n有 %s 個 profile 寫入失敗，請看上面的訊息。\n' "$FAILED"
    exit 1
fi
