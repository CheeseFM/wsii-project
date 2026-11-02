# Server3 - step 2: DHCP
#   - DHCP role, authorized in AD
#   - scope .100 - .200 with exclusion .151 - .200
#   - options: 006 DNS servers + 015 DNS domain name, no 003 router (no uplink)
#   - DHCP doesn't register DNS records for clients
#
# Prerequisites: base + domain join done.
# Authorizing in AD requires a domain admin (see common\domain-admin.ps1).
# Safe to run multiple times.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
. "$PSScriptRoot\..\common\domain-admin.ps1"
$cfg     = Get-LabConfig
$dhcp    = $cfg.Dhcp
$me      = $cfg.Nodes.server3
$fqdn    = "$($me.Hostname).$($cfg.Domain.Name)"
$scopeId = $cfg.Network.NetworkId
$dns     = $cfg.Nodes[$cfg.Dns.PrimaryNode].IP, $cfg.Nodes[$cfg.Dns.SecondaryNode].IP

Write-Host "=== DHCP: scope $($dhcp.StartRange) - $($dhcp.EndRange) ==="

if (-not (Get-WindowsFeature DHCP).Installed) {
    Write-Host 'Installing DHCP role'
    Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
}

# --- Post-install configuration ----------------------------------------------
# Local groups DHCP Administrators / DHCP Users, and mark the post-install
# configuration as done so Server Manager stops showing its notification.
if (-not (Get-LocalGroup 'DHCP Administrators' -ErrorAction SilentlyContinue)) {
    Write-Host 'Creating DHCP security groups'
    netsh dhcp add securitygroups | Out-Null
    Restart-Service DHCPServer
}
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' -Name ConfigurationState -Value 2

# --- Only on the host-only network -------------------------------------------
# Never hand out addresses on the NAT network.
foreach ($binding in Get-DhcpServerv4Binding) {
    $wanted = $binding.InterfaceAlias -eq 'Host-Only'
    if ($binding.BindingState -ne $wanted) {
        Write-Host "DHCP binding $($binding.InterfaceAlias): $wanted"
        Set-DhcpServerv4Binding -InterfaceAlias $binding.InterfaceAlias -BindingState $wanted | Out-Null
    }
}

# --- Authorize in AD ---------------------------------------------------------
if (-not (Get-DhcpServerSetting).IsAuthorized) {
    Write-Host "Authorizing $fqdn in AD (as domain admin)"
    Invoke-AsDomainAdmin -Config $cfg -Parameters @{ Fqdn = $fqdn; IP = $me.IP } -ScriptBlock {
        Add-DhcpServerInDC -DnsName $Fqdn -IPAddress $IP
    }
    Restart-Service DHCPServer
}

# --- Scope -------------------------------------------------------------------
if (-not (Get-DhcpServerv4Scope -ScopeId $scopeId -ErrorAction SilentlyContinue)) {
    Write-Host "Creating scope $scopeId ($($dhcp.StartRange) - $($dhcp.EndRange))"
    Add-DhcpServerv4Scope -Name $dhcp.ScopeName -StartRange $dhcp.StartRange -EndRange $dhcp.EndRange `
        -SubnetMask $dhcp.SubnetMask -LeaseDuration ([TimeSpan]$dhcp.LeaseDuration) -State Active
}

$exclusion = Get-DhcpServerv4ExclusionRange -ScopeId $scopeId |
    Where-Object { "$($_.StartRange)" -eq $dhcp.ExclusionStart -and "$($_.EndRange)" -eq $dhcp.ExclusionEnd }
if (-not $exclusion) {
    Write-Host "Exclusion $($dhcp.ExclusionStart) - $($dhcp.ExclusionEnd)"
    Add-DhcpServerv4ExclusionRange -ScopeId $scopeId -StartRange $dhcp.ExclusionStart -EndRange $dhcp.ExclusionEnd
}

# 006 DNS servers + 015 DNS domain name. No 003 router: the host-only network
# has no uplink, clients reach the internet via their own NAT adapter.
Set-DhcpServerv4OptionValue -ScopeId $scopeId -DnsServer $dns -DnsDomain $cfg.Domain.Name -Force

# Clients don't end up in DNS, not even via DHCP
Set-DhcpServerv4DnsSetting -DynamicUpdates Never

# --- Result (for the demo) ---------------------------------------------------
Write-Host "Authorized: $((Get-DhcpServerSetting).IsAuthorized)"
Get-DhcpServerv4Scope -ScopeId $scopeId |
    Format-Table ScopeId, Name, StartRange, EndRange, SubnetMask, State, LeaseDuration -AutoSize | Out-String | Write-Host
Get-DhcpServerv4ExclusionRange -ScopeId $scopeId | Format-Table -AutoSize | Out-String | Write-Host
Get-DhcpServerv4OptionValue -ScopeId $scopeId |
    Format-Table OptionId, Name, @{ n = 'Value'; e = { $_.Value -join ', ' } } -AutoSize | Out-String | Write-Host

Write-Host '=== DHCP done ==='
