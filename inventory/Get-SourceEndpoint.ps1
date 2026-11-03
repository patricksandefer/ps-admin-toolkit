<#
.SYNOPSIS
    M&A due-diligence endpoint sweep (runbook F2b, Sweep 1). Inventories what a migration will trip over
    on an acquired user's PC: PST/OST files, mounted Outlook data files, installed software, cloud-sync
    clients, mapped drives and printers, browser extensions, non-Microsoft services/tasks, Office add-ins,
    Access/macro files, user certificates, VPN clients. Read-only. One JSON per machine.
.PARAMETER OutDir   UNC share or local folder to write <COMPUTER>_<USER>.json into.
.NOTES
    Run as the signed-in user (needed for the Outlook profile and HKCU data) via the acquired company's
    RMM, a login script, or N-central once onboarded. Windows PowerShell 5.1 is sufficient.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutDir
)

$r = [ordered]@{ Computer = $env:COMPUTERNAME; User = $env:USERNAME; When = (Get-Date).ToString('u') }

# 1. PST / OST / NST files anywhere on local fixed drives
$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 -and $_.Root -match '^[A-Z]:\\$' }
$r.OutlookDataFiles = @(foreach ($d in $drives) {
    Get-ChildItem -Path $d.Root -Recurse -Include *.pst,*.ost,*.nst -File -ErrorAction SilentlyContinue |
        Select-Object FullName, @{n='SizeMB';e={[math]::Round($_.Length/1MB)}}, LastWriteTime
})

# 2. PSTs actually mounted in the Outlook profile
$r.MountedPst = @(Get-ChildItem 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles' -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
    Where-Object { $_.PSObject.Properties.Name -contains '001f6700' } |
    ForEach-Object { [Text.Encoding]::Unicode.GetString($_.'001f6700').TrimEnd("`0") } | Sort-Object -Unique)

# 3. Installed software: classic installers + Store apps
$uninst = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
$r.Software = @(Get-ItemProperty $uninst -ErrorAction SilentlyContinue | Where-Object DisplayName |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate,
        @{n='Scope';e={ if ($_.PSPath -match 'HKCU') { 'User' } else { 'Machine' } }} | Sort-Object DisplayName)
$r.StoreApps = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and $_.SignatureKind -ne 'System' } |
    Select-Object Name, Version, Publisher)

# 4. Cloud-sync clients and personal storage
$r.SyncClients = @($r.Software | Where-Object DisplayName -match 'Dropbox|Google Drive|\bBox\b|iCloud|Sync\.com|Mega|pCloud|OneDrive' |
    Select-Object DisplayName, DisplayVersion)
$r.OneDriveAccounts = @(Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ItemProperty $_.PSPath } | Select-Object @{n='Account';e={$_.PSChildName}}, UserEmail, Business, UserFolder)

# 5. Mapped drives, printers, recent servers
$r.MappedDrives = @(Get-SmbMapping -ErrorAction SilentlyContinue | Select-Object LocalPath, RemotePath)
$r.Printers     = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object Type -eq 'Connection' | Select-Object Name, ComputerName, PortName)
$mru = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Map Network Drive MRU' -ErrorAction SilentlyContinue
$r.RecentServers = @(if ($mru) { $mru.PSObject.Properties | Where-Object Name -match '^[a-z]$' | Select-Object -ExpandProperty Value })

# 6. Browser extensions (names only)
$extNames = foreach ($p in "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions", "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions") {
    Get-ChildItem $p -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $m = Get-ChildItem $_.FullName -Recurse -Filter manifest.json -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($m) { try { (Get-Content $m.FullName -Raw | ConvertFrom-Json).name } catch { $_.Name } }
    }
}
$r.BrowserExtensions = @($extNames | Sort-Object -Unique)

# 7. Local admins, non-Microsoft scheduled tasks and services
$r.LocalAdmins   = @((Get-LocalGroupMember -Group Administrators -ErrorAction SilentlyContinue).Name)
$r.NonMsTasks    = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notmatch '^\\Microsoft' -and $_.State -ne 'Disabled' } |
    Select-Object TaskName, TaskPath, @{n='Action';e={($_.Actions | Select-Object -First 1).Execute}})
$r.NonMsServices = @(Get-CimInstance Win32_Service | Where-Object { $_.PathName -notmatch 'Windows|Microsoft' -and $_.StartMode -ne 'Disabled' } |
    Select-Object Name, DisplayName, PathName, StartMode)

# 8. Office add-ins, Access databases, macro-enabled files in the profile
$r.OfficeAddins = @(Get-ChildItem 'HKCU:\Software\Microsoft\Office\*\Addins','HKLM:\Software\Microsoft\Office\*\Addins' -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty PSChildName -Unique)
$r.LobFiles = @(Get-ChildItem "$env:USERPROFILE" -Recurse -Include *.accdb,*.mdb,*.xlsm,*.docm -File -ErrorAction SilentlyContinue |
    Select-Object FullName, @{n='SizeMB';e={[math]::Round($_.Length/1MB,1)}}, LastWriteTime)

# 9. User certificates and VPN clients
$r.UserCerts  = @(Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue | Select-Object Subject, Issuer, NotAfter)
$r.VpnClients = @($r.Software | Where-Object DisplayName -match 'VPN|AnyConnect|GlobalProtect|FortiClient|Pulse|SonicWall|WatchGuard' | Select-Object DisplayName)

New-Item -ItemType Directory -Path $OutDir -Force -ErrorAction SilentlyContinue | Out-Null
$out = Join-Path $OutDir "$($env:COMPUTERNAME)_$($env:USERNAME).json"
$r | ConvertTo-Json -Depth 6 | Set-Content $out
Write-Output "Wrote $out"
