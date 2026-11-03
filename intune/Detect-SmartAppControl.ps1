# Detect-SmartAppControl.ps1 - Intune Remediations detection. exit 1 = needs remediation, exit 0 = compliant. Runs as SYSTEM.
# VerifiedAndReputablePolicyState: 0 = off, 1 = on, 2 = evaluation (device may switch itself to enforcing).
$key = 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy'
$state = (Get-ItemProperty -Path $key -Name VerifiedAndReputablePolicyState -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
if ($null -eq $state) { Write-Output 'SAC not present (older build)'; exit 0 }
if ($state -eq 0)     { Write-Output 'SAC off';                     exit 0 }
Write-Output "SAC state $state (1=on, 2=evaluation); remediation needed"
exit 1
