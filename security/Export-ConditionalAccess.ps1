<#
.SYNOPSIS
    Exports every Conditional Access policy to one JSON file each (runbook D1 / B2 "before" picture).
.PARAMETER OutDir   Folder for the JSON files. Default C:\Admin\CA
.NOTES   Re-import with Import-ConditionalAccess.ps1. Needs Policy.Read.All (Security Reader / Global Reader).
#>
[CmdletBinding()]
param([string]$OutDir = 'C:\Admin\CA')

Import-Module Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns
Connect-MgGraph -Scopes 'Policy.Read.All' -NoWelcome
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$policies = Get-MgIdentityConditionalAccessPolicy -All
foreach ($p in $policies) {
    $name = $p.DisplayName -replace '[^\w\- ]', '_'
    $path = Join-Path $OutDir "$name.json"
    $p | ConvertTo-Json -Depth 20 | Set-Content $path
    Write-Host ("{0,-50} {1,-32} -> {2}" -f $p.DisplayName, $p.State, $path)
}
Write-Host "Exported $($policies.Count) policies to $OutDir"
Disconnect-MgGraph | Out-Null
