# Server1 - step 5: GPO so every machine trusts the CA
#   - root certificate of the CA on server3 in Trusted Root Certification
#     Authorities on all servers and the client
#
# Run only AFTER the CA on server3 is installed:
#   vagrant provision server1 --provision-with ca-gpo

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
$cfg = Get-LabConfig
$ca  = $cfg.Ca

Write-Host "=== GPO: trust $($ca.CommonName) ==="

# TODO: get the root certificate of $ca.CommonName
#       (published in AD by the Enterprise CA, or via certutil -ca.cert on server3)

# TODO: create GPO $ca.GpoName if it doesn't exist yet and link it to the domain

# TODO: add the root certificate to the GPO under
#       Computer Configuration > Windows Settings > Security Settings >
#       Public Key Policies > Trusted Root Certification Authorities

# TODO: test: gpupdate /force + certificate visible in Cert:\LocalMachine\Root

Write-Host '=== GPO done ==='
