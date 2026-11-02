# Client - step 1: RSAT tools
#   - only the tools needed for the demo:
#     AD, DNS, DHCP, Certificate Services, Group Policy Management
#
# Needs only internet (via NAT), not the domain: runs as the FIRST client step,
# so deploy.ps1 can install it in parallel with the servers. RSAT is a Windows
# "capability" downloaded via Windows Update: this takes up to an hour.
# The client checks (IP, CA trusted, ...) are in 02-verify.ps1.
# Safe to run multiple times.

$ErrorActionPreference = 'Stop'

Write-Host '=== RSAT tools ==='

$tools = @(
    'Rsat.ActiveDirectory.DS-LDS.Tools'      # Users and Computers, AD PowerShell
    'Rsat.Dns.Tools'                         # DNS Manager (+ dnscmd)
    'Rsat.DHCP.Tools'                        # DHCP console
    'Rsat.CertificateServices.Tools'         # Certification Authority console
    'Rsat.GroupPolicy.Management.Tools'      # GPMC
)

foreach ($tool in $tools) {
    $capability = Get-WindowsCapability -Online -Name "$tool*"
    if (-not $capability) { throw "Capability $tool not found" }
    if ($capability.State -ne 'Installed') {
        Write-Host "Installing $($capability.Name) ($(Get-Date -Format HH:mm))"
        Add-WindowsCapability -Online -Name $capability.Name | Out-Null
    }
}
Get-WindowsCapability -Online -Name 'Rsat.*' | Where-Object State -eq 'Installed' |
    Format-Table Name, State -AutoSize | Out-String | Write-Host

Write-Host '=== RSAT tools done ==='
