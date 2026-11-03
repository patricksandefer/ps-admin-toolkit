<#
.SYNOPSIS
    Signs every .ps1/.psm1/.psd1 under -Path that is unsigned or whose signature is stale (runbook P4.4).
    Run from the admin session with the code-signing certificate in Cert:\CurrentUser\My.
.PARAMETER Path        Folder to sign. Default: the repo root this script lives in.
.PARAMETER Thumbprint  Thumbprint of the code-signing cert. Omit to use the only code-signing cert present.
.PARAMETER TimestampServer  RFC 3161 timestamp URL so signatures outlive the certificate.
.NOTES
    For Azure Trusted Signing, replace the Set-AuthenticodeSignature call with Invoke-TrustedSigning
    from the TrustedSigning module (same loop, same timestamp behaviour).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Path = (Split-Path $PSScriptRoot -Parent),
    [string]$Thumbprint = '',
    [string]$TimestampServer = 'http://timestamp.digicert.com'
)

$cert = if ($Thumbprint) { Get-Item "Cert:\CurrentUser\My\$Thumbprint" }
        else { Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1 }
if (-not $cert) { throw 'No code-signing certificate in Cert:\CurrentUser\My' }
if ($cert.NotAfter -lt (Get-Date).AddDays(30)) { Write-Warning "Certificate expires $($cert.NotAfter); renew soon." }

$files = Get-ChildItem -Path $Path -Recurse -Include *.ps1,*.psm1,*.psd1 -File | Where-Object FullName -notmatch '\\\.git\\'
$signed = 0; $skipped = 0; $failed = 0
foreach ($f in $files) {
    $sig = Get-AuthenticodeSignature -FilePath $f.FullName
    if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Thumbprint -eq $cert.Thumbprint) { $skipped++; continue }
    if (-not $PSCmdlet.ShouldProcess($f.FullName, 'Sign')) { continue }
    $r = Set-AuthenticodeSignature -FilePath $f.FullName -Certificate $cert -HashAlgorithm SHA256 -TimestampServer $TimestampServer -IncludeChain All
    if ($r.Status -eq 'Valid') { $signed++; Write-Host "signed  $($f.FullName)" }
    else { $failed++; Write-Warning "FAILED $($f.FullName): $($r.StatusMessage)" }
}
"Signed $signed, already valid $skipped, failed $failed"
if ($failed) { exit 1 }
