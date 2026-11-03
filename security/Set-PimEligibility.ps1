<#
.SYNOPSIS
    Makes principals ELIGIBLE for Entra directory roles from a CSV (runbook Checklist A3), and optionally
    removes their standing (active) assignment afterwards.
.DESCRIPTION
    assignments.csv columns: Upn, Role       e.g.  adm.jane@example.com, Global Administrator
    Run the role SETTINGS (A2) in the portal first. Then:
      1. .\Set-PimEligibility.ps1 -Csv .\assignments.csv            # create eligible assignments
      2. test an activation end to end (A3 gate)
      3. .\Set-PimEligibility.ps1 -Csv .\assignments.csv -RemoveActive   # drop standing assignments
    Break-glass accounts must NOT be in the CSV.
.PARAMETER Csv            Path to the assignments CSV
.PARAMETER DurationDays   Eligibility length (default 365; re-reviewed by access review)
.PARAMETER RemoveActive   Also remove the active (standing) assignment for each row
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Csv,
    [int]$DurationDays = 365,
    [switch]$RemoveActive
)

Import-Module Microsoft.Graph.Authentication, Microsoft.Graph.Identity.Governance, Microsoft.Graph.Users
Connect-MgGraph -Scopes 'RoleManagement.ReadWrite.Directory','Directory.Read.All' -NoWelcome

$roles = Get-MgRoleManagementDirectoryRoleDefinition -All
$rows  = Import-Csv $Csv
foreach ($row in $rows) {
    $user = Get-MgUser -UserId $row.Upn -ErrorAction SilentlyContinue
    $role = $roles | Where-Object DisplayName -eq $row.Role
    if (-not $user) { Write-Warning "User not found: $($row.Upn)"; continue }
    if (-not $role) { Write-Warning "Role not found: $($row.Role)"; continue }

    if ($PSCmdlet.ShouldProcess("$($row.Upn) -> $($row.Role)", 'Create eligible assignment')) {
        $body = @{
            action           = 'adminAssign'
            principalId      = $user.Id
            roleDefinitionId = $role.Id
            directoryScopeId = '/'
            justification    = 'Checklist A3 eligibility per A2b assignment map'
            scheduleInfo     = @{ startDateTime = (Get-Date).ToUniversalTime(); expiration = @{ type = 'afterDuration'; duration = "P${DurationDays}D" } }
        }
        try {
            $res = New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -BodyParameter $body
            Write-Host ("eligible  {0,-40} {1,-35} {2}" -f $row.Upn, $row.Role, $res.Status)
        } catch { Write-Warning "Eligible failed for $($row.Upn)/$($row.Role): $_" }
    }

    if ($RemoveActive -and $PSCmdlet.ShouldProcess("$($row.Upn) -> $($row.Role)", 'Remove ACTIVE assignment')) {
        $body = @{ action='adminRemove'; principalId=$user.Id; roleDefinitionId=$role.Id; directoryScopeId='/'; justification='Converted to eligible (Checklist A3)' }
        try {
            $res = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $body
            Write-Host ("removed   {0,-40} {1,-35} {2}" -f $row.Upn, $row.Role, $res.Status)
        } catch { Write-Warning "Remove active failed for $($row.Upn)/$($row.Role): $_" }
    }
}
Disconnect-MgGraph | Out-Null
