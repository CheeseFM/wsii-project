# Server1 - step 5: GPO so every machine trusts the CA
#   - root certificate of the CA on server3 in Trusted Root Certification
#     Authorities on all servers and the client, via a GPO linked to the domain
#
# Run only AFTER the CA on server3 is installed:
#   vagrant provision server1 --provision-with ca-gpo
# Creating GPOs requires a domain admin (see common\domain-admin.ps1).
# Safe to run multiple times.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
. "$PSScriptRoot\..\common\domain-admin.ps1"
$cfg = Get-LabConfig
$ca  = $cfg.Ca

Write-Host "=== GPO: trust $($ca.CommonName) ==="

Invoke-AsDomainAdmin -Config $cfg -Parameters @{ GpoName = $ca.GpoName; CaName = $ca.CommonName } -ScriptBlock {
    Import-Module ActiveDirectory, GroupPolicy

    # --- Root certificate from AD -------------------------------------------
    # An Enterprise CA publishes its certificate under Public Key Services in
    # the configuration partition, so server3 doesn't have to be contacted.
    $configNc = (Get-ADRootDSE).configurationNamingContext
    $caObject = Get-ADObject -SearchBase "CN=Certification Authorities,CN=Public Key Services,CN=Services,$configNc" `
        -Filter "Name -eq '$CaName'" -Properties cACertificate
    if (-not $caObject) { throw "CA $CaName not found in AD: is the CA on server3 installed?" }
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(, [byte[]]$caObject.cACertificate[0])
    $thumb = $cert.Thumbprint
    Write-Output "Root certificate: $($cert.Subject) ($thumb)"

    # --- Certificate in the format Group Policy expects ---------------------
    # A GPO stores trusted root certificates as a registry value 'Blob' in
    # Windows' own serialized format (not plain DER). Importing the
    # certificate locally makes Windows create exactly that Blob.
    $certFile = "$env:TEMP\$thumb.cer"
    [IO.File]::WriteAllBytes($certFile, $cert.RawData)
    Import-Certificate -FilePath $certFile -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    $blob = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\SystemCertificates\ROOT\Certificates\$thumb").Blob

    # --- GPO, linked to the domain ------------------------------------------
    $domainDn = (Get-ADDomain).DistinguishedName
    if (-not (Get-GPO -Name $GpoName -ErrorAction SilentlyContinue)) {
        Write-Output "Creating GPO '$GpoName'"
        New-GPO -Name $GpoName -Comment "Trusted root certificate of $CaName" | Out-Null
    }
    if ((Get-GPInheritance -Target $domainDn).GpoLinks.DisplayName -notcontains $GpoName) {
        Write-Output "Linking GPO to $domainDn"
        New-GPLink -Name $GpoName -Target $domainDn | Out-Null
    }

    # Computer Configuration > Windows Settings > Security Settings >
    # Public Key Policies > Trusted Root Certification Authorities
    $key = "HKLM\SOFTWARE\Policies\Microsoft\SystemCertificates\Root\Certificates\$thumb"
    $current = Get-GPRegistryValue -Name $GpoName -Key $key -ValueName Blob -ErrorAction SilentlyContinue
    if (-not $current) {
        Write-Output "Adding certificate to GPO (Trusted Root Certification Authorities)"
        Set-GPRegistryValue -Name $GpoName -Key $key -ValueName Blob -Type Binary -Value $blob | Out-Null
    }

    # --- Check on server1 itself --------------------------------------------
    gpupdate /target:computer /force | Out-Null
    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\SystemCertificates\Root\Certificates\$thumb")) {
        throw 'Certificate not applied by the GPO on server1 after gpupdate'
    }
    Write-Output "GPO applied on ${env:COMPUTERNAME}: certificate in the policy Root store"
}

Write-Host '=== GPO done ==='
