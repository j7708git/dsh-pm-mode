<#
.SYNOPSIS
    dsh-pm-mode 安裝腳本（Windows）。可重複執行，安裝後原 repo 可移動或刪除。

.DESCRIPTION
    1. 自動找出 DSH home（$env:DSH_HOME，否則 ~/.dsh），並對**所有支援 agent preset 的 profile**
       安裝（desktop / web / …）；用 -Profile 可只裝一個。
    2. 把 skills/ 與 templates/ 複製到 <DSH_HOME>/pm-mode/，並寫入 manifest。
    3. 把 presets/pm-preset.patch.yml 的 {{PM_SKILLS_DIR}} 換成該路徑，
       冪等地寫進每個 <DSH_HOME>/profiles/<profile>/cordis.patch.yml 的 marker 區塊（先備份）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
.EXAMPLE
    .\scripts\install.ps1 -DshHome 'D:\dsh-home' -Profile desktop
#>
[CmdletBinding()]
param(
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),
    [string]$Profile = ''
)

$ErrorActionPreference = 'Stop'

$begin = '# >>> dsh-pm-mode:begin'
$end   = '# <<< dsh-pm-mode:end'
$version = '1.3'

$repoRoot     = Split-Path -Parent $PSScriptRoot
$source       = Join-Path $repoRoot 'presets\pm-preset.patch.yml'
$srcSkills    = Join-Path $repoRoot 'skills'
$srcTemplates = Join-Path $repoRoot 'templates'

Write-Host "== dsh-pm-mode 安裝（v$version）=="
Write-Host "repo      : $repoRoot"
Write-Host "DSH home  : $DshHome"

if (-not (Test-Path -LiteralPath $source))    { throw "找不到來源檔：$source" }
if (-not (Test-Path -LiteralPath $srcSkills)) { throw "找不到 skills 目錄：$srcSkills" }
if (-not (Test-Path -LiteralPath $DshHome))   { throw "找不到 DSH home：$DshHome（DSH 裝好了嗎？或用 -DshHome 指定）" }

# --- 1. 解析要處理哪些 profile ----------------------------------------------
$profilesRoot = Join-Path $DshHome 'profiles'
$candidates = @(
    Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'cordis.patch.yml') }
)
if ($candidates.Count -eq 0) { throw "在 $profilesRoot 找不到任何含 cordis.patch.yml 的 profile" }

function Test-PresetCapable([System.IO.DirectoryInfo]$dir) {
    $pkg = Join-Path $dir.FullName 'package.json'
    if (Test-Path -LiteralPath $pkg) {
        if ([System.IO.File]::ReadAllText($pkg) -match 'dsh-web-app') { return $true }
    }
    $txt = [System.IO.File]::ReadAllText((Join-Path $dir.FullName 'cordis.patch.yml'))
    if ($txt -match 'agent-preset|dsh-agent-preset') { return $true }
    return $false
}

if ($Profile) {
    $exact = @($candidates | Where-Object { $_.Name -eq $Profile })
    if ($exact.Count -ne 1) { throw "找不到 profile '$Profile'；可選：$($candidates.Name -join ', ')" }
    $targets = @($Profile)
} else {
    $targets = @($candidates | Where-Object { Test-PresetCapable $_ } | Select-Object -ExpandProperty Name)
    if ($targets.Count -eq 0) {
        $targets = @($candidates | Select-Object -ExpandProperty Name)
        Write-Host '（沒有 profile 明顯支援 preset，仍對全部 profile 安裝）'
    }
}
Write-Host "profiles  : $($targets -join ', ')"

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
    profiles     = $targets
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

# --- 4. 渲染 preset 區塊（共用，一次）---------------------------------------
$blockText = [System.IO.File]::ReadAllText($source)
$blockText = $blockText -replace '\{\{PM_SKILLS_DIR\}\}', $skillsFwd
$blockText = $blockText.TrimEnd()

$failed = 0
foreach ($name in $targets) {
    $patchPath = Join-Path $profilesRoot (Join-Path $name 'cordis.patch.yml')
    Write-Host ''
    Write-Host "[$name] $patchPath"

    $raw = [System.IO.File]::ReadAllText($patchPath)
    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$patchPath.bak-pm-$stamp"
    Copy-Item -LiteralPath $patchPath -Destination $backup -Force
    Write-Host "  已備份    : $backup"

    $nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $blockForThis = ($blockText -replace "`r?`n", $nl)
    $managedText = $begin + $nl + $blockForThis + $nl + $end

    $pattern = '(?ms)^' + [regex]::Escape($begin) + '.*?^' + [regex]::Escape($end) + '\r?\n?'
    $hadBlock = [regex]::IsMatch($raw, $pattern)
    $stripped = if ($hadBlock) { [regex]::Replace($raw, $pattern, '') } else { $raw }
    if ($stripped -notmatch "\r?\n$") { $stripped += $nl }
    if ($stripped.Trim() -eq '') { $stripped = '' }

    $new = $stripped + $managedText + $nl

    $pmIds = ([regex]::Matches($new, '(?m)^\s*id:\s*pm\s*$')).Count
    $beginCount = ([regex]::Matches($new, [regex]::Escape($begin))).Count
    $endCount   = ([regex]::Matches($new, [regex]::Escape($end))).Count
    if ($pmIds -ne 1 -or $beginCount -ne 1 -or $endCount -ne 1) {
        Write-Warning "  防呆失敗（pm=$pmIds, begin=$beginCount, end=$endCount）。此 profile 未寫入；備份於 $backup"
        $failed++
        continue
    }

    [System.IO.File]::WriteAllText($patchPath, $new, $utf8NoBom)
    $action = if ($hadBlock) { '已更新既有區塊' } else { '已追加新區塊' }
    Write-Host "  $action（marker 1 組）"
}

# --- 5. 下一步 --------------------------------------------------------------
Write-Host ''
Write-Host '下一步：'
Write-Host '  1) 驗證： powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1'
Write-Host '  2) 完整重啟 DSH（preset 宣告在啟動時載入）'
Write-Host '  3) 開新 session，在預設選擇器選「DSH PM 模式」'
if ($failed -gt 0) {
    Write-Host ''
    Write-Host "有 $failed 個 profile 寫入失敗，請看上面的訊息。"
    exit 1
}
