# Server3 - step 2: DHCP
#   - DHCP role, authorized in AD
#   - scope .100 - .200 with exclusion .151 - .200
#   - options: 006 DNS servers + 015 DNS domain name, no 003 router (no uplink)
#   - DHCP doesn't register DNS records for clients
#
# Prerequisites: base + domain join done.
# Authorizing in AD requires a domain admin (see 01-ca.ps1).

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
$cfg  = Get-LabConfig
$dhcp = $cfg.Dhcp
$me   = $cfg.Nodes.server3

Write-Host "=== DHCP: scope $($dhcp.StartRange) - $($dhcp.EndRange) ==="

# TODO: install DHCP role if not installed yet

# TODO: DHCP security groups (netsh dhcp add securitygroups) + restart service,
#       and clear the Server Manager "configuration required" notification

# TODO: authorize in AD with domain admin credentials, if not authorized yet
#       (Add-DhcpServerInDC -DnsName <FQDN> -IPAddress $me.IP)

# TODO: bind DHCP only to the host-only adapter, never to NAT

# TODO: scope if it doesn't exist yet ($dhcp.StartRange/EndRange/SubnetMask/LeaseDuration)

# TODO: exclusion range $dhcp.ExclusionStart - $dhcp.ExclusionEnd

# TODO: options: 006 = primary + secondary DNS IP, 015 = $cfg.Domain.Name
#       (no 003 router: the host-only network has no uplink)

# TODO: no DNS registration for clients (Set-DhcpServerv4DnsSetting -DynamicUpdates Never)

Write-Host '=== DHCP done ==='
