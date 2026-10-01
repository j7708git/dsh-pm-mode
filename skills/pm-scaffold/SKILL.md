---
name: pm-scaffold
description: 專案骨架與 git 初始化。需求規格已獲使用者確認後使用：建立專案資料夾、複製骨架樣板、git init 並完成第一個存檔，讓後續每一步都有版控可回溯。
whenToUse: 使用者已確認需求規格，準備開始新專案時。
---

# pm-scaffold — 專案骨架與 git 初始化

## 鐵則
1. 只在 `docs/01-需求規格.md` 狀態為「已確認」時執行。
2. **動工前先確認目標資料夾不存在或使用者同意沿用**，不要覆蓋既有專案。
3. 第一個 commit 之前必須先看過 `git status`，確認沒有金鑰、沒有大檔、沒有暫存垃圾。

## 步驟

### 1. 決定專案位置與名稱
- 位置：**目前 DSH 工作區**底下一個新資料夾（用 `pwd` 查工作區根目錄；不要寫死路徑）。
- 名稱：白話可、但避免空白與 `\ / : * ? " < > |`；建議 kebab-case（例：`expense-tracker`）。
- 若同名資料夾已存在 → 用 `ask_user_question` 問：改名（推薦）／沿用既有資料夾／取消。

### 2. 建立骨架
優先複製已安裝的樣板。安裝時已把樣板複製到 `<DSH_HOME>/pm-mode/templates/project`
（實際路徑看 `<DSH_HOME>/pm-mode/install.json` 的 `templatesDir`）：

```powershell
$workspace = (Get-Location).Path                  # 目前 session 的工作區
$src = '<DSH_HOME>\pm-mode\templates\project'     # 找不到就看 install.json
$dst = Join-Path $workspace '<專案名>'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Recurse -Force -Path (Join-Path $src '*') -Destination $dst
```

macOS / Linux 用等價指令（`cp -R "$src"/. "$dst"/`）。

若找不到樣板（例如舊版安裝或已手動刪除），就手動建立等價結構：

```
<專案名>/
├─ README.md            小白版：這是什麼、怎麼用、目前狀態
├─ AGENTS.md            專案規則（語言／風格／測試／commit 規範）
├─ CHANGELOG.md
├─ .gitignore
├─ docs/01-需求規格.md  02-技術研究.md  03-開發計畫.md  04-進度日誌.md  05-驗收報告.md
├─ src/
├─ tests/
└─ tasks/
```

### 3. 改寫佔位內容
把 `README.md`、`AGENTS.md`、`docs/01-需求規格.md` 裡的 `<專案名>`、`<日期>` 換成真實值；
`docs/01-需求規格.md` 用 `pm-intake` 產出的內容覆蓋。

### 4. git 初始化
```powershell
cd '<專案路徑>'      # 上一步建立的那個資料夾
git init -b main
```
若 `git init -b` 失敗（舊版 git）：
```powershell
git init
git symbolic-ref HEAD refs/heads/main
```

### 5. 第一個 commit
```powershell
git add -A
git status --short
git commit -m "M0: 建立專案骨架與需求規格"
```

### 6. `.gitignore` 最低要求
`.env`、`*.key`、`*.pem`、`credentials*`、`node_modules/`、`.venv/`、`__pycache__/`、`dist/`、`.artifacts/`。
**金鑰一律不進版控**：需要金鑰時改用環境變數或 `~/.dsh/.credentials.yaml`，並在 `README.md` 說明。

### 7. 回報使用者（三句白話）
已完成：建立了專案資料夾與第一個存檔版本；
證據：`git log --oneline -1` 的輸出；
下一步：開始做研究／直接進規劃。

## 完成檢核
- [ ] 專案資料夾存在，骨架檔齊備
- [ ] `git log --oneline` 至少有 1 個 commit（`M0: …`）
- [ ] `.gitignore` 已包含金鑰與產物類檔案
- [ ] `README.md` 已改寫成這個專案的白話說明（不是樣板文字）
- [ ] 使用者知道專案在哪個資料夾

## 常見錯誤
- ❌ 專案直接建在工作區根目錄 → 每個專案一個資料夾，根目錄只放 `IDEA.md` 與各專案。
- ❌ 忘了 `.gitignore` 就 `git add -A` → 可能把暫存檔或金鑰存進去。
- ❌ 一開始就建 `feat/xxx` 分支 → 單人專案先用 `main`，需要時再分支。
