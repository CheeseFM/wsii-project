# Firewall for a server, based on the Firewall section in config.psd1
#   - default policy: inbound blocked, outbound allowed, firewall enabled
#   - inbound only what the server needs (Common + server-specific);
#     every other enabled inbound allow rule is disabled
#
# Run as the LAST step per server: some rule groups only exist after the
# matching role is installed.
# Safe to run multiple times.
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

$groups = @($fw.Common.Groups) + @($fw[$Node].Groups)
$rules  = @($fw.Common.Rules) + @($fw[$Node].Rules) | Where-Object { $_ }

# --- Default policy ----------------------------------------------------------
Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True `
    -DefaultInboundAction $fw.DefaultInbound -DefaultOutboundAction $fw.DefaultOutbound

# --- Allowed: built-in groups ------------------------------------------------
# Enabled FIRST: WinRM must stay allowed before anything gets disabled,
# otherwise Vagrant loses its connection.
foreach ($group in $groups) {
    if (-not (Get-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue)) {
        throw "Firewall group '$group' doesn't exist on $env:COMPUTERNAME (role not installed yet?)"
    }
    Enable-NetFirewallRule -DisplayGroup $group
}

# --- Allowed: custom rules ---------------------------------------------------
foreach ($rule in $rules) {
    if (-not (Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue)) {
        Write-Host "Creating rule $($rule.Name)"
        $params = @{
            Name        = $rule.Name
            DisplayName = $rule.Name
            Direction   = 'Inbound'
            Action      = 'Allow'
            Protocol    = $rule.Protocol
            Profile     = 'Any'
        }
        if ($rule.IcmpType)  { $params.IcmpType  = $rule.IcmpType }
        if ($rule.LocalPort) { $params.LocalPort = $rule.LocalPort }
        New-NetFirewallRule @params | Out-Null
    }
    Enable-NetFirewallRule -Name $rule.Name
}

# --- Everything else inbound: disabled ---------------------------------------
$customNames = @($rules | ForEach-Object { $_.Name })
$extra = Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow |
    Where-Object { $_.DisplayGroup -notin $groups -and $_.Name -notin $customNames }
foreach ($group in $extra | Group-Object { if ($_.DisplayGroup) { $_.DisplayGroup } else { $_.DisplayName } }) {
    Write-Host "Disabling: $($group.Name) ($($group.Count) rules)"
    $group.Group | Disable-NetFirewallRule
}

# --- Result (for the demo) ---------------------------------------------------
Write-Host "Profiles: inbound $($fw.DefaultInbound), outbound $($fw.DefaultOutbound), enabled"
Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow |
    Group-Object { if ($_.DisplayGroup) { $_.DisplayGroup } else { $_.DisplayName } } |
    Sort-Object Name |
    Format-Table @{ n = 'Allowed inbound'; e = { $_.Name } }, @{ n = 'Rules'; e = { $_.Count } } -AutoSize |
    Out-String | Write-Host

Write-Host '=== Firewall done ==='
