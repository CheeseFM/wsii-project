# Join a VM to the domain (server2, server3, client)
#
# Safe to run multiple times: does nothing if already a domain member.
# Requires a reboot afterwards (Vagrant does this via reboot: true). Unlike the
# DC promotion, the local vagrant account keeps working until that reboot.
# Usage: C:\vagrant\common\join-domain.ps1 -Node server2

param(
    [Parameter(Mandatory)]
    [ValidateSet('server2', 'server3', 'client')]
    [string]$Node
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\domain-admin.ps1"
$cfg     = Get-LabConfig
$zone    = $cfg.Domain.Name
$primary = $cfg.Nodes[$cfg.Dns.PrimaryNode].IP

Write-Host "=== Domain join: $Node -> $zone ==="

$computer = Get-CimInstance Win32_ComputerSystem
if ($computer.PartOfDomain -and $computer.Domain -eq $zone) {
    Write-Host "Already a member of $zone, nothing to do"
    return
}

# The join finds the domain controller via DNS (SRV records on server1).
for ($i = 1; -not (Resolve-DnsName "_ldap._tcp.dc._msdcs.$zone" -Type SRV -Server $primary -ErrorAction SilentlyContinue); $i++) {
    if ($i -gt 30) { throw "Domain $zone not resolvable via $primary after 5 minutes" }
    Write-Host "Waiting for $zone via DNS server $primary..."
    Start-Sleep -Seconds 10
}

# Joining requires domain credentials: the local vagrant user has no rights in AD.
Write-Host "Joining $env:COMPUTERNAME to $zone"
Add-Computer -DomainName $zone -Credential (Get-DomainAdminCredential -Config $cfg) -Force

Write-Host '=== Domain join done, reboot required ==='
