# ---------- daily-driver profile ----------
# Save as: Documents\PowerShell\Microsoft.PowerShell_profile.ps1 (PowerShell 7)
# Requires common.ps1 beside it.

$ErrorView = 'ConciseView'
$WarningPreference = 'Continue'
$Host.PrivateData.WarningForegroundColor = 'Black'
$Host.PrivateData.WarningBackgroundColor = 'Yellow'   # warnings stand out instead of scrolling past

Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Ctrl+r    -Function ReverseSearchHistory
Import-Module Az.Tools.Predictor -ErrorAction SilentlyContinue
Import-Module Terminal-Icons, posh-git, ZLocation -ErrorAction SilentlyContinue

# Which tenants count as production: name => tenant id. Real values come from settings.local.ps1.
$global:ProdTenants = @{ 'corp' = '00000000-0000-0000-0000-000000000000' }

. (Join-Path (Split-Path $PROFILE) 'common.ps1')
$null = Import-ToolkitSettings

function global:prompt {
    $ok  = $?
    $now = Get-Date -Format 'HH:mm:ss'
    $dur = Get-LastCommandDuration
    Write-Host "[$now" -NoNewline -ForegroundColor DarkGray
    if ($dur) { Write-Host " $dur" -NoNewline -ForegroundColor DarkCyan }
    Write-Host ']' -NoNewline -ForegroundColor DarkGray
    if (-not $ok) { Write-Host ' FAILED' -NoNewline -ForegroundColor White -BackgroundColor DarkRed }
    foreach ($p in Get-CloudContextLine) {
        $fg = if ($p.Prod) { 'White' } else { 'Black' }
        $bg = if ($p.Prod) { 'DarkRed' } else { 'DarkGreen' }
        Write-Host " $($p.Text) " -NoNewline -ForegroundColor $fg -BackgroundColor $bg
    }
    Write-Host ''
    return "PS $(Get-Location)> "
}

$global:PSDefaultParameterValues['*:WarningAction'] = 'Continue'
