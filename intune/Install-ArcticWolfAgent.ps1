<#
.SYNOPSIS
    Installs the Arctic Wolf Agent silently. Safe to re-run. Works under Intune (Win32 app) and
    N-central (automation policy, runs as SYSTEM).
.PARAMETER MsiPath   Path to the agent MSI. Default: the single *.msi beside this script (the portal
                     download bundle is company-named, so no file name is assumed).
.PARAMETER MsiUrl    Optional HTTPS URL to download the MSI from when MsiPath does not exist.
.PARAMETER Uuid      Optional fallback when customer.json is not beside the MSI: the customer UUID
                     (a credential; from Keeper or an N-central secure property).
.PARAMETER RegHost   Optional fallback: the regional registration hostname
                     (activate.agent-common.prod.<region>.arcticwolf.net).
.NOTES
    The portal bundle contains customer.json with the UUID and regional DNS. When it is beside the MSI
    the installer reads it and -Uuid/-RegHost are not needed. The bundle is company-identifying and the
    UUID is a credential: keep it in the Intune package and the N-central file repository, never in git.
    Exit codes: 0 success, 3010 soft reboot, 1 failed (Intune return-code mapping).
#>
param(
    [string]$MsiPath = '',
    [string]$MsiUrl  = '',
    [string]$Uuid    = '',
    [string]$RegHost = ''
)

$ServiceName = 'ArcticWolfAgentMgr'   # Arctic Wolf Agent Manager (core). Not AWWfpService - the Containment Service only runs during host isolation
$UuidProp    = 'CUSTOMER_UUID'        # Arctic Wolf silent install: msiexec /i <agent> /qn CUSTOMER_UUID=<uuid> REGISTER_DNS=<dns> /l*v scout_install.log
$RegHostProp = 'REGISTER_DNS'
$LogDir      = 'C:\ProgramData\ArcticWolf-Install'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Log = Join-Path $LogDir ("install_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
function Write-Log($m) { $line = "{0:u} {1}" -f (Get-Date), $m; Add-Content -Path $Log -Value $line; Write-Output $line }

if (-not $MsiPath) { $MsiPath = (Get-ChildItem -Path $PSScriptRoot -Filter *.msi -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }

# 1. Already installed? Exit 0 so Intune marks compliant and N-central shows success.
if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) { Write-Log "Service '$ServiceName' present; nothing to do."; exit 0 }

# 2. Get the MSI
if (-not $MsiPath -or -not (Test-Path $MsiPath)) {
    if (-not $MsiUrl) { Write-Log "MSI not found beside the script and no -MsiUrl given."; exit 1 }
    $MsiPath = Join-Path $LogDir 'ArcticWolfAgent.msi'
    Write-Log "Downloading MSI from $MsiUrl"
    try { Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing } catch { Write-Log "Download failed: $_"; exit 1 }
}
$sig = Get-AuthenticodeSignature -FilePath $MsiPath
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Arctic Wolf') {
    Write-Log "MSI signature check failed: $($sig.Status) $($sig.SignerCertificate.Subject)"; exit 1
}

# 2b. The installer needs VBScript, an optional feature (off by default) on Windows 11 24H2+
$vbs = Get-WindowsCapability -Online -Name 'VBSCRIPT*' -ErrorAction SilentlyContinue
if ($vbs -and $vbs.State -ne 'Installed') {
    Write-Log "VBScript capability state: $($vbs.State); enabling."
    try {
        $r = Add-WindowsCapability -Online -Name $vbs.Name -ErrorAction Stop
        Write-Log "VBScript enabled (restart needed: $($r.RestartNeeded))."
    } catch {
        Write-Log "Could not enable VBScript: $_  (0x800F0954 = device points at WSUS and policy blocks Features on Demand from Windows Update)"
        exit 1
    }
}

# 3. Install silently
$msiLog = Join-Path $LogDir 'msiexec.log'
$args = @('/i', "`"$MsiPath`"", '/qn', '/norestart', '/l*v', "`"$msiLog`"")
$customerJson = Join-Path (Split-Path $MsiPath) 'customer.json'
if (Test-Path $customerJson) {
    Write-Log 'customer.json found beside the MSI; installer will read UUID and DNS from it.'
} elseif ($Uuid -and $RegHost) {
    $args += "$UuidProp=$Uuid", "$RegHostProp=$RegHost"
    Write-Log 'No customer.json; passing UUID and DNS as MSI properties.'
} else {
    Write-Log 'No customer.json beside the MSI and no -Uuid/-RegHost given; cannot register.'; exit 1
}
Write-Log "Running msiexec $(if ($Uuid) { $args -replace [regex]::Escape($Uuid), '<uuid>' } else { $args })"
$p = Start-Process -FilePath msiexec.exe -ArgumentList $args -Wait -PassThru
Write-Log "msiexec exit code $($p.ExitCode)"
if ($p.ExitCode -notin 0, 3010) { exit $p.ExitCode }

# 4. Verify the service came up (give it a minute)
$deadline = (Get-Date).AddSeconds(90)
do { Start-Sleep 5; $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue } until ($svc -or (Get-Date) -gt $deadline)
if (-not $svc) { Write-Log 'Install finished but service not found.'; exit 1 }
Write-Log "Installed; service status $($svc.Status)."
exit $(if ($p.ExitCode -eq 3010) { 3010 } else { 0 })
