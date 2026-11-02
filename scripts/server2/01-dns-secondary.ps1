# Server2 - step 1: secondary DNS
#   - DNS role (server2 is NOT a domain controller)
#   - secondary zones for the forward and reverse zone, with server1 as master
#
# Prerequisites: base + domain join done, 02-dns.ps1 on server1 allows
# zone transfers to the name servers (server2 is one of them).
# Safe to run multiple times.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
$cfg     = Get-LabConfig
$me      = $cfg.Nodes[$cfg.Dns.SecondaryNode]
$primary = $cfg.Nodes[$cfg.Dns.PrimaryNode].IP
$zones   = $cfg.Domain.Name, $cfg.Dns.ReverseZone

Write-Host "=== Secondary DNS (master: $primary) ==="

if (-not (Get-WindowsFeature DNS).Installed) {
    Write-Host 'Installing DNS role'
    Install-WindowsFeature DNS -IncludeManagementTools | Out-Null
}

# Only the host-only IP, same reason as on server1 (no NAT IP in DNS)
$listening = @((Get-DnsServerSetting -All -WarningAction SilentlyContinue).ListeningIPAddress)
if ($listening.Count -ne 1 -or "$($listening[0])" -ne $me.IP) {
    Write-Host "DNS server listens only on $($me.IP)"
    $settings = Get-DnsServerSetting -All -WarningAction SilentlyContinue
    $settings.ListeningIPAddress = @($me.IP)
    Set-DnsServerSetting -InputObject $settings -WarningAction SilentlyContinue
    Restart-Service DNS
}

foreach ($z in $zones) {
    if (-not (Get-DnsServerZone -Name $z -ErrorAction SilentlyContinue)) {
        Write-Host "Creating secondary zone $z (master $primary)"
        Add-DnsServerSecondaryZone -Name $z -ZoneFile "$z.dns" -MasterServers $primary
    }
    # Don't wait for the refresh interval: transfer now
    Start-DnsServerZoneTransfer -Name $z -FullTransfer
}

# --- Check: the zones must actually contain server1's records ----------------
# An empty secondary zone means server1 refuses the transfer.
foreach ($z in $zones) {
    for ($i = 1; -not (Get-DnsServerResourceRecord -ZoneName $z -RRType NS -ErrorAction SilentlyContinue); $i++) {
        if ($i -gt 12) {
            throw "Zone $z still empty after 2 minutes: does server1 allow zone transfers to $($me.IP)?"
        }
        Write-Host "Waiting for zone transfer of $z..."
        Start-Sleep -Seconds 10
    }

    Write-Host "--- $z (copy from $primary)"
    Get-DnsServerResourceRecord -ZoneName $z |
        Where-Object RecordType -in 'A', 'PTR', 'NS', 'CNAME' |
        Where-Object { $_.HostName -notlike '*_*' } |
        Format-Table HostName, RecordType, @{ n = 'Data'; e = {
            $d = $_.RecordData
            if ($d.IPv4Address) { $d.IPv4Address } elseif ($d.NameServer) { $d.NameServer }
            elseif ($d.PtrDomainName) { $d.PtrDomainName } else { $d.HostNameAlias } } } -AutoSize |
        Out-String | Write-Host
}

Write-Host '=== Secondary DNS done ==='
