# dsh-pm-mode — 給 agent 的安裝／移除指南

這個 repo 是一個 **DSH agent preset**（模式 id `pm`，顯示名稱「DSH PM 模式」）。
使用者通常不懂技術，會說「照 README 幫我裝起來」。你的工作就是照下面做完並回報，**不要問他技術問題**。

## 你要做的事（順序固定）

1. **前檢**（缺一項就停下來白話回報，不要硬做）
   - DSH home：`$DSH_HOME`，沒設就是 `~/.dsh`。
   - 該 home 底下要有一個含 `cordis.patch.yml` 的 profile（通常是 `web`）。
2. **安裝**（依你所在平台挑一個）
   - Windows：`powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1`
   - macOS / Linux：`bash scripts/install.sh`
   - 需要指定時：Windows 用 `-DshHome DIR -Profile NAME`；其他用 `--dsh-home DIR --profile NAME`。
3. **驗證**：跑同目錄的 verify（Windows `verify.ps1`，其他 `verify.sh`）。
   必須看到「**全部檢查通過**」，且 dump 差異是「**移除 0 行**」。
4. **回報使用者（白話三句）**：裝好了什麼／怎麼證明沒動到別的東西／請他**完整重啟 DSH** 再開**新 session** 選「DSH PM 模式」。

## 禁止

- 不要改 `agent-preset-registry` 的 `default`，也不要改其他 preset 的行。
- 不要整檔覆寫或刪除 `cordis.patch.yml`；只能透過安裝腳本的 marker 區塊。
- 不要為了讓驗證通過而改 `scripts/verify.*` 或放寬檢查。
- 不要安裝任何額外的 npm 套件或插件。

## 出錯時

- 安裝前一定備份成 `cordis.patch.yml.bak-pm-<時間>`；要還原就把它複製回 `cordis.patch.yml`。
- 移除：`.\scripts\uninstall.ps1` 或 `bash scripts/uninstall.sh`（一樣先備份）。
- 原理、限制與已知坑：`開發文件.md`、`docs/安裝與驗證.md`。

## 檔案地圖

| 路徑 | 用途 |
|---|---|
| `presets/pm-preset.patch.yml` | 模式定義唯一真源（persona ＋ 工具名冊） |
| `skills/pm-*/SKILL.md` | PM 的六份工作流程；安裝時會複製到 `<DSH_HOME>/pm-mode/skills` |
| `templates/project/` | PM 開新專案時複製的骨架 |
| `scripts/` | install / uninstall / verify（PowerShell 與 bash 各一份，行為一致） |

> 寫入範圍：只在 `<DSH_HOME>/profiles/<profile>/cordis.patch.yml` 的 marker 區塊，以及 `<DSH_HOME>/pm-mode/`。
