<#
.SYNOPSIS
    Creates the IT inbox folder tree and the nine triage rules (runbook "Inbox setup"). Re-runnable:
    existing folders and rules with the same names are left alone.
.PARAMETER Mailbox      UPN of the mailbox. Default: the signed-in user. Another user's mailbox needs
                        Exchange Administrator (PIM) for the rules; folders for another user cannot be
                        created through Graph 'me' - create them by hand there and run with -SkipFolders.
.PARAMETER SkipFolders  Skip the Graph folder-creation step
.EXAMPLE
    .\New-InboxRules.ps1 -WhatIf
    .\New-InboxRules.ps1
    .\New-InboxRules.ps1 -Mailbox new.hire@example.com -SkipFolders
.NOTES
    Edit the sender lists below once you have seen the real alert senders arrive. Keep the committed
    copy generic; real addresses can live in the company repo or in settings.local.ps1.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Mailbox = '',
    [switch]$SkipFolders
)

# ---- Edit these once: real sender addresses as you see them arrive ----
$VIPs            = @('<manager@example.com>','<ciso-advisor@vendor.example>','<acq-pm@example.com>','<it-admin-1@example.com>','<it-admin-2@example.com>')
$CriticalFrom    = @('azure-noreply@microsoft.com','<arctic-wolf-alert-sender>','<defender-alert-sender>')
$CriticalSubject = @('P1','Critical','High severity','Global Administrator','break-glass','Sev1')
$FreshFrom       = @('<support@yourdomain.freshservice.com>','@freshservice.com')
$MicrosoftFrom   = @('o365mc@microsoft.com','msonlineservicesteam@microsoftonline.com','azure-noreply@microsoft.com','microsoft-noreply@microsoft.com','@microsoft.com')
$SecToolsFrom    = @('@arcticwolf.com','@proofpoint.com','@zscaler.com','@pphosted.com')
$AwsFrom         = @('@amazon.com','@aws.amazon.com')
$MigrationFrom   = @('@bittitan.com','@sharegate.com','@migrationwiz.com')
$DealCodes       = @()    # e.g. 'DEAL-01'; one Acquisitions\<code> folder and rule per code

$Folders = @(
    'Needs attention','Waiting',
    'Notifications','Notifications\Critical','Notifications\Microsoft','Notifications\Security tools',
    'Notifications\Freshservice','Notifications\AWS','Notifications\Migration tools',
    'Vendors & newsletters','Acquisitions'
) + @($DealCodes | ForEach-Object { "Acquisitions\$_" })

# ---- 1. Folders via Graph (own mailbox) ----
if (-not $SkipFolders) {
    Import-Module Microsoft.Graph.Authentication, Microsoft.Graph.Mail -ErrorAction Stop
    Connect-MgGraph -Scopes 'Mail.ReadWrite' -NoWelcome
    $me = 'me'
    $inboxId = (Get-MgUserMailFolder -UserId $me -Filter "displayName eq 'Inbox'").Id
    function New-FolderPath([string]$Path) {
        $parentId = $inboxId
        foreach ($name in ($Path -split '\\')) {
            $existing = Get-MgUserMailFolderChildFolder -UserId $me -MailFolderId $parentId -All | Where-Object DisplayName -eq $name
            if (-not $existing) {
                if (-not $PSCmdlet.ShouldProcess("Inbox\$Path", 'Create folder')) { return }
                $existing = New-MgUserMailFolderChildFolder -UserId $me -MailFolderId $parentId -BodyParameter @{ displayName = $name }
                Write-Host "created  Inbox\$Path"
            }
            $parentId = $existing.Id
        }
    }
    foreach ($f in $Folders) { New-FolderPath $f }
}

# ---- 2. Rules via Exchange Online, in priority order ----
Import-Module ExchangeOnlineManagement -ErrorAction Stop
Connect-ExchangeOnline -ShowBanner:$false
$mbx = if ($Mailbox) { $Mailbox } else { (Get-ConnectionInformation | Select-Object -First 1).UserPrincipalName }
$existingRules = @((Get-InboxRule -Mailbox $mbx).Name)
$script:prio = 0
function Add-Rule([string]$Name, [hashtable]$Params) {
    $script:prio++
    if ($existingRules -contains $Name) { Write-Host "exists   $Name"; return }
    if ($PSCmdlet.ShouldProcess($Name, 'Create inbox rule')) {
        New-InboxRule -Mailbox $mbx -Name $Name -Priority $script:prio -StopProcessingRules $true @Params | Out-Null
        Write-Host "created  $Name (priority $script:prio)"
    }
}

Add-Rule '01 Critical alerts' @{ FromAddressContainsWords = $CriticalFrom; SubjectContainsWords = $CriticalSubject; MoveToFolder = "${mbx}:\Inbox\Notifications\Critical"; MarkImportance = 'High'; MarkAsRead = $false }
Add-Rule '02 VIPs'            @{ From = $VIPs; ApplyCategory = 'VIP' }
foreach ($code in $DealCodes) {
    Add-Rule "03 Deal $code"  @{ SubjectContainsWords = @($code); MoveToFolder = "${mbx}:\Inbox\Acquisitions\$code" }
}
Add-Rule '04 Freshservice'    @{ FromAddressContainsWords = $FreshFrom;     MoveToFolder = "${mbx}:\Inbox\Notifications\Freshservice" }
Add-Rule '05 Microsoft'       @{ FromAddressContainsWords = $MicrosoftFrom; MoveToFolder = "${mbx}:\Inbox\Notifications\Microsoft" }
Add-Rule '06 Security tools'  @{ FromAddressContainsWords = $SecToolsFrom;  MoveToFolder = "${mbx}:\Inbox\Notifications\Security tools" }
Add-Rule '07 AWS'             @{ FromAddressContainsWords = $AwsFrom;       MoveToFolder = "${mbx}:\Inbox\Notifications\AWS" }
Add-Rule '08 Migration tools' @{ FromAddressContainsWords = $MigrationFrom; MoveToFolder = "${mbx}:\Inbox\Notifications\Migration tools" }
Add-Rule '09 Bulk'            @{ HeaderContainsWords = @('List-Unsubscribe'); MoveToFolder = "${mbx}:\Inbox\Vendors & newsletters" }

Get-InboxRule -Mailbox $mbx | Sort-Object Priority | Format-Table Priority, Name, Enabled -AutoSize
Disconnect-ExchangeOnline -Confirm:$false
