# Firewall for a server, based on the Firewall section in config.psd1
#   - default policy: inbound blocked, outbound allowed, firewall enabled
#   - inbound only what the server needs (Common + server-specific)
#
# Run as the LAST step per server: some rule groups only exist after the
# matching role is installed.
# Usage: C:\vagrant\common\firewall.ps1 -Node server1

param(
    [Parameter(Mandatory)]
    [ValidateSet('server1', 'server2', 'server3')]
    [string]$Node
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
$cfg = Get-LabConfig
$fw  = $cfg.Firewall

Write-Host "=== Firewall: $Node ==="

# TODO: enable all profiles with $fw.DefaultInbound / $fw.DefaultOutbound
#       (Set-NetFirewallProfile -Profile Domain,Private,Public ...)

# TODO: groups = $fw.Common.Groups + $fw[$Node].Groups:
#       Enable-NetFirewallRule -DisplayGroup per group, error if the group doesn't exist

# TODO: rules = $fw.Common.Rules + $fw[$Node].Rules:
#       New-NetFirewallRule per rule if it doesn't exist yet (by Name)

# TODO: show the result (enabled inbound rules) for the demo

Write-Host '=== Firewall done ==='
