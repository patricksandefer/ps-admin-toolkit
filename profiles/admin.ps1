# ---------- admin / PAW profile ----------
# Save as the ADMIN account's Documents\PowerShell\Microsoft.PowerShell_profile.ps1 (PowerShell 7)
# Requires common.ps1 beside it. No community modules on this side.

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force   # RemoteSigned until a code-signing cert exists.
                                                             # AllSigned later - then this profile and common.ps1 must be signed too, or nothing loads.
$ErrorView = 'ConciseView'
$WarningPreference = 'Continue'
$ConfirmPreference  = 'High'      # PowerShell default. 'Medium' makes folder creation, transcripts and module aliases prompt on every launch.
$Host.PrivateData.WarningForegroundColor = 'Black'
$Host.PrivateData.WarningBackgroundColor = 'Yellow'

# Every admin session is transcribed: when, what, how long, output. Reviewed weekly; kept 1 year.
$logDir = 'C:\Admin\Logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path (Join-Path $logDir ("{0:yyyy-MM-dd}_{1}_{2}.txt" -f (Get-Date), $env:USERNAME, $PID)) -Append -IncludeInvocationHeader | Out-Null
# IncludeInvocationHeader writes a timestamp line before each command, so the transcript is the timing record.

Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView -HistorySaveStyle SaveIncrementally
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Import-Module Az.Tools.Predictor -ErrorAction SilentlyContinue

$global:ProdTenants = @{ 'corp' = '00000000-0000-0000-0000-000000000000' }

# Shared timing and context functions - common.ps1 must exist beside this profile or the next line fails
. (Join-Path (Split-Path $PROFILE) 'common.ps1')
$null = Import-ToolkitSettings

# Graph sign-in through the Windows account broker (the signed-in admin identity), not a browser pop-up.
# The pop-up fails on this laptop profile; fallback if WAM misbehaves: Connect-MgGraph ... -UseDeviceCode
try { Set-MgGraphOption -EnableLoginByWAM $true -ErrorAction Stop } catch { }   # older Microsoft.Graph.Authentication versions; newer ones use WAM by default and lack the parameter

function global:prompt {
    $ok  = $?
    $now = Get-Date -Format 'HH:mm:ss'
    $dur = Get-LastCommandDuration
    Write-Host "[$now" -NoNewline -ForegroundColor DarkGray
    if ($dur) { Write-Host " $dur" -NoNewline -ForegroundColor DarkCyan }
    Write-Host '] ' -NoNewline -ForegroundColor DarkGray
    Write-Host ' ADMIN ' -NoNewline -ForegroundColor White -BackgroundColor DarkRed
    if (-not $ok) { Write-Host ' FAILED ' -NoNewline -ForegroundColor White -BackgroundColor Red }
    $ctx = Get-CloudContextLine
    if (-not $ctx) { Write-Host ' not connected ' -NoNewline -ForegroundColor DarkGray }
    foreach ($p in $ctx) { Write-Host " $($p.Text) " -NoNewline -ForegroundColor White -BackgroundColor DarkRed }
    Write-Host ''
    return "PS $(Get-Location)> "
}

# Guard rails: the verbs that delete or disable always confirm, whatever the cmdlet's own ConfirmImpact
$global:PSDefaultParameterValues['Remove-*:Confirm']    = $true
$global:PSDefaultParameterValues['Disable-*:Confirm']   = $true
$global:PSDefaultParameterValues['Set-Mailbox:Confirm'] = $true

# Reminder on connect: which tenant, and that PIM roles expire
function global:Connect-Admin {
    param([string[]]$Scopes = @('Directory.Read.All'))
    Connect-MgGraph -Scopes $Scopes -NoWelcome
    $c = Get-MgContext
    Write-Host ("Connected as {0} to {1} at {2}. Active PIM roles expire on their own; re-activate from the PIM portal." -f $c.Account, $c.TenantId, (Get-Date -Format 'HH:mm')) -ForegroundColor Yellow
}
