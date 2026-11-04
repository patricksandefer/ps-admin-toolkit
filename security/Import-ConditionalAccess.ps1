<#
.SYNOPSIS
    Creates Conditional Access policies from JSON files exported by Export-ConditionalAccess.ps1,
    always in REPORT-ONLY state, so nothing is enforced by accident (runbook D2).
.DESCRIPTION
    Strips the read-only fields (id, timestamps) from each file and posts it. Policies whose
    display name already exists in the tenant are skipped. Group and user object IDs inside the
    JSON must exist in the target tenant; use -Map to translate them when moving between tenants.
.PARAMETER Path   A JSON file or a folder of JSON files
.PARAMETER Map    Optional hashtable of old-id => new-id for groups/users/named locations
.EXAMPLE
    .\Import-ConditionalAccess.ps1 -Path C:\Admin\CA
    .\Import-ConditionalAccess.ps1 -Path .\CA-ADM-01.json -Map @{ '<old-group-id>' = '<new-group-id>' }
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Path,
    [hashtable]$Map = @{}
)

Import-Module Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns
# Reuse an existing Graph session (e.g. from Connect-Admin); otherwise sign in with device code.
if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes 'Policy.ReadWrite.ConditionalAccess','Policy.Read.All' -UseDeviceCode -NoWelcome
}
$existing = (Get-MgIdentityConditionalAccessPolicy -All).DisplayName

$files = if (Test-Path $Path -PathType Container) { Get-ChildItem $Path -Filter *.json } else { Get-Item $Path }
foreach ($f in $files) {
    $raw = Get-Content $f.FullName -Raw
    foreach ($k in $Map.Keys) { $raw = $raw.Replace($k, $Map[$k]) }
    $p = $raw | ConvertFrom-Json -AsHashtable
    foreach ($drop in 'id','createdDateTime','modifiedDateTime','templateId','Id','CreatedDateTime','ModifiedDateTime','TemplateId','AdditionalProperties') { $null = $p.Remove($drop) }
    $p.state = 'enabledForReportingButNotEnforced'
    if ($existing -contains $p.displayName) { Write-Host "skip      $($p.displayName) (exists)"; continue }
    if ($PSCmdlet.ShouldProcess($p.displayName, 'Create CA policy (report-only)')) {
        try {
            $null = New-MgIdentityConditionalAccessPolicy -BodyParameter $p
            Write-Host "created   $($p.displayName) [report-only]"
        } catch { Write-Warning "Failed $($f.Name): $_" }
    }
}
Disconnect-MgGraph | Out-Null
