<#
.SYNOPSIS
    dsh-pm-mode 移除腳本（Windows）。可重複執行。

.DESCRIPTION
    1. 從 <DSH_HOME>/profiles/<profile>/cordis.patch.yml 移除 marker 區塊（先備份），其他使用者內容保留。
    2. 刪除安裝時複製的 <DSH_HOME>/pm-mode（skills 與 manifest）。
    使用者自己的 skill（例如 ~/.dsh/skills/ 下的其他項目）一律不動。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
#>
[CmdletBinding()]
param(
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),
    [string]$Profile = 'web'
)

$ErrorActionPreference = 'Stop'

$begin = '# >>> dsh-pm-mode:begin'
$end   = '# <<< dsh-pm-mode:end'

Write-Host '== dsh-pm-mode 移除 =='
Write-Host "DSH home  : $DshHome"

$profilesRoot = Join-Path $DshHome 'profiles'
$candidates = @(
    Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'cordis.patch.yml') }
)
$exact = @($candidates | Where-Object { $_.Name -eq $Profile })
if ($exact.Count -eq 1) { $Profile = $exact[0].Name }
elseif ($candidates.Count -eq 1) { $Profile = $candidates[0].Name }

$patchPath = Join-Path $profilesRoot (Join-Path $Profile 'cordis.patch.yml')
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# --- patch 區塊 -------------------------------------------------------------
if (Test-Path -LiteralPath $patchPath) {
    $raw = [System.IO.File]::ReadAllText($patchPath)
    $pattern = '(?ms)^' + [regex]::Escape($begin) + '.*?^' + [regex]::Escape($end) + '\r?\n?'
    if ([regex]::IsMatch($raw, $pattern)) {
        $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = "$patchPath.bak-pm-$stamp"
        Copy-Item -LiteralPath $patchPath -Destination $backup -Force
        Write-Host "已備份    : $backup"
        $new = [regex]::Replace($raw, $pattern, '')
        [System.IO.File]::WriteAllText($patchPath, $new, $utf8NoBom)
        Write-Host "已移除 marker 區塊：$patchPath"
    } else {
        Write-Host "找不到 marker 區塊，patch 檔未變更：$patchPath"
    }
} else {
    Write-Host "找不到 patch 檔：$patchPath"
}

# --- 模式自己的資料夾 -------------------------------------------------------
$modeDir = Join-Path $DshHome 'pm-mode'
if (Test-Path -LiteralPath $modeDir) {
    if ($modeDir -notmatch 'pm-mode$') { throw "拒絕刪除非預期路徑：$modeDir" }
    Remove-Item -LiteralPath $modeDir -Recurse -Force
    Write-Host "已刪除    : $modeDir"
} else {
    Write-Host "找不到    : $modeDir（可能已移除）"
}

Write-Host ''
Write-Host '下一步：完整重啟 DSH，「DSH PM 模式」即從選擇器消失。'
