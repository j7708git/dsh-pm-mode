<#
.SYNOPSIS
    dsh-pm-mode 驗證腳本（Windows）。

.DESCRIPTION
    驗收項 1–3：
      1. patch 檔 YAML 語法有效
      2. marker 區塊與 preset id 各只有一個、placeholder 已渲染且指向存在的技能目錄
      3. `dsh --profile <p> --dump-config` 與 baseline 的差異沒有移除任何既有行
    另外檢查安裝到 <DSH_HOME>/pm-mode/skills 的技能 frontmatter 與長度。

.PARAMETER Snapshot
    只把目前的 dump-config 存成 baseline（安裝前使用），不做其他檢查。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1 -Snapshot
    powershell -ExecutionPolicy Bypass -File .\scripts\verify.ps1
#>
[CmdletBinding()]
param(
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),
    [string]$Profile = 'web',
    [switch]$Snapshot
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Split-Path -Parent $PSScriptRoot
$artifacts = Join-Path $repoRoot '.artifacts'
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

# --- 解析 profile -----------------------------------------------------------
$profilesRoot = Join-Path $DshHome 'profiles'
$candidates = @(
    Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'cordis.patch.yml') }
)
$exact = @($candidates | Where-Object { $_.Name -eq $Profile })
if ($exact.Count -eq 1) { $Profile = $exact[0].Name }
elseif ($candidates.Count -eq 1) { $Profile = $candidates[0].Name }

$patchPath = Join-Path $profilesRoot (Join-Path $Profile 'cordis.patch.yml')
$modeDir   = Join-Path $DshHome 'pm-mode'
$manifestPath = Join-Path $modeDir 'install.json'

$failures = New-Object System.Collections.Generic.List[string]
function Ok($msg)   { Write-Host "  [OK]   $msg" }
function Warn($msg) { Write-Host "  [WARN] $msg" }
function Bad($msg)  { Write-Host "  [FAIL] $msg"; $script:failures.Add($msg) }

function Get-Dump([string]$fileName) {
    $out = Join-Path $artifacts $fileName
    if (-not (Get-Command dsh -ErrorAction SilentlyContinue)) {
        Warn '找不到 dsh 指令，跳過 dump-config'
        return $null
    }
    try {
        $env:DSH_HOME = $DshHome
        $text = & dsh --profile $Profile --dump-config 2>&1 | Out-String
        Set-Content -LiteralPath $out -Value $text -Encoding UTF8
        return $text
    } catch {
        Warn "dump-config 執行失敗：$($_.Exception.Message)"
        return $null
    }
}

if ($Snapshot) {
    Write-Host '== 建立 baseline（安裝前）=='
    $text = Get-Dump 'dump-baseline.txt'
    if ($text) {
        [System.IO.File]::WriteAllText((Join-Path $artifacts 'dump-baseline.home'), $DshHome, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "已寫入 $(Join-Path $artifacts 'dump-baseline.txt')（$($text.Length) 字元，DSH home = $DshHome）"
    }
    exit 0
}

Write-Host '== dsh-pm-mode 驗證 =='
Write-Host "DSH home  : $DshHome"
Write-Host "profile   : $Profile"

# --- 1. YAML ----------------------------------------------------------------
Write-Host '[1/4] YAML 語法'
$raw = $null
if (-not (Test-Path -LiteralPath $patchPath)) {
    Bad "找不到 patch 檔：$patchPath"
} else {
    $raw = [System.IO.File]::ReadAllText($patchPath)
    $checker = Join-Path $PSScriptRoot 'check-yaml.mjs'
    if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $checker)) {
        $profileDir = Join-Path $profilesRoot $Profile
        $lines = & node $checker $patchPath $profileDir 2>&1
        $code = $LASTEXITCODE
        $lines | ForEach-Object { Write-Host "  $_" }
        if ($code -ne 0) { Bad 'YAML 解析失敗' }
    } else {
        Warn '找不到 node 或 check-yaml.mjs，跳過 YAML 解析（改由 dump-config 把關）'
    }
}

# --- 2. marker / id / 渲染 --------------------------------------------------
Write-Host '[2/4] marker、preset id、skills 路徑'
$renderedSkills = $null
if ($raw) {
    $begin = '# >>> dsh-pm-mode:begin'
    $end   = '# <<< dsh-pm-mode:end'
    $beginCount = ([regex]::Matches($raw, [regex]::Escape($begin))).Count
    $endCount   = ([regex]::Matches($raw, [regex]::Escape($end))).Count
    if ($beginCount -eq 1 -and $endCount -eq 1) { Ok 'marker 區塊恰好 1 組' } else { Bad "marker 數量異常（begin=$beginCount, end=$endCount）" }

    $pmIds = ([regex]::Matches($raw, '(?m)^\s*id:\s*pm\s*$')).Count
    if ($pmIds -eq 1) { Ok 'preset id `pm` 恰好 1 個' } else { Bad "`id: pm` 出現 $pmIds 次（應為 1）" }

    $rowIds = ([regex]::Matches($raw, '(?m)^\s*-\s*id:\s*preset-pm\s*$')).Count
    if ($rowIds -eq 1) { Ok '宣告行 `preset-pm` 恰好 1 個' } else { Bad "`preset-pm` 宣告行出現 $rowIds 次（應為 1）" }

    if ($raw -match '\{\{PM_SKILLS_DIR\}\}') {
        Bad '仍有 {{PM_SKILLS_DIR}} 未渲染（請重跑 install）'
    } else {
        $m = [regex]::Match($raw, "(?m)^\s*-\s*'?([A-Za-z]:/[^'\r\n]+/pm-mode/skills)'?\s*$")
        if ($m.Success) {
            $renderedSkills = $m.Groups[1].Value
            Ok "skills 路徑已渲染：$renderedSkills"
        } else {
            Bad '找不到渲染後的 customSkillDirs 路徑'
        }
    }
}

# --- 3. 安裝到 DSH home 的 skills -------------------------------------------
Write-Host '[3/4] 已安裝的 skills'
$skillsDir = Join-Path $modeDir 'skills'
if (-not (Test-Path -LiteralPath $skillsDir)) {
    Bad "找不到已安裝的 skills 目錄：$skillsDir（請先跑 install）"
} else {
    if ($renderedSkills) {
        $normalized = ($skillsDir -replace '\\', '/')
        if ($normalized -eq $renderedSkills) { Ok 'preset 指向的目錄與實際安裝位置一致' }
        else { Bad "preset 指向 $renderedSkills，實際在 $normalized" }
    }
    $dirs = @(Get-ChildItem -LiteralPath $skillsDir -Directory -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 0) { Bad "skills 目錄是空的：$skillsDir" }
    foreach ($dir in $dirs) {
        $file = Join-Path $dir.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $file)) { Bad "$($dir.Name)：缺少 SKILL.md"; continue }
        $text = [System.IO.File]::ReadAllText($file)
        $bytes = (Get-Item -LiteralPath $file).Length
        $problems = @()
        if ($text -notmatch "(?m)^name:\s*$([regex]::Escape($dir.Name))\s*$") { $problems += 'frontmatter name 與目錄名不符' }
        if ($text -notmatch '(?m)^description:\s*\S')                            { $problems += 'frontmatter 缺 description' }
        if ($dir.Name -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$')                     { $problems += '目錄名非 kebab-case' }
        if ($bytes -gt 8000)                                                    { $problems += "長度 $bytes 位元組超過 8000" }
        if ($problems.Count -eq 0) { Ok "$($dir.Name)（$bytes 位元組）" } else { Bad "$($dir.Name)：$($problems -join '；')" }
    }
}

# --- manifest 與 templates --------------------------------------------------
if (Test-Path -LiteralPath $manifestPath) { Ok "manifest 存在：$manifestPath" } else { Warn "找不到 manifest：$manifestPath" }

$templatesDir = Join-Path $modeDir 'templates'
if (Test-Path -LiteralPath (Join-Path $templatesDir 'project\README.md')) {
    Ok "templates 已安裝：$templatesDir"
} else {
    Warn "找不到已安裝的 templates（$templatesDir）；PM 開新專案時會改用手動結構（見 pm-scaffold skill）"
}

# --- 4. dump diff -----------------------------------------------------------
Write-Host '[4/4] dump-config 差異'
$baselineFile = Join-Path $artifacts 'dump-baseline.txt'
$baselineHomeFile = Join-Path $artifacts 'dump-baseline.home'
$baselineHome = $null
if (Test-Path -LiteralPath $baselineHomeFile) {
    $baselineHome = ([System.IO.File]::ReadAllText($baselineHomeFile)).Trim()
}
if (-not (Test-Path -LiteralPath $baselineFile)) {
    Warn '沒有 baseline；請在安裝前先跑 verify -Snapshot。仍會存下本次 dump。'
    Get-Dump 'dump-after.txt' | Out-Null
} elseif ($baselineHome -and ($baselineHome -ne $DshHome)) {
    Warn "baseline 是針對 $baselineHome 取的，與目前 $DshHome 不同；跳過差異比對（仍會存下本次 dump）"
    Get-Dump 'dump-after.txt' | Out-Null
} else {
    $after = Get-Dump 'dump-after.txt'
    if ($after) {
        $before = Get-Content -LiteralPath $baselineFile
        $now    = Get-Content -LiteralPath (Join-Path $artifacts 'dump-after.txt')
        $added   = @(Compare-Object -ReferenceObject $before -DifferenceObject $now | Where-Object SideIndicator -eq '=>')
        $removed = @(Compare-Object -ReferenceObject $before -DifferenceObject $now | Where-Object SideIndicator -eq '<=')
        Write-Host "  新增 $($added.Count) 行、移除 $($removed.Count) 行"
        if ($added.Count -gt 0) {
            Write-Host '  --- 新增（前 20 行）---'
            $added | Select-Object -First 20 | ForEach-Object { Write-Host "   + $($_.InputObject.Trim())" }
        }
        if ($removed.Count -gt 0) {
            Write-Host '  --- 移除（前 20 行）---'
            $removed | Select-Object -First 20 | ForEach-Object { Write-Host "   - $($_.InputObject.Trim())" }
            Bad "有 $($removed.Count) 行被移除，請檢查是否影響其他 preset"
        } else {
            Ok '沒有任何既有行被移除（無回歸）'
        }
        if ($added.Count -gt 0) { Ok '差異僅為新增（含 pm preset）' } else { Warn 'dump 沒有差異；模式可能未安裝或已移除' }
    }
}

Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host '全部檢查通過。'
    exit 0
}
Write-Host "有 $($failures.Count) 項失敗："
$failures | ForEach-Object { Write-Host "  - $_" }
exit 1
