#!/usr/bin/env bash
# dsh-pm-mode 移除腳本（macOS / Linux，含 Windows 的 Git Bash）。可重複執行。
#
#   1. 從每個 <DSH_HOME>/profiles/<profile>/cordis.patch.yml 移除 marker 區塊（先備份），
#      其他使用者內容一律保留；可用 --profile 只處理一個。
#   2. 刪除安裝時複製的 <DSH_HOME>/pm-mode（skills、templates 與 manifest）。
#   使用者自己的 skill（例如 ~/.dsh/skills/ 下的其他項目）一律不動。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-pm-mode.sh
. "$SCRIPT_DIR/lib-pm-mode.sh"

pm_parse_args "$@"

printf '== dsh-pm-mode 移除 ==\n'
printf 'DSH home  : %s\n' "$DSH_HOME"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -n "${PROFILE:-}" ]; then
    PM_TARGETS=("$PROFILE")
    [ -f "$DSH_HOME/profiles/$PROFILE/cordis.patch.yml" ] || { printf '找不到 profile %s\n' "$PROFILE" >&2; exit 1; }
else
    PM_TARGETS=()
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        PM_TARGETS+=("$name")
    done <<EOF
$(pm_all_profiles)
EOF
fi

removed_any=0
for name in "${PM_TARGETS[@]}"; do
    PATCH="$DSH_HOME/profiles/$name/cordis.patch.yml"
    [ -f "$PATCH" ] || continue
    if grep -q -- "$PM_BEGIN" "$PATCH" 2>/dev/null; then
        BACKUP="$(pm_backup "$PATCH")"
        crlf=0
        pm_file_has_crlf "$PATCH" && crlf=1
        pm_strip_block_lf "$PATCH" "$WORK/base.lf"
        pm_write_with_eol "$WORK/base.lf" "$PATCH" "$crlf"
        printf '已移除區塊：%s（備份：%s）\n' "$PATCH" "$BACKUP"
        removed_any=1
    fi
done
[ "$removed_any" = "1" ] || printf '找不到任何 dsh-pm-mode 區塊，patch 檔未變更。\n'

# --- 模式自己的資料夾 -------------------------------------------------------
MODE_DIR="$DSH_HOME/pm-mode"
case "$MODE_DIR" in
    */pm-mode) ;;
    *) printf '拒絕刪除非預期路徑：%s\n' "$MODE_DIR" >&2; exit 1 ;;
esac
if [ -d "$MODE_DIR" ]; then
    rm -rf "$MODE_DIR"
    printf '已刪除    : %s\n' "$MODE_DIR"
else
    printf '找不到    : %s（可能已移除）\n' "$MODE_DIR"
fi

printf '\n下一步：完整重啟 DSH，「DSH PM 模式」即從選擇器消失。\n'
