# Client - step 2: verify the whole environment from the client
#   Every service is used over the network, as a domain admin, so the real
#   paths through the server firewalls are tested (RPC, SMB, LDAP, Kerberos,
#   DNS, DHCP, HTTP). Handy after a full deployment and in the demo.
#
#   vagrant provision client --provision-with verify

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
. "$PSScriptRoot\..\common\domain-admin.ps1"
$cfg  = Get-LabConfig
$zone = $cfg.Domain.Name

Write-Host '=== Verify environment from the client ==='

$params = @{
    Zone      = $zone
    RZone     = $cfg.Dns.ReverseZone
    Server1   = "$($cfg.Nodes.server1.Hostname).$zone"
    Server2   = "$($cfg.Nodes.server2.Hostname).$zone"
    Server3   = "$($cfg.Nodes.server3.Hostname).$zone"
    Intranet  = "$($cfg.Iis.HostName).$zone"
    CaName    = $cfg.Ca.CommonName
    GpoName   = $cfg.Ca.GpoName
    ScopeId    = $cfg.Network.NetworkId
    RangeStart = $cfg.Dhcp.StartRange.Split('.')[-1]
    ExclStart  = $cfg.Dhcp.ExclusionStart.Split('.')[-1]
}

Invoke-AsDomainAdmin -Config $cfg -Parameters $params -ScriptBlock {
    $results = [System.Collections.Generic.List[object]]::new()
    function Test-Step($Name, [scriptblock]$Test) {
        try   { $detail = & $Test; $ok = $true }
        catch { $detail = $_.Exception.Message.Split("`n")[0]; $ok = $false }
        $results.Add([pscustomobject]@{ Result = if ($ok) { 'OK' } else { 'FAIL' }; Test = $Name; Detail = "$detail" })
    }

    Test-Step 'DHCP lease in active range (renew)' {
        ipconfig /renew Host-Only | Out-Null
        $address = Get-NetIPAddress -InterfaceAlias Host-Only -AddressFamily IPv4
        if ($address.PrefixOrigin -ne 'Dhcp') { throw "no DHCP address ($($address.IPAddress))" }
        $last = [int]$address.IPAddress.Split('.')[-1]
        if ($last -lt [int]$RangeStart -or $last -ge [int]$ExclStart) { throw "$($address.IPAddress) outside .$RangeStart - .$([int]$ExclStart - 1)" }
        $address.IPAddress
    }
    Test-Step 'Client NOT registered in DNS' {
        $ip = (Get-NetIPAddress -InterfaceAlias Host-Only -AddressFamily IPv4).IPAddress
        if (Resolve-DnsName "$env:COMPUTERNAME.$Zone" -Server $Server1 -DnsOnly -ErrorAction SilentlyContinue) { throw "A record $env:COMPUTERNAME exists" }
        if (Resolve-DnsName $ip -Server $Server1 -DnsOnly -ErrorAction SilentlyContinue) { throw "PTR for $ip exists" }
        'no A or PTR record'
    }
    Test-Step 'CA root certificate trusted' {
        if (-not (Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like "CN=$CaName*")) { throw "$CaName not in Trusted Root" }
        "$CaName in Trusted Root"
    }
    foreach ($dns in $Server1, $Server2) {
        Test-Step "DNS query via $dns" {
            (Resolve-DnsName $Intranet -Server $dns -DnsOnly | Where-Object QueryType -eq 'A').IPAddress
        }
    }
    Test-Step 'AD via ADWS (Get-ADUser)' {
        "$(@(Get-ADUser -Filter * -Server $Server1).Count) users"
    }
    Test-Step 'GPO (Kerberos, LDAP, SMB SYSVOL)' {
        $out = gpupdate /target:computer /force 2>&1 | Out-String
        if ($out -notmatch 'completed successfully') { throw $out.Trim() }
        if (-not (gpresult /scope computer /r | Select-String ([regex]::Escape($GpoName)))) { throw "$GpoName not applied" }
        "$GpoName applied"
    }
    Test-Step 'DNS management RPC (server1)' {
        $z = dnscmd $Server1 /enumzones 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $z -notmatch [regex]::Escape($RZone)) { throw $z.Trim() }
        'zones listed'
    }
    Test-Step 'DNS management RPC (server2)' {
        $z = dnscmd $Server2 /enumzones 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $z -notmatch 'Secondary') { throw $z.Trim() }
        'secondary zones listed'
    }
    Test-Step 'DHCP management RPC (server3)' {
        $s = netsh dhcp server "\\$Server3" show scope 2>&1 | Out-String
        if ($s -notmatch [regex]::Escape($ScopeId)) { throw $s.Trim() }
        "scope $ScopeId listed"
    }
    Test-Step 'CA DCOM (certutil -ping)' {
        $p = certutil -config "$Server3\$CaName" -ping 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw $p.Trim() }
        'CA interface alive'
    }
    Test-Step 'Web Enrollment /CertSrv (HTTP)' {
        $r = Invoke-WebRequest "http://$Server3/certsrv/" -UseDefaultCredentials -UseBasicParsing
        "HTTP $($r.StatusCode)"
    }
    Test-Step 'Intranet site (HTTP)' {
        $r = Invoke-WebRequest "http://$Intranet" -UseBasicParsing
        if ($r.Content -notmatch 'Hello World') { throw 'no Hello World' }
        "HTTP $($r.StatusCode), Hello World"
    }
    Test-Step 'Ping all servers' {
        foreach ($s in $Server1, $Server2, $Server3) {
            if (-not (Test-Connection $s -Count 1 -Quiet)) { throw "$s doesn't answer" }
        }
        '3/3'
    }

    $results | Format-Table -AutoSize | Out-String -Width 200
    $failed = @($results | Where-Object Result -eq 'FAIL').Count
    if ($failed) { throw "$failed test(s) failed" }
}

Write-Host '=== Verify done, all tests OK ==='
