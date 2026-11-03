# Remediate-SmartAppControl.ps1 - sets Smart App Control to Off. Runs as SYSTEM. Idempotent.
# Only ever moves 1/2 -> 0; never sets 1. Takes effect after the next restart (not forced here).
$key = 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy'
$state = (Get-ItemProperty -Path $key -Name VerifiedAndReputablePolicyState -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
if ($null -eq $state -or $state -eq 0) { Write-Output 'Nothing to do'; exit 0 }
try {
    Set-ItemProperty -Path $key -Name VerifiedAndReputablePolicyState -Value 0 -Type DWord -ErrorAction Stop
    $now = (Get-ItemProperty -Path $key -Name VerifiedAndReputablePolicyState).VerifiedAndReputablePolicyState
    if ($now -eq 0) { Write-Output 'SAC set to Off; takes effect after next restart'; exit 0 }
    Write-Output "Write did not stick (state $now)"; exit 1
} catch { Write-Output "Failed: $_"; exit 1 }
