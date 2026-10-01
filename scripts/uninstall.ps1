<#
.SYNOPSIS
    dsh-pm-mode 移除腳本（Windows）。可重複執行。

.DESCRIPTION
    1. 從每個 <DSH_HOME>/profiles/<profile>/cordis.patch.yml 移除 marker 區塊（先備份），
       其他使用者內容一律保留；可用 -Profile 只處理一個。
    2. 刪除安裝時複製的 <DSH_HOME>/pm-mode（skills、templates 與 manifest）。
    使用者自己的 skill（例如 ~/.dsh/skills/ 下的其他項目）一律不動。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
#>
[CmdletBinding()]
param(
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }),
    [string]$Profile = ''
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
if ($Profile) {
    $candidates = @($candidates | Where-Object { $_.Name -eq $Profile })
    if ($candidates.Count -eq 0) { throw "找不到 profile '$Profile'" }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$removedAny = $false

foreach ($dir in $candidates) {
    $patchPath = Join-Path $dir.FullName 'cordis.patch.yml'
    $raw = [System.IO.File]::ReadAllText($patchPath)
    $pattern = '(?ms)^' + [regex]::Escape($begin) + '.*?^' + [regex]::Escape($end) + '\r?\n?'
    if (-not [regex]::IsMatch($raw, $pattern)) { continue }

    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$patchPath.bak-pm-$stamp"
    Copy-Item -LiteralPath $patchPath -Destination $backup -Force
    $new = [regex]::Replace($raw, $pattern, '')
    [System.IO.File]::WriteAllText($patchPath, $new, $utf8NoBom)
    Write-Host "已移除區塊：$patchPath（備份：$backup）"
    $removedAny = $true
}
if (-not $removedAny) { Write-Host '找不到任何 dsh-pm-mode 區塊，patch 檔未變更。' }

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
