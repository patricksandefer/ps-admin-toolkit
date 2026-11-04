<#
.SYNOPSIS
    Tenant inventory (runbook Checklist B2): roles, guests, apps, forwarding, service accounts,
    MFA registration, domains, Conditional Access, devices, licenses. Read-only.
.DESCRIPTION
    Writes one CSV/JSON per item into -OutDir with the date in the folder name, so the same export
    can be re-run later for a before/after comparison. Activate Global Reader or Security Reader
    through PIM before running; Global Administrator is not needed.
.PARAMETER OutDir   Output folder. Default C:\Admin\Inventory\<yyyy-MM>
.PARAMETER SkipExchange   Skip the Exchange Online items (forwarding, shared mailboxes, domains/DKIM)
.EXAMPLE
    .\Inventory.ps1
    .\Inventory.ps1 -OutDir C:\Admin\Inventory\2026-10 -SkipExchange
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path 'C:\Admin\Inventory' (Get-Date -Format 'yyyy-MM')),
    [switch]$SkipExchange
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
function Save($Name, $Data) {
    $path = Join-Path $OutDir $Name
    if ($Name -like '*.json') { $Data | ConvertTo-Json -Depth 10 | Set-Content $path }
    else { $Data | Export-Csv $path -NoTypeInformation }
    Write-Host ("{0,-28} {1,6} rows" -f $Name, @($Data).Count)
}

Import-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups,
              Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Identity.Governance,
              Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Applications, Microsoft.Graph.Reports
# Reuse an existing Graph session (e.g. from Connect-Admin); otherwise sign in with device code.
if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes 'Directory.Read.All','RoleManagement.Read.Directory','Application.Read.All',
                        'AuditLog.Read.All','Policy.Read.All','Organization.Read.All','Device.Read.All',
                        'UserAuthenticationMethod.Read.All' -UseDeviceCode -NoWelcome
}
# 1. Directory roles: active + eligible
$roleDefs = Get-MgRoleManagementDirectoryRoleDefinition -All | Select-Object Id, DisplayName
$roleMap  = @{}; foreach ($r in $roleDefs) { $roleMap[$r.Id] = $r.DisplayName }
$active = Get-MgRoleManagementDirectoryRoleAssignment -All -ExpandProperty Principal | ForEach-Object {
    [pscustomobject]@{ Type='Active'; Role=$roleMap[$_.RoleDefinitionId]; PrincipalId=$_.PrincipalId
        Principal=$_.Principal.AdditionalProperties['userPrincipalName'] ?? $_.Principal.AdditionalProperties['displayName']
        PrincipalType=$_.Principal.AdditionalProperties['@odata.type'] -replace '#microsoft.graph.','' ; Scope=$_.DirectoryScopeId }
}
$eligible = Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All -ExpandProperty Principal -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{ Type='Eligible'; Role=$roleMap[$_.RoleDefinitionId]; PrincipalId=$_.PrincipalId
        Principal=$_.Principal.AdditionalProperties['userPrincipalName'] ?? $_.Principal.AdditionalProperties['displayName']
        PrincipalType=$_.Principal.AdditionalProperties['@odata.type'] -replace '#microsoft.graph.',''; Scope=$_.DirectoryScopeId }
}
Save 'roles.csv' (@($active) + @($eligible))

# 2. Guests with last sign-in
$guests = Get-MgUser -All -Filter "userType eq 'Guest'" -Property Id,DisplayName,Mail,UserPrincipalName,CreatedDateTime,SignInActivity,AccountEnabled |
    Select-Object DisplayName, Mail, UserPrincipalName, CreatedDateTime, AccountEnabled,
        @{n='LastSignIn';e={$_.SignInActivity.LastSignInDateTime}},
        @{n='DaysSinceSignIn';e={ if ($_.SignInActivity.LastSignInDateTime) { [int]((Get-Date) - $_.SignInActivity.LastSignInDateTime).TotalDays } else { 'never' } }}
Save 'guests.csv' $guests

# 3. App registrations (credentials + expiry) and service principals with consented permissions
$apps = Get-MgApplication -All -Property Id,AppId,DisplayName,CreatedDateTime,PasswordCredentials,KeyCredentials | ForEach-Object {
    $a = $_
    $creds = @($a.PasswordCredentials | ForEach-Object { [pscustomobject]@{ Kind='Secret'; End=$_.EndDateTime } }) +
             @($a.KeyCredentials      | ForEach-Object { [pscustomobject]@{ Kind='Cert';   End=$_.EndDateTime } })
    [pscustomobject]@{ DisplayName=$a.DisplayName; AppId=$a.AppId; Created=$a.CreatedDateTime
        Credentials=$creds.Count; Expired=@($creds | Where-Object End -lt (Get-Date)).Count
        NextExpiry=($creds | Sort-Object End | Select-Object -First 1).End }
}
Save 'apps.csv' $apps
$grants = Get-MgOauth2PermissionGrant -All
$spMap = @{}; Get-MgServicePrincipal -All -Property Id,DisplayName,AppId | ForEach-Object { $spMap[$_.Id] = $_.DisplayName }
$consents = $grants | ForEach-Object {
    [pscustomobject]@{ App=$spMap[$_.ClientId]; ConsentType=$_.ConsentType; Scopes=$_.Scope; Resource=$spMap[$_.ResourceId] }
}
Save 'app-consents.csv' $consents

# 6. MFA registration
$mfa = Get-MgReportAuthenticationMethodUserRegistrationDetail -All |
    Select-Object UserPrincipalName, UserDisplayName, IsAdmin, IsMfaRegistered, IsMfaCapable,
        IsPasswordlessCapable, @{n='Methods';e={$_.MethodsRegistered -join ';'}}, DefaultMfaMethod
Save 'mfa-registration.csv' $mfa

# 8. Conditional Access policies (full JSON, re-importable)
$ca = Get-MgIdentityConditionalAccessPolicy -All
Save 'ca-policies.json' $ca
Save 'ca-policies-summary.csv' ($ca | Select-Object DisplayName, State, CreatedDateTime, ModifiedDateTime)

# 9. Devices
$devices = Get-MgDevice -All -Property DisplayName,OperatingSystem,OperatingSystemVersion,TrustType,ApproximateLastSignInDateTime,IsCompliant,IsManaged,AccountEnabled |
    Select-Object DisplayName, OperatingSystem, OperatingSystemVersion, TrustType, IsManaged, IsCompliant, AccountEnabled, ApproximateLastSignInDateTime,
        @{n='DaysSinceActivity';e={ if ($_.ApproximateLastSignInDateTime) { [int]((Get-Date) - $_.ApproximateLastSignInDateTime).TotalDays } else { 'never' } }}
Save 'devices.csv' $devices

# 10. Licenses
$skus = Get-MgSubscribedSku | Select-Object SkuPartNumber, SkuId, @{n='Purchased';e={$_.PrepaidUnits.Enabled}}, ConsumedUnits,
    @{n='Free';e={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}}, CapabilityStatus
Save 'licenses.csv' $skus

# 4, 5, 7. Exchange Online items
if (-not $SkipExchange) {
    Import-Module ExchangeOnlineManagement
    # Reuse an existing Exchange Online session (e.g. Connect-ExchangeOnline -Device); otherwise sign in with device code.
    if (-not (Get-ConnectionInformation | Where-Object State -eq 'Connected')) {
        Connect-ExchangeOnline -Device -ShowBanner:$false
    }
    $mbx = Get-EXOMailbox -ResultSize Unlimited -Properties UserPrincipalName, ForwardingSmtpAddress, ForwardingAddress, DeliverToMailboxAndForward, RecipientTypeDetails
    $fwd = foreach ($m in $mbx) {
        if ($m.ForwardingSmtpAddress -or $m.ForwardingAddress) {
            [pscustomobject]@{ Mailbox=$m.UserPrincipalName; Kind='MailboxForwarding'; Target=($m.ForwardingSmtpAddress ?? $m.ForwardingAddress); KeepCopy=$m.DeliverToMailboxAndForward }
        }
        Get-InboxRule -Mailbox $m.UserPrincipalName -ErrorAction SilentlyContinue | Where-Object { $_.ForwardTo -or $_.RedirectTo -or $_.ForwardAsAttachmentTo } | ForEach-Object {
            [pscustomobject]@{ Mailbox=$m.UserPrincipalName; Kind="InboxRule:$($_.Name)"; Target=(@($_.ForwardTo)+@($_.RedirectTo)+@($_.ForwardAsAttachmentTo) -join ';'); KeepCopy=$null }
        }
    }
    Save 'forwarding.csv' $fwd
    $shared = $mbx | Where-Object RecipientTypeDetails -in 'SharedMailbox','RoomMailbox','EquipmentMailbox' |
        Select-Object DisplayName, UserPrincipalName, RecipientTypeDetails, @{n='HasAdminRole';e={ $upn=$_.UserPrincipalName; [bool]($active + $eligible | Where-Object Principal -eq $upn) }}
    Save 'service-accounts.csv' $shared
    $domains = Get-AcceptedDomain | ForEach-Object {
        $d = $_.DomainName
        $dkim = Get-DkimSigningConfig -Identity $d -ErrorAction SilentlyContinue
        $dmarc = (Resolve-DnsName "_dmarc.$d" -Type TXT -ErrorAction SilentlyContinue | Where-Object Strings -match 'v=DMARC1').Strings -join ''
        $spf   = (Resolve-DnsName $d -Type TXT -ErrorAction SilentlyContinue | Where-Object Strings -match 'v=spf1').Strings -join ''
        [pscustomobject]@{ Domain=$d; Default=$_.Default; Type=$_.DomainType; DkimEnabled=$dkim.Enabled; DMARC=$dmarc; SPF=$spf }
    }
    Save 'domains.csv' $domains
}

# Headline numbers for the findings memo
$summary = [ordered]@{
    StandingGlobalAdmins   = @($active | Where-Object Role -eq 'Global Administrator').Count
    EligibleGlobalAdmins   = @($eligible | Where-Object Role -eq 'Global Administrator').Count
    GuestsStale90d         = @($guests | Where-Object { $_.DaysSinceSignIn -eq 'never' -or $_.DaysSinceSignIn -gt 90 }).Count
    AppsWithExpiredCreds   = @($apps | Where-Object Expired -gt 0).Count
    AdminConsentedApps     = @($consents | Where-Object ConsentType -eq 'AllPrincipals').Count
    UsersWithoutMfa        = @($mfa | Where-Object { -not $_.IsMfaRegistered }).Count
    ExternalForwarding     = if ($fwd) { @($fwd).Count } else { 'skipped' }
    DevicesInactive60d     = @($devices | Where-Object { $_.DaysSinceActivity -eq 'never' -or $_.DaysSinceActivity -gt 60 }).Count
}
Save 'summary.json' $summary
$summary | Format-Table -AutoSize
Write-Host "Done. Output in $OutDir"
