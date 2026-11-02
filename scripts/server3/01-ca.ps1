# Server3 - step 1: Certification Authority
#   - Enterprise Root CA for the domain
#   - Web Enrollment, reachable via http://<FQDN server3>/CertSrv
#
# Prerequisites: base + domain join done.
# An Enterprise CA must be configured by an Enterprise Admin: the local vagrant
# user isn't one, so the domain Administrator credentials from the config are used.
# Safe to run multiple times.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
. "$PSScriptRoot\..\common\domain-admin.ps1"
$cfg  = Get-LabConfig
$ca   = $cfg.Ca
$cred = Get-DomainAdminCredential -Config $cfg

Write-Host "=== CA: $($ca.CommonName) ==="

$features = 'ADCS-Cert-Authority', 'ADCS-Web-Enrollment'
$missing  = $features | Where-Object { -not (Get-WindowsFeature $_).Installed }
if ($missing) {
    Write-Host "Installing $($missing -join ', ')"
    Install-WindowsFeature $missing -IncludeManagementTools | Out-Null
}

# --- Enterprise Root CA ------------------------------------------------------
# A configured CA has an Active entry under CertSvc\Configuration.
$caConfig = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration' -ErrorAction SilentlyContinue
if (-not $caConfig.Active) {
    Write-Host "Configuring $($ca.Type) $($ca.CommonName) ($($ca.ValidityYears) years)"
    Install-AdcsCertificationAuthority `
        -CAType $ca.Type `
        -CACommonName $ca.CommonName `
        -KeyLength 2048 `
        -HashAlgorithmName SHA256 `
        -ValidityPeriod Years `
        -ValidityPeriodUnits $ca.ValidityYears `
        -Credential $cred `
        -Force | Out-Null
}
else {
    Write-Host "CA already configured: $($caConfig.Active)"
}

# --- Web Enrollment ----------------------------------------------------------
# Configured = the CertSrv application exists in IIS. appcmd writes its
# "not found" error to normal output, so look for an actual APP line.
$appcmd = "$env:windir\System32\inetsrv\appcmd.exe"
if (-not (& $appcmd list app 2>$null | Select-String '^APP "Default Web Site/CertSrv"')) {
    Write-Host 'Configuring Web Enrollment (/CertSrv)'
    Install-AdcsWebEnrollment -Force | Out-Null
}

# Windows Server 2025 makes /CertSrv require HTTPS by default (403.4), as
# protection against NTLM relay attacks on Web Enrollment (ESC8). The
# assignment asks for http://<FQDN>/CertSrv, so the requirement is removed
# for this one application - a deliberate trade-off, documented in the readme.
$sslFlags = & $appcmd list config 'Default Web Site/CertSrv' /section:access 2>$null
if ($sslFlags -match 'sslFlags="Ssl') {
    Write-Host 'Allowing HTTP for /CertSrv (Server 2025 default: HTTPS only)'
    & $appcmd set config 'Default Web Site/CertSrv' /section:access /sslFlags:None /commit:apphost | Out-Null
}

# --- Test --------------------------------------------------------------------
# Locally via localhost: NTLM to the machine's own FQDN is blocked by the
# loopback check. Via the FQDN is tested from the client/host.
$response = Invoke-WebRequest -Uri 'http://localhost/certsrv/' -UseDefaultCredentials -UseBasicParsing
if ($response.Content -notmatch 'Microsoft Active Directory Certificate Services') {
    throw '/CertSrv does not return the Web Enrollment page'
}
$fqdn = "$($cfg.Nodes.server3.Hostname).$($cfg.Domain.Name)"
Write-Host "/CertSrv -> HTTP $($response.StatusCode), Web Enrollment OK (http://$fqdn/CertSrv)"

# The CA puts its own root certificate in the Trusted Root store
$cert = Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like "CN=$($ca.CommonName)*" | Select-Object -First 1
if (-not $cert) { throw "Root certificate CN=$($ca.CommonName) not found" }
Write-Host "Root certificate: $($cert.Subject), valid until $($cert.NotAfter.ToString('yyyy-MM-dd'))"

Write-Host '=== CA done ==='
