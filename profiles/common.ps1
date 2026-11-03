# common.ps1 - shared prompt helpers, dot-sourced by both the daily and admin profiles.
# Lives beside each profile: Documents\PowerShell\common.ps1

function global:Import-ToolkitSettings {
    <#
    .SYNOPSIS  Loads settings.local.ps1 (real values, never committed) if present.
    .NOTES     Looks in C:\Admin\Toolkit\settings first, then beside the profile.
    #>
    $candidates = @(
        'C:\Admin\Toolkit\settings\settings.local.ps1',
        (Join-Path (Split-Path $PROFILE) 'settings.local.ps1')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { . $c; return $c }
    }
    return $null
}

function global:Get-LastCommandDuration {
    $h = Get-History -Count 1 -ErrorAction SilentlyContinue
    if (-not $h) { return '' }
    $ts = $h.EndExecutionTime - $h.StartExecutionTime
    if ($ts.TotalMinutes -ge 1) { return ('{0}m {1:00}s' -f [int]$ts.TotalMinutes, $ts.Seconds) }
    if ($ts.TotalSeconds -ge 1) { return ('{0:n1}s' -f $ts.TotalSeconds) }
    return ('{0}ms' -f [int]$ts.TotalMilliseconds)
}

function global:Get-CloudContextLine {
    $parts = @()
    if (-not $global:ProdTenants) { $global:ProdTenants = @{} }

    if (Get-Command Get-MgContext -ErrorAction SilentlyContinue) {
        $mg = Get-MgContext -ErrorAction SilentlyContinue
        if ($mg) {
            $name  = ($global:ProdTenants.GetEnumerator() | Where-Object Value -eq $mg.TenantId | Select-Object -First 1).Key
            $label = if ($name) { "MG:$($mg.Account)@$name" } else { "MG:$($mg.Account)@$($mg.TenantId.Substring(0,8))" }
            $parts += [pscustomobject]@{ Text = $label; Prod = [bool]$name }
        }
    }
    if (Get-Command Get-AzContext -ErrorAction SilentlyContinue) {
        $az = Get-AzContext -ErrorAction SilentlyContinue
        if ($az) { $parts += [pscustomobject]@{ Text = "AZ:$($az.Subscription.Name)"; Prod = ($az.Subscription.Name -match 'prod|platform') } }
    }
    if (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) {
        $exo = Get-ConnectionInformation -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exo) { $parts += [pscustomobject]@{ Text = "EXO:$($exo.Organization)"; Prod = $true } }
    }
    return $parts
}

function global:Invoke-Timed {
    param([Parameter(Mandatory)][scriptblock]$Script)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { & $Script }
    finally {
        $sw.Stop()
        Write-Host ("[{0}] took {1}" -f (Get-Date -Format 'HH:mm:ss'), $sw.Elapsed) -ForegroundColor DarkCyan
    }
}
