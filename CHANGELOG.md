# CHANGELOG

## v1.3 — 2026-10-02

- **修正「裝了卻看不到」**：DSH 桌面版用的是 `desktop` profile，不是 `web`；v1.2 只裝 `web`，所以重啟後選擇器裡沒有 PM 模式。
- 安裝器改為**預設安裝到所有支援 agent preset 的 profile**（`desktop`、`web`…；`headless` 這種沒有 web-app bundle 的會自動略過），
  `-Profile`／`--profile` 可只裝一個；`uninstall` 與 `verify` 同步變成逐 profile 處理。
- `verify` 的 dump 比對改為**逐 profile 的 baseline**（`dump-baseline-<profile>.txt`）。
- 已知限制寫入文件：`desktop` profile 由 Electron app 專屬管理，`dsh --dump-config` 無法 compose 它
  （回 `profile "desktop" is managed exclusively by the Electron application`），
  因此該 profile 的實機驗證只能靠「重啟後開新 session 看選擇器」。

## v1.2 — 2026-10-02

- **安裝時一併複製 `templates/`** 到 `<DSH_HOME>/pm-mode/templates/`（PM 開新專案用），
  安裝後原 repo 完全可刪；manifest 增列 `templatesDir`；`verify` 增加 templates 檢查。
- **去除機器專屬路徑**：文件與 skill 改用 `<DSH_HOME>`／`<repo>`／`<專案路徑>` 佔位符，
  公開分享不會洩漏本機使用者名稱或工作區路徑；`pm-scaffold` 改為從已安裝的樣板複製，
  並提示用 `pwd` 取得目前工作區（原本寫死 Windows 路徑，換機器會壞）。

## v1.1 — 2026-10-02

- **跨機器可安裝**：新增 bash 版 `install.sh` / `uninstall.sh` / `verify.sh` 與共用函式庫 `lib-pm-mode.sh`
  （macOS / Linux，含 Windows 的 Git Bash；自動處理 MSYS→Windows 路徑與 CRLF 保留）。
- **安裝後 repo 可移動／刪除**：技能改為安裝時複製到 `<DSH_HOME>/pm-mode/skills/`，preset 指向該處，
  並寫入 `<DSH_HOME>/pm-mode/install.json` manifest；移除時整個資料夾刪除。
- **自動偵測**：DSH home（`$DSH_HOME` → `~/.dsh`）與 profile（預設 `web`，找不到時採唯一可用者，多個則報錯列出）。
- **agent 入口**：新增根目錄 `AGENTS.md`（安裝／移除 runbook），README 亦內含同一份 runbook。
- **驗證強化**：baseline 旁記錄 DSH home（home 不同只警告不比對）；技能長度改以位元組計；找不到 `dsh`/`node` 時優雅降級。
- 修正：preset 檔頭註解不再被佔位符取代（安裝後區塊文字正確）。

## v1.0 — 2026-10-01

- 新增 agent preset `pm`（顯示名稱：**DSH PM 模式**，order 5），以官方 `preset-standard` 名冊為基底，
  改動三處：PM persona、`skill-filesystem.customSkillDirs`、啟用 `tool-plugin-manager`。
- 新增六份工作流程 skill：`pm-intake`、`pm-scaffold`、`pm-research`、`pm-plan`、`pm-delegate`、`pm-handoff`。
- 新增 `templates/project/` 專案骨架樣板。
- 新增 `scripts/install.ps1`（冪等、備份、marker 區塊）、`scripts/uninstall.ps1`、`scripts/verify.ps1`。
- 新增 `README.md`、`開發文件.md`、`docs/安裝與驗證.md`。
