# DSH PM 模式（dsh-pm-mode）

一個給「不懂技術的使用者」用的 DSH 模式。選用後，agent 會變成你的專屬**專案經理（PM）**：
你用白話說想要什麼，PM 負責訪談需求、寫規格、做版控、派研究與開發的 subagent、驗收、回報進度。

- 模式 id：`pm`；顯示名稱：**DSH PM 模式**
- 跨機器可安裝：Windows / macOS / Linux 都能裝；DSH home 與 profile 會自動偵測
- 安裝後**這個資料夾可以移動或刪除**，模式照樣運作（技能會複製到 `<DSH_HOME>/pm-mode/`）
- 不需要網路、不需要額外套件（PowerShell 或 bash；有 node 會多做一項 YAML 檢查）

---

## 一、這個模式會幫你做什麼

| 階段 | PM 做什麼 | 你看得到什麼 |
|---|---|---|
| 1 需求訪談 | 用白話問你最多 3 個問題，每題都附建議 | 對話 |
| 2 寫規格 | 寫成 `docs/01-需求規格.md`，請你確認（**沒確認不動工**） | 一份你讀得懂的文件 |
| 3 開專案＋版控 | 建資料夾、`git init`、第一次存檔 | 專案資料夾 |
| 4 研究 | 派 subagent 上網查證、比較方案、找可用 skill／插件 | `docs/02-技術研究.md` |
| 5 計畫 | 切成里程碑與任務卡 | `docs/03-開發計畫.md` |
| 6 開發 | 派 subagent 實作，PM 監督 | 程式碼 |
| 7 驗收 | PM 親自讀 diff、跑測試（不採信 subagent 自述） | 驗證證據 |
| 8 存檔 | `git commit` ＋ `git tag m1` | 版控紀錄（GUI 可看 git 圖） |
| 9 回報 | 白話三句：做完什麼／怎麼證明／下一步 | 對話＋`docs/04-進度日誌.md` |

專案會建立在目前 DSH workspace 底下一個新資料夾（例如 `<你的工作區>\<專案名>\`）。

---

## 二、安裝

### 方法 A：叫 agent 幫你裝（推薦）

把這個資料夾複製到新電腦，用 DSH 在這個資料夾開一個 session，然後說：

```
請讀 README 並幫我安裝 dsh-pm-mode
```

agent 會照下面的步驟做，並且要回報「全部檢查通過」。

### 方法 B：自己跑（兩行）

Windows（PowerShell）：
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

macOS / Linux：
```bash
bash scripts/install.sh
bash scripts/verify.sh
```

> 想先留基準（之後才能證明「沒有動到別的東西」）：安裝**前**先跑一次 `verify.ps1 -Snapshot`（bash：`verify.sh -Snapshot`）。
> 想指定路徑：Windows `-DshHome DIR -Profile NAME`；其他 `--dsh-home DIR --profile NAME`。

### 安裝做了什麼（只動這些地方）

1. 把 `skills/` 複製到 `<DSH_HOME>/pm-mode/skills/`（`<DSH_HOME>` 預設 `~/.dsh`）。
2. 寫一份安裝紀錄 `<DSH_HOME>/pm-mode/install.json`。
3. 在 `<DSH_HOME>/profiles/<profile>/cordis.patch.yml` 尾端插入一段 **marker 區塊**
   （`# >>> dsh-pm-mode:begin` … `# <<< dsh-pm-mode:end`），內容＝`presets/pm-preset.patch.yml` 渲染後原文。
   - 插入前一定備份成 `cordis.patch.yml.bak-pm-<時間>`。
   - 可重複執行（第二次是「更新既有區塊」，不會重複插入）。
4. **不會**改其他 preset、不會改 `agent-preset-registry` 的預設模式、不會改 DSH 安裝本體。

### 最後一步要你自己做

**完整關閉並重啟 DSH**（preset 宣告在啟動時載入；先試開新 session 也可能直接生效），
然後開一個**新的空白 session**，在預設選擇器選「**DSH PM 模式**」。
選用該 session 前，請把權限設成 **danger-full-access**：PM 需要跑 `git` 等指令，而 `workspace-write` 沙箱在部分機器（含 Windows 的 ACL 授權失敗）會讓 shell 完全無法執行。

### 怎麼把這個資料夾帶到新電腦

- 複製整個 `dsh-pm-mode` 資料夾即可（含 `.git` 就順便有版控）。用 `git clone` 也一樣。
- 資料夾放哪都行；安裝後就算刪掉，模式還是能用（技能已在 `<DSH_HOME>/pm-mode/`）。
- 版本升級＝覆蓋資料夾後**再跑一次安裝**（會更新既有區塊與技能）。

---

## 三、怎麼用

新 session 選「DSH PM 模式」，直接用白話講你要什麼：

> 我想要一個可以記錄每天花費的小工具，能看一個月總共花多少。

PM 會開始訪談。你只要回答問題、在「規格確認」時說「可以」，其他交給它。

---

## 四、出問題怎麼回復

| 狀況 | 處理 |
|---|---|
| 重啟後 DSH 開不起來 | 還原備份：把 `<DSH_HOME>/profiles/<profile>/cordis.patch.yml.bak-pm-<時間>` 複製回 `cordis.patch.yml`，再重啟 |
| 選擇器裡沒有「DSH PM 模式」 | 先跑 `verify`（應為「全部檢查通過」），再確認是**完整重啟**而不是只重整瀏覽器頁面 |
| 模式在，但 `pm-*` skill 沒出現 | 重跑安裝（會重新複製技能）；再跑 `verify` 看 skill 檢查那一節 |
| 想完全移除 | Windows `.\scripts\uninstall.ps1`／其他 `bash scripts/uninstall.sh`，再重啟 |
| 不知道裝到哪 | 看 `<DSH_HOME>/pm-mode/install.json` |

---

## 五、這個 repo 裡有什麼

| 路徑 | 用途 |
|---|---|
| `AGENTS.md` | 給 agent 的安裝／移除指南（開這個資料夾的 agent 會自動讀到） |
| `presets/pm-preset.patch.yml` | ★模式定義唯一真源（persona＋工具名冊） |
| `skills/pm-*/SKILL.md` | PM 的六份工作流程（訪談／開專案／研究／規劃／派工／收尾） |
| `templates/project/` | PM 開新專案時複製的骨架檔 |
| `scripts/install.ps1`、`install.sh` | 安裝（冪等、備份、marker 區塊） |
| `scripts/uninstall.ps1`、`uninstall.sh` | 移除（只刪自己裝的東西） |
| `scripts/verify.ps1`、`verify.sh` | 驗證（YAML、防呆、skill、dump 差異） |
| `scripts/lib-pm-mode.sh` | bash 三支腳本共用的函式 |
| `scripts/check-yaml.mjs` | 用 profile 內建 `yaml` 套件做結構檢查（找不到就跳過） |
| `docs/安裝與驗證.md` | 逐步安裝與驗收紀錄 |
| `docs/驗收報告.md` | 驗收項目的結果 |
| `開發文件.md` | 設計決策、DSH 機制事實、風險與防呆 |

## 六、授權

本 repo 目前**未附授權檔**，預設為「保留所有權利」：你可以自由檢視與自行使用，但轉載、再散布或改作請先詢問作者。
`presets/pm-preset.patch.yml` 的名冊與部分內容改寫自 DeepSeek Harness 內建的 `standard`／`cordis` preset（MIT 授權），
該部分依原始 MIT 條款。若你希望別人能自由取用，加一個 `LICENSE`（MIT）即可。
