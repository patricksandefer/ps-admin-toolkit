<#
.SYNOPSIS
    Hourly enforcement for Add-GroupMemberWithExpiry.ps1: adds members whose window has started,
    removes members whose window has ended, and flags members with no expiry record (manual adds).
.PARAMETER Store            'AzureTable' (default) or 'Local'
.PARAMETER StorageAccount   Storage account holding table 'groupexpiry'
.PARAMETER LocalStorePath   JSON path for the Local store
.PARAMETER Identity         Use the Automation managed identity
.PARAMETER RemoveUntracked  Also remove group members that have no expiry row (default: report only)
.NOTES
    Schedule in Azure Automation hourly. Optionally POST a note to the Freshservice ticket on removal
    (see the commented block) using an API key stored as an encrypted Automation variable.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('AzureTable','Local')][string]$Store = 'AzureTable',
    [string]$StorageAccount = '',
    [string]$LocalStorePath = 'C:\Admin\group-expiry.json',
    [switch]$Identity,
    [switch]$RemoveUntracked
)

Import-Module Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Users
if ($Identity) { Connect-MgGraph -Identity -NoWelcome }
elseif (-not (Get-MgContext)) { Connect-MgGraph -Scopes 'GroupMember.ReadWrite.All','User.Read.All' -UseDeviceCode -NoWelcome }   # reuse Connect-Admin session if present

# Load rows
if ($Store -eq 'AzureTable') {
    Import-Module Az.Accounts, Az.Storage, AzTable
    if ($Identity) { Connect-AzAccount -Identity | Out-Null }
    $ctx   = (Get-AzStorageAccount | Where-Object StorageAccountName -eq $StorageAccount).Context
    $table = (Get-AzStorageTable -Name 'groupexpiry' -Context $ctx).CloudTable
    $rows  = Get-AzTableRow -Table $table
} else {
    $rows = if (Test-Path $LocalStorePath) { @(Get-Content $LocalStorePath -Raw | ConvertFrom-Json) } else { @() }
}

$now = Get-Date
$groups = $rows | Select-Object -ExpandProperty PartitionKey -Unique
foreach ($gName in $groups) {
    $group = Get-MgGroup -Filter "displayName eq '$gName'"
    if (-not $group) { Write-Warning "Group missing: $gName"; continue }
    $members = @(Get-MgGroupMember -GroupId $group.Id -All | Select-Object -ExpandProperty Id)
    $gRows   = @($rows | Where-Object PartitionKey -eq $gName)

    foreach ($r in $gRows) {
        $start = [datetime]$r.Start; $end = [datetime]$r.End
        if ($now -ge $start -and $now -lt $end -and $members -notcontains $r.UserId) {
            if ($PSCmdlet.ShouldProcess("$($r.Upn) -> $gName", 'Add (window started)')) {
                New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $r.UserId -ErrorAction SilentlyContinue
                Write-Output "added    $($r.Upn) to $gName (ticket $($r.Ticket))"
            }
        }
        if ($now -ge $end) {
            if ($PSCmdlet.ShouldProcess("$($r.Upn) -> $gName", 'Remove (expired)')) {
                if ($members -contains $r.UserId) { Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $r.UserId -ErrorAction SilentlyContinue }
                if ($Store -eq 'AzureTable') { Remove-AzTableRow -Table $table -PartitionKey $r.PartitionKey -RowKey $r.RowKey | Out-Null }
                else { $rows = @($rows | Where-Object RowKey -ne $r.RowKey) }
                Write-Output "removed  $($r.Upn) from $gName (ticket $($r.Ticket))"
                # Optional Freshservice note:
                # $fs = Get-AutomationVariable -Name 'FreshserviceApiKey'; $dom = Get-AutomationVariable -Name 'FreshserviceDomain'
                # Invoke-RestMethod -Method Post -Uri "https://$dom.freshservice.com/api/v2/tickets/$($r.Ticket)/notes" `
                #   -Headers @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${fs}:X")) } `
                #   -ContentType 'application/json' -Body (@{ body = "Exception expired; $($r.Upn) removed from $gName"; private = $true } | ConvertTo-Json)
            }
        }
    }

    # Members with no expiry record = someone added them by hand
    $tracked = @($gRows | Select-Object -ExpandProperty UserId)
    foreach ($m in $members | Where-Object { $tracked -notcontains $_ }) {
        $upn = (Get-MgUser -UserId $m -ErrorAction SilentlyContinue).UserPrincipalName
        if ($RemoveUntracked -and $PSCmdlet.ShouldProcess("$upn -> $gName", 'Remove (no expiry record)')) {
            Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $m -ErrorAction SilentlyContinue
            Write-Warning "removed untracked member $upn from $gName"
        } else {
            Write-Warning "UNTRACKED member in ${gName}: $upn (no expiry row - manual add?)"
        }
    }
}
if ($Store -eq 'Local') { $rows | ConvertTo-Json -Depth 4 | Set-Content $LocalStorePath }
