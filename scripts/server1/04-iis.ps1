# Server1 - step 4: IIS
#   - basic IIS installation
#   - static Hello World page on port 80, reachable via http://intranet.<domain>
#     (the intranet CNAME is created in 02-dns.ps1)
#
# Safe to run multiple times: only creates what doesn't exist yet.
# Run after the promotion reboot:
#   vagrant provision server1 --provision-with iis

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
$cfg  = Get-LabConfig
$iis  = $cfg.Iis
$fqdn = "$($iis.HostName).$($cfg.Domain.Name)".ToLower()
$root = "C:\inetpub\$($iis.SiteName.ToLower())"

Write-Host "=== IIS: http://$fqdn ==="

# --- Role --------------------------------------------------------------------
# Web-Scripting-Tools = WebAdministration module (no GUI on Server Core)
$features = 'Web-Server', 'Web-Scripting-Tools'
$missing  = $features | Where-Object { -not (Get-WindowsFeature $_).Installed }
if ($missing) {
    Write-Host "Installing $($missing -join ', ')"
    Install-WindowsFeature $missing | Out-Null
}
Import-Module WebAdministration

# --- Content -----------------------------------------------------------------
New-Item -ItemType Directory -Force $root | Out-Null
$html = @"
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Intranet $($cfg.Domain.Name)</title></head>
<body>
  <h1>Hello World</h1>
  <p>Intranet of $($cfg.Domain.Name), served by $env:COMPUTERNAME.</p>
</body>
</html>
"@
Set-Content -Path "$root\index.html" -Value $html -Encoding UTF8

# --- Site --------------------------------------------------------------------
# Host header: only requests for intranet.<domain> end up here; the Default
# Web Site keeps answering for everything else on port 80.
if (-not (Get-Website -Name $iis.SiteName)) {
    Write-Host "Creating site $($iis.SiteName) on port $($iis.Port) for $fqdn"
    New-Website -Name $iis.SiteName -PhysicalPath $root -Port $iis.Port -HostHeader $fqdn | Out-Null
}
if ((Get-Website -Name $iis.SiteName).State -ne 'Started') {
    Start-Website -Name $iis.SiteName
}

# The Default Web Site answers every other request on port 80 (e.g. via the
# IP) with the IIS welcome page: unused, so stopped - also after a reboot.
$default = Get-Website -Name 'Default Web Site'
if ($default -and $default.State -ne 'Stopped') {
    Write-Host 'Stopping Default Web Site'
    Stop-Website -Name 'Default Web Site'
    Set-ItemProperty 'IIS:\Sites\Default Web Site' -Name serverAutoStart -Value $false
}

# --- Test via DNS (CNAME) ----------------------------------------------------
$response = Invoke-WebRequest -Uri "http://$fqdn" -UseBasicParsing
if ($response.Content -notmatch 'Hello World') {
    throw "http://$fqdn doesn't return the Hello World page"
}
Write-Host "http://$fqdn -> HTTP $($response.StatusCode), Hello World OK"
Get-Website -Name $iis.SiteName |
    Format-Table Name, State, PhysicalPath, @{ n = 'Binding'; e = { $_.Bindings.Collection.bindingInformation } } -AutoSize |
    Out-String | Write-Host

Write-Host '=== IIS done ==='
