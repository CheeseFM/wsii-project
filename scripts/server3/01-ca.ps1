# Server3 - step 1: Certification Authority
#   - Enterprise Root CA for the domain
#   - Web Enrollment, reachable via http://<FQDN server3>/CertSrv
#
# Prerequisites: base + domain join done.
# An Enterprise CA must be installed by a domain (Enterprise) admin: the local
# vagrant user isn't one, so use the domain Administrator credentials from the config.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
$cfg = Get-LabConfig
$ca  = $cfg.Ca

Write-Host "=== CA: $($ca.CommonName) ==="

# TODO: credentials for <NetBiosName>\Administrator from $cfg.Domain

# TODO: install ADCS-Cert-Authority + ADCS-Web-Enrollment if not installed yet

# TODO: configure the CA if not configured yet
#       (Install-AdcsCertificationAuthority -CAType $ca.Type -CACommonName ...
#        -ValidityPeriod Years -ValidityPeriodUnits $ca.ValidityYears -Credential ...)

# TODO: configure Web Enrollment if not configured yet (Install-AdcsWebEnrollment)

# TODO: test: Invoke-WebRequest http://<FQDN server3>/CertSrv (needs Windows authentication)

Write-Host '=== CA done ==='
