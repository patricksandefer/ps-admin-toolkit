<#
.SYNOPSIS
    Adds a user to a Conditional Access exception group for a bounded window and records the expiry
    (runbook Workflow 3: travel exceptions; also USB exceptions and the admin Zscaler bypass).
.DESCRIPTION
    Works for both the interactive emergency path and the Azure Automation runbook (Freshservice calls
    the runbook's webhook). Expiry rows are kept in an Azure Table (default) or a local JSON file
    (-Store Local, for testing) and enforced by Remove-ExpiredGroupMembers.ps1 every hour.
.PARAMETER UserPrincipalName   The user to add
.PARAMETER StartDate           When membership begins (today or future)
.PARAMETER EndDate             When membership ends; max 30 days after StartDate
.PARAMETER GroupName           Exception group. Default sg-ca-travel-exception
.PARAMETER TicketId            Freshservice ticket number for the audit trail (optional)
.PARAMETER Store               'AzureTable' (default) or 'Local'
.PARAMETER StorageAccount      Storage account name holding table 'groupexpiry' (AzureTable store)
.PARAMETER LocalStorePath      JSON file path for the Local store (default C:\Admin\group-expiry.json)
.PARAMETER Identity            Use the Automation managed identity instead of interactive sign-in
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$UserPrincipalName,
    [Parameter(Mandatory)][datetime]$StartDate,
    [Parameter(Mandatory)][datetime]$EndDate,
    [string]$GroupName = 'sg-ca-travel-exception',
    [string]$TicketId = '',
    [ValidateSet('AzureTable','Local')][string]$Store = 'AzureTable',
    [string]$StorageAccount = '',
    [string]$LocalStorePath = 'C:\Admin\group-expiry.json',
    [switch]$Identity
)

if (($EndDate - $StartDate).TotalDays -gt 30) { throw 'Max 30 days; split the request.' }
if ($EndDate -le (Get-Date)) { throw 'EndDate is in the past.' }

Import-Module Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Users
if ($Identity) { Connect-MgGraph -Identity -NoWelcome }
elseif (-not (Get-MgContext)) { Connect-MgGraph -Scopes 'GroupMember.ReadWrite.All','User.Read.All' -UseDeviceCode -NoWelcome }   # reuse Connect-Admin session if present

$group = Get-MgGroup -Filter "displayName eq '$GroupName'"
$user  = Get-MgUser  -UserId $UserPrincipalName
if (-not $group) { throw "Group not found: $GroupName" }

$row = [ordered]@{
    PartitionKey = $GroupName
    RowKey       = "$($user.Id)-$($EndDate.ToString('yyyyMMddHHmm'))"
    Upn          = $UserPrincipalName
    UserId       = $user.Id
    Start        = $StartDate.ToString('o')
    End          = $EndDate.ToString('o')
    Ticket       = $TicketId
    AddedBy      = if ($Identity) { 'automation' } else { (Get-MgContext).Account }
}

# 1. Add now if the window has started (otherwise the hourly cleanup adds on StartDate)
if ((Get-Date) -ge $StartDate -and $PSCmdlet.ShouldProcess("$UserPrincipalName -> $GroupName", 'Add member')) {
    New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction SilentlyContinue
    Write-Output "Added $UserPrincipalName to $GroupName until $EndDate"
} else {
    Write-Output "Scheduled $UserPrincipalName for $GroupName from $StartDate until $EndDate"
}

# 2. Record the expiry
if ($Store -eq 'AzureTable') {
    Import-Module Az.Accounts, Az.Storage, AzTable
    if ($Identity) { Connect-AzAccount -Identity | Out-Null }
    $ctx = (Get-AzStorageAccount | Where-Object StorageAccountName -eq $StorageAccount).Context
    if (-not $ctx) { throw "Storage account not found: $StorageAccount" }
    $table = (Get-AzStorageTable -Name 'groupexpiry' -Context $ctx -ErrorAction SilentlyContinue) ?? (New-AzStorageTable -Name 'groupexpiry' -Context $ctx)
    $props = @{}; foreach ($k in 'Upn','UserId','Start','End','Ticket','AddedBy') { $props[$k] = $row[$k] }
    Add-AzTableRow -Table $table.CloudTable -PartitionKey $row.PartitionKey -RowKey $row.RowKey -Property $props -UpdateExisting | Out-Null
} else {
    $all = if (Test-Path $LocalStorePath) { @(Get-Content $LocalStorePath -Raw | ConvertFrom-Json) } else { @() }
    $all = @($all | Where-Object RowKey -ne $row.RowKey) + [pscustomobject]$row
    $all | ConvertTo-Json -Depth 4 | Set-Content $LocalStorePath
}
Write-Output "Expiry recorded ($Store)."
