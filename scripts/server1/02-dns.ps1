# Server1 - step 2: primary DNS
#   - only the host-only IP in DNS (no records with the NAT IP)
#   - reverse lookup zone + exactly one A and one PTR record per server
#   - server2 as second name server, with zone transfers + notify
#   - forwarders from the config + extra records (intranet CNAME)
#
# Safe to run multiple times: only adds/removes what isn't correct yet.
# Run after the promotion reboot:
#   vagrant provision server1 --provision-with dns

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
$cfg    = Get-LabConfig
$zone   = $cfg.Domain.Name
$rzone  = $cfg.Dns.ReverseZone
$me     = $cfg.Nodes[$cfg.Dns.PrimaryNode]
$second = $cfg.Nodes[$cfg.Dns.SecondaryNode]

Write-Host "=== DNS: zones for $zone ==="

# --- Wait until AD-integrated DNS is ready -----------------------------------
# Right after the first boot as DC, or after a restart of the DNS service, the
# zones are still loading (and locked: error 9607 when adding records).
function Wait-DnsZone {
    for ($i = 1; -not (Get-DnsServerZone -Name $zone -ErrorAction SilentlyContinue); $i++) {
        if ($i -gt 30) { throw "Zone $zone not available after 5 minutes" }
        Write-Host "Waiting for zone $zone..."
        Start-Sleep -Seconds 10
    }
    Start-Sleep -Seconds 5
}
Wait-DnsZone

# --- Only the host-only IP ---------------------------------------------------
# The DNS server registers A records for every IP it listens on: listening on
# the NAT IP is what puts 10.0.2.15 in the zone.
$listening = @((Get-DnsServerSetting -All -WarningAction SilentlyContinue).ListeningIPAddress)
if ($listening.Count -ne 1 -or "$($listening[0])" -ne $me.IP) {
    Write-Host "DNS server listens only on $($me.IP)"
    $settings = Get-DnsServerSetting -All -WarningAction SilentlyContinue
    $settings.ListeningIPAddress = @($me.IP)
    Set-DnsServerSetting -InputObject $settings -WarningAction SilentlyContinue
    Restart-Service DNS
    Wait-DnsZone
}

# Remove records with a NAT address (IPv4 10.0.2.x) and all IPv6 records:
# only the host-only IPv4 network is used.
foreach ($z in $zone, "_msdcs.$zone") {
    Get-DnsServerResourceRecord -ZoneName $z |
        Where-Object {
            ($_.RecordType -eq 'A' -and "$($_.RecordData.IPv4Address)" -like $cfg.Network.NatSubnet) -or
            $_.RecordType -eq 'AAAA'
        } |
        ForEach-Object {
            Write-Host "Removing $($_.RecordType) $($_.HostName) in $z"
            $_ | Remove-DnsServerResourceRecord -ZoneName $z -Force
        }
}

# --- Forwarders --------------------------------------------------------------
# The promotion copies the NAT DNS servers (those of the host's network) as
# forwarders; they don't work on another network. Use the config instead;
# empty = no forwarders, root hints via NAT.
# (without forwarders, IPAddress contains one empty entry: filter it out)
$current = @((Get-DnsServerForwarder).IPAddress | Where-Object { $_ } | ForEach-Object { "$_" })
if (Compare-Object $current @($cfg.Dns.Forwarders)) {
    Write-Host "Forwarders: $(if ($cfg.Dns.Forwarders) { $cfg.Dns.Forwarders -join ', ' } else { 'none (root hints)' })"
    if ($current) { Remove-DnsServerForwarder -IPAddress $current -Force }
    if ($cfg.Dns.Forwarders) { Add-DnsServerForwarder -IPAddress $cfg.Dns.Forwarders }
}

# --- Reverse lookup zone -----------------------------------------------------
if (-not (Get-DnsServerZone -Name $rzone -ErrorAction SilentlyContinue)) {
    Write-Host "Creating reverse zone $rzone"
    Add-DnsServerPrimaryZone -NetworkId "$($cfg.Network.NetworkId)/$($cfg.Network.PrefixLength)" `
        -ReplicationScope Domain -DynamicUpdate Secure
}

# --- Exactly one A + PTR per server ------------------------------------------
foreach ($node in $cfg.Nodes.Values | Where-Object IP) {
    $fqdn = "$($node.Hostname).$zone"
    $a = @(Get-DnsServerResourceRecord -ZoneName $zone -Name $node.Hostname -RRType A -ErrorAction SilentlyContinue)
    if ($a.Count -ne 1 -or "$($a[0].RecordData.IPv4Address)" -ne $node.IP) {
        Write-Host "A record $($node.Hostname) -> $($node.IP)"
        $a | Remove-DnsServerResourceRecord -ZoneName $zone -Force
        Add-DnsServerResourceRecordA -ZoneName $zone -Name $node.Hostname -IPv4Address $node.IP
    }

    $ptrName = $node.IP.Split('.')[-1]
    $ptr = @(Get-DnsServerResourceRecord -ZoneName $rzone -Name $ptrName -RRType Ptr -ErrorAction SilentlyContinue)
    if ($ptr.Count -ne 1 -or $ptr[0].RecordData.PtrDomainName -ne "$fqdn.") {
        Write-Host "PTR record $($node.IP) -> $fqdn"
        $ptr | Remove-DnsServerResourceRecord -ZoneName $rzone -Force
        Add-DnsServerResourceRecordPtr -ZoneName $rzone -Name $ptrName -PtrDomainName $fqdn
    }
}

# --- Both DNS servers as name server + zone transfers ------------------------
foreach ($z in $zone, $rzone) {
    foreach ($ns in $me, $second) {
        $nsFqdn = "$($ns.Hostname).$zone."
        $existing = Get-DnsServerResourceRecord -ZoneName $z -Name '@' -RRType NS |
            Where-Object { $_.RecordData.NameServer -eq $nsFqdn }
        if (-not $existing) {
            Write-Host "NS record $nsFqdn in $z"
            Add-DnsServerResourceRecord -ZoneName $z -Name '@' -NS -NameServer $nsFqdn
        }
    }

    # Transfers only to the name servers of the zone, and notify them on changes
    $info = Get-DnsServerZone -Name $z
    if ($info.SecureSecondaries -ne 'TransferToZoneNameServer' -or $info.Notify -ne 'Notify') {
        Write-Host "Zone transfers + notify to name servers for $z"
        Set-DnsServerPrimaryZone -Name $z -SecureSecondaries TransferToZoneNameServer -Notify Notify
    }
}

# --- Extra records -----------------------------------------------------------
foreach ($record in $cfg.Dns.Records) {
    if ($record.Type -ne 'CNAME') { throw "Record type $($record.Type) not supported" }
    $target = "$($record.Target).$zone."
    $cname = Get-DnsServerResourceRecord -ZoneName $zone -Name $record.Name -RRType CName -ErrorAction SilentlyContinue
    if ($cname.RecordData.HostNameAlias -ne $target) {
        Write-Host "CNAME $($record.Name) -> $target"
        $cname | Remove-DnsServerResourceRecord -ZoneName $zone -Force
        Add-DnsServerResourceRecordCName -ZoneName $zone -Name $record.Name -HostNameAlias $target
    }
}

# --- Result (for the demo) ---------------------------------------------------
foreach ($z in $zone, $rzone) {
    Write-Host "--- $z"
    Get-DnsServerResourceRecord -ZoneName $z |
        Where-Object RecordType -in 'A', 'PTR', 'NS', 'CNAME' |
        Where-Object { $_.HostName -notlike '*_*' } |
        Format-Table HostName, RecordType, @{ n = 'Data'; e = {
            $d = $_.RecordData
            if ($d.IPv4Address) { $d.IPv4Address } elseif ($d.NameServer) { $d.NameServer }
            elseif ($d.PtrDomainName) { $d.PtrDomainName } else { $d.HostNameAlias } } } -AutoSize |
        Out-String | Write-Host
}

# --- Check the requirements --------------------------------------------------
# Not every DNS cmdlet error stops the script, so verify the end result and
# fail loudly (Vagrant then reports an error instead of success).
$problems = @()
foreach ($node in $cfg.Nodes.Values | Where-Object IP) {
    $a   = @(Get-DnsServerResourceRecord -ZoneName $zone -Name $node.Hostname -RRType A -ErrorAction SilentlyContinue)
    $ptr = @(Get-DnsServerResourceRecord -ZoneName $rzone -Name $node.IP.Split('.')[-1] -RRType Ptr -ErrorAction SilentlyContinue)
    if ($a.Count -ne 1)   { $problems += "$($node.Hostname): $($a.Count) A records instead of 1" }
    if ($ptr.Count -ne 1) { $problems += "$($node.Hostname): $($ptr.Count) PTR records instead of 1" }
}
$natRecords = Get-DnsServerResourceRecord -ZoneName $zone -RRType A |
    Where-Object { "$($_.RecordData.IPv4Address)" -like $cfg.Network.NatSubnet }
if ($natRecords) { $problems += "NAT IP still in DNS: $($natRecords.HostName -join ', ')" }
foreach ($z in $zone, $rzone) {
    $nsCount = @(Get-DnsServerResourceRecord -ZoneName $z -Name '@' -RRType NS).Count
    if ($nsCount -ne 2) { $problems += "${z}: $nsCount NS records instead of 2" }
}
if ($problems) { throw "DNS not correct:`n  $($problems -join "`n  ")" }

Write-Host '=== DNS done, all checks OK ==='
