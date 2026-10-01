<#
.SYNOPSIS
    dsh-pm-mode 安裝腳本（Windows）。可重複執行，安裝後原 repo 可移動或刪除。

.DESCRIPTION
    1. 自動找出 DSH home（$env:DSH_HOME，否則 ~/.dsh）與 profile（預設 web，找不到就自動挑唯一可用者）。
    2. 把 skills/ 複製到 <DSH_HOME>/pm-mode/skills，並寫入 manifest。
    3. 把 presets/pm-preset.patch.yml 的 {{PM_SKILLS_DIR}} 換成上面那個路徑，
       冪等地寫進 <DSH_HOME>/profiles/<profile>/cordis.patch.yml 的 marker 區塊（先備份）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
.EXAMPLE
    .\scripts\install.ps1 -DshHome 'D:\dsh-home' -Profile web
#>
[CmdletBinding()]
param(
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),
    [string]$Profile = 'web'
)

$ErrorActionPreference = 'Stop'

$begin = '# >>> dsh-pm-mode:begin'
$end   = '# <<< dsh-pm-mode:end'
$version = '1.2'

$repoRoot  = Split-Path -Parent $PSScriptRoot
$source    = Join-Path $repoRoot 'presets\pm-preset.patch.yml'
$srcSkills = Join-Path $repoRoot 'skills'

Write-Host "== dsh-pm-mode 安裝（v$version）=="
Write-Host "repo      : $repoRoot"
Write-Host "DSH home  : $DshHome"

if (-not (Test-Path -LiteralPath $source))    { throw "找不到來源檔：$source" }
if (-not (Test-Path -LiteralPath $srcSkills)) { throw "找不到 skills 目錄：$srcSkills" }
if (-not (Test-Path -LiteralPath $DshHome))   { throw "找不到 DSH home：$DshHome（DSH 裝好了嗎？或用 -DshHome 指定）" }

# --- 1. 解析 profile --------------------------------------------------------
$profilesRoot = Join-Path $DshHome 'profiles'
$candidates = @(
    Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'cordis.patch.yml') }
)
$exact = @($candidates | Where-Object { $_.Name -eq $Profile })
if ($exact.Count -eq 1) {
    $Profile = $exact[0].Name
} elseif ($candidates.Count -eq 1) {
    Write-Host "找不到 profile '$Profile'，自動改用唯一的 '$($candidates[0].Name)'"
    $Profile = $candidates[0].Name
} elseif ($candidates.Count -eq 0) {
    throw "在 $profilesRoot 找不到任何含 cordis.patch.yml 的 profile"
} else {
    throw "找不到 profile '$Profile'；可選：$($candidates.Name -join ', ')。請用 -Profile 指定。"
}

$patchPath = Join-Path $profilesRoot (Join-Path $Profile 'cordis.patch.yml')
Write-Host "profile   : $Profile"
Write-Host "patch 檔  : $patchPath"

# --- 2. 複製 skills 到 DSH home（安裝後 repo 可刪）--------------------------
$modeDir   = Join-Path $DshHome 'pm-mode'
$skillsDst = Join-Path $modeDir 'skills'

if (Test-Path -LiteralPath $skillsDst) {
    if ($skillsDst -notmatch 'pm-mode[\\/]skills$') { throw "拒絕刪除非預期路徑：$skillsDst" }
    Remove-Item -LiteralPath $skillsDst -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $skillsDst | Out-Null
Copy-Item -Path (Join-Path $srcSkills '*') -Destination $skillsDst -Recurse -Force

$skillNames = @(Get-ChildItem -LiteralPath $skillsDst -Directory | Select-Object -ExpandProperty Name)
Write-Host "skills    : $($skillNames.Count) 個 → $skillsDst"
Write-Host "            $($skillNames -join ', ')"

$skillsFwd = $skillsDst -replace '\\', '/'

# --- 2b. 複製 templates（PM 開新專案用；複製後 repo 可刪）--------------------
$srcTemplates = Join-Path $repoRoot 'templates'
$templatesDst = Join-Path $modeDir 'templates'
if (Test-Path -LiteralPath $srcTemplates) {
    if (Test-Path -LiteralPath $templatesDst) {
        if ($templatesDst -notmatch 'pm-mode[\\/]templates$') { throw "拒絕刪除非預期路徑：$templatesDst" }
        Remove-Item -LiteralPath $templatesDst -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $templatesDst | Out-Null
    Copy-Item -Path (Join-Path $srcTemplates '*') -Destination $templatesDst -Recurse -Force
    Write-Host "templates : → $templatesDst"
} else {
    Write-Host "templates : （repo 沒有 templates/，跳過）"
}

# --- 3. manifest ------------------------------------------------------------
$dshVersion = ''
$dshCmd = Get-Command dsh -ErrorAction SilentlyContinue
if ($dshCmd) {
    try { $dshVersion = (& dsh --version 2>&1 | Out-String).Trim() } catch { $dshVersion = '' }
}
$manifest = [ordered]@{
    name         = 'dsh-pm-mode'
    version      = $version
    installedAt  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    dshHome      = $DshHome
    profile      = $Profile
    skillsDir    = $skillsFwd
    skills       = $skillNames
    templatesDir = if (Test-Path -LiteralPath $templatesDst) { $templatesDst -replace '\\', '/' } else { '' }
    repoRoot     = $repoRoot
    dshVersion   = $dshVersion
}
$manifestPath = Join-Path $modeDir 'install.json'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4), $utf8NoBom)
Write-Host "manifest  : $manifestPath"

# --- 4. 渲染 preset 區塊 ----------------------------------------------------
$blockText = [System.IO.File]::ReadAllText($source)
$blockText = $blockText -replace '\{\{PM_SKILLS_DIR\}\}', $skillsFwd
$blockText = $blockText.TrimEnd()

$raw = [System.IO.File]::ReadAllText($patchPath)
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$patchPath.bak-pm-$stamp"
Copy-Item -LiteralPath $patchPath -Destination $backup -Force
Write-Host "已備份    : $backup"

$nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
$blockText = ($blockText -replace "`r?`n", $nl)
$managedText = $begin + $nl + $blockText + $nl + $end

$pattern = '(?ms)^' + [regex]::Escape($begin) + '.*?^' + [regex]::Escape($end) + '\r?\n?'
$hadBlock = [regex]::IsMatch($raw, $pattern)
$stripped = if ($hadBlock) { [regex]::Replace($raw, $pattern, '') } else { $raw }
if ($stripped -notmatch "\r?\n$") { $stripped += $nl }
if ($stripped.Trim() -eq '') { $stripped = '' }

$new = $stripped + $managedText + $nl

# --- 5. 防呆 ----------------------------------------------------------------
$pmIds = ([regex]::Matches($new, '(?m)^\s*id:\s*pm\s*$')).Count
if ($pmIds -ne 1) {
    throw "偵測到 $pmIds 個 'id: pm' 宣告（應為 1）。已中止且未寫入；原檔備份於 $backup"
}
$beginCount = ([regex]::Matches($new, [regex]::Escape($begin))).Count
$endCount   = ([regex]::Matches($new, [regex]::Escape($end))).Count
if ($beginCount -ne 1 -or $endCount -ne 1) {
    throw "marker 數量異常（begin=$beginCount, end=$endCount）。已中止且未寫入；原檔備份於 $backup"
}

[System.IO.File]::WriteAllText($patchPath, $new, $utf8NoBom)
$action = if ($hadBlock) { '已更新既有區塊' } else { '已追加新區塊' }
Write-Host "$action（marker 1 組）"

# --- 6. 下一步 --------------------------------------------------------------
Write-Host ''
Write-Host '下一步：'
Write-Host '  1) 驗證： powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1'
Write-Host '  2) 完整重啟 DSH（preset 宣告在啟動時載入）'
Write-Host '  3) 開新 session，在預設選擇器選「DSH PM 模式」'
Write-Host ''
Write-Host "要還原： Copy-Item '$backup' '$patchPath' -Force"
