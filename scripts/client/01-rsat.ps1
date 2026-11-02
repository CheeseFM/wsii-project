# Client - step 1: RSAT tools
#   - only the tools needed for the demo:
#     AD, DNS, DHCP, Certificate Services, Group Policy Management
#
# Prerequisites: base + domain join done, IP received via DHCP (server3).
# RSAT is a Windows "capability" downloaded via Windows Update (internet via NAT).

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
$cfg = Get-LabConfig

Write-Host '=== RSAT tools ==='

# TODO: list of capabilities, e.g.
#       Rsat.ActiveDirectory.DS-LDS.Tools, Rsat.Dns.Tools, Rsat.DHCP.Tools,
#       Rsat.CertificateServices.Tools, Rsat.GroupPolicy.Management.Tools

# TODO: install each one that isn't installed yet (Get-WindowsCapability -Online / Add-WindowsCapability)

# TODO: check: host-only IP in .100 - .150, CA root certificate in Cert:\LocalMachine\Root

Write-Host '=== RSAT tools done ==='
