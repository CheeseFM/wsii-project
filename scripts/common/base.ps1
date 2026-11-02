# Basic configuration for every VM:
#   - identify NAT and host-only adapter (by IP, not by name) and rename them
#   - host-only: static IP without default gateway (servers) or DHCP (client)
#   - DNS servers on the host-only adapter
#   - no DNS registration for the NAT adapter (and none at all for the client)
#   - hostname
#
# Safe to run multiple times: it only changes what isn't correct yet.
# Usage: C:\vagrant\common\base.ps1 -Node server1
# A hostname change requires a reboot (Vagrant does this via reboot: true).

param(
    [Parameter(Mandatory)]
    [ValidateSet('server1', 'server2', 'server3', 'client')]
    [string]$Node
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
$cfg = Get-LabConfig
$me  = $cfg.Nodes[$Node]

Write-Host "=== Base configuration for $Node ($($me.Hostname)) ==="

# --- Identify adapters -------------------------------------------------------
# The NAT adapter always gets a 10.0.2.x address from VirtualBox,
# the other connected adapter is the host-only one.
$natIndex = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object IPAddress -like $cfg.Network.NatSubnet).InterfaceIndex
$adapters = Get-NetAdapter -Physical | Where-Object Status -eq 'Up'
$nat      = $adapters | Where-Object ifIndex -eq $natIndex
$hostOnly = $adapters | Where-Object ifIndex -ne $natIndex

if (-not $nat -or @($hostOnly).Count -ne 1) {
    throw "Could not identify NAT and host-only adapter: $($adapters.Name -join ', ')"
}

# Clear names make the rest of the setup (and the demo) easier to follow.
if ($nat.Name -ne 'NAT')            { Rename-NetAdapter -Name $nat.Name -NewName 'NAT' }
if ($hostOnly.Name -ne 'Host-Only') { Rename-NetAdapter -Name $hostOnly.Name -NewName 'Host-Only' }
$natIdx = $nat.ifIndex
$hoIdx  = $hostOnly.ifIndex
Write-Host "NAT adapter: index $natIdx, host-only adapter: index $hoIdx"

# --- Host-only IP configuration ---------------------------------------------
if ($me.IP) {
    $current = Get-NetIPAddress -InterfaceIndex $hoIdx -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($current.IPAddress -ne $me.IP) {
        Write-Host "Setting static IP $($me.IP)/$($cfg.Network.PrefixLength) (no gateway)"
        Set-NetIPInterface -InterfaceIndex $hoIdx -Dhcp Disabled
        $current | Remove-NetIPAddress -Confirm:$false
        Remove-NetRoute -InterfaceIndex $hoIdx -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $hoIdx -IPAddress $me.IP -PrefixLength $cfg.Network.PrefixLength | Out-Null
    }

    $dnsServers = @(
        $cfg.Nodes[$cfg.Dns.PrimaryNode].IP
        $cfg.Nodes[$cfg.Dns.SecondaryNode].IP
    )
    Write-Host "DNS servers: $($dnsServers -join ', ')"
    Set-DnsClientServerAddress -InterfaceIndex $hoIdx -ServerAddresses $dnsServers
    # Servers register their host-only IP: one A + PTR record per server.
    Set-DnsClient -InterfaceIndex $hoIdx -RegisterThisConnectionsAddress $true
}
else {
    Write-Host 'Host-only adapter via DHCP (server3)'
    Set-NetIPInterface -InterfaceIndex $hoIdx -Dhcp Enabled
    Set-DnsClientServerAddress -InterfaceIndex $hoIdx -ResetServerAddresses
    # The client must not register itself in DNS.
    Set-DnsClient -InterfaceIndex $hoIdx -RegisterThisConnectionsAddress $false
}

# Lower metric = preferred. Domain names must be resolved via the host-only
# DNS servers first; the NAT DNS server doesn't know our domain.
Set-NetIPInterface -InterfaceIndex $hoIdx  -InterfaceMetric 10
Set-NetIPInterface -InterfaceIndex $natIdx -InterfaceMetric 50

# --- NAT adapter -------------------------------------------------------------
# Keeps its VirtualBox DHCP config (internet), but never ends up in our DNS.
Set-DnsClient -InterfaceIndex $natIdx -RegisterThisConnectionsAddress $false

# --- Hostname ----------------------------------------------------------------
if ($env:COMPUTERNAME -ne $me.Hostname) {
    Write-Host "Renaming $env:COMPUTERNAME -> $($me.Hostname) (reboot required)"
    Rename-Computer -NewName $me.Hostname -Force
}
else {
    Write-Host "Hostname already $($me.Hostname)"
}

Write-Host '=== Base configuration done ==='
