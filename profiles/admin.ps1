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

# Graph sign-in: device code. The browser pop-up and the Windows account broker both fail on the admin
# profile (and the PAW has no reason to run a localhost listener). Use Connect-Admin instead of Connect-MgGraph.

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

# Connect-Admin: device-code sign-in with the scopes a task needs, then a reminder of who/where you are.
# Scripts that call Connect-MgGraph themselves (Inventory.ps1 etc.) reuse this session and skip their own prompt.
function global:Connect-Admin {
    param([string[]]$Scopes = @('Directory.Read.All'))
    Connect-MgGraph -Scopes $Scopes -UseDeviceCode -NoWelcome
    $c = Get-MgContext
    Write-Host ("Connected as {0} to {1} at {2}. Active PIM roles expire on their own; re-activate from the PIM portal." -f $c.Account, $c.TenantId, (Get-Date -Format 'HH:mm')) -ForegroundColor Yellow
}

# Scope sets for the runbook's scripts, so the right one is one word away
$global:AdminScopes = @{
    Read      = @('Directory.Read.All','RoleManagement.Read.Directory','Application.Read.All','AuditLog.Read.All','Policy.Read.All','Organization.Read.All','Device.Read.All','UserAuthenticationMethod.Read.All')
    Pim       = @('RoleManagement.ReadWrite.Directory','Directory.Read.All')
    CA        = @('Policy.ReadWrite.ConditionalAccess','Policy.Read.All')
    Groups    = @('GroupMember.ReadWrite.All','User.Read.All')
    Licensing = @('User.ReadWrite.All','Organization.Read.All')
}
# e.g.  Connect-Admin -Scopes $AdminScopes.Read   before .\Inventory.ps1
