# Server1 - step 1: Active Directory Domain Services
#   - install the AD DS role
#   - create a new forest (domain + forest functional level Windows Server 2025)
#     with integrated DNS
#
# Why a scheduled task? After the promotion, until the reboot, server1 refuses
# every WinRM request (hangs, 401 or connection reset) - even Vagrant closing
# its own session. So Vagrant must be completely done before the promotion
# starts. This script (run by Vagrant) only prepares and schedules; the task
# runs this same script with -Promote as SYSTEM, which promotes and reboots.

param(
    [switch]$Promote    # used by the scheduled task, not by Vagrant
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
$cfg    = Get-LabConfig
$domain = $cfg.Domain

$localDir = 'C:\ws2'
$logFile  = "$localDir\adds-promotion.log"
$taskName = 'WS2-ADDS-Promotion'

# --- Run by the scheduled task ----------------------------------------------
if ($Promote) {
    Start-Transcript -Path $logFile -Force | Out-Null
    try {
        # Give Vagrant time to close its session cleanly
        Start-Sleep -Seconds 30
        $safeModePassword = ConvertTo-SecureString $domain.SafeModePassword -AsPlainText -Force
        Install-ADDSForest `
            -DomainName $domain.Name `
            -DomainNetbiosName $domain.NetBiosName `
            -ForestMode $domain.ForestMode `
            -DomainMode $domain.DomainMode `
            -InstallDns `
            -SafeModeAdministratorPassword $safeModePassword `
            -NoRebootOnCompletion `
            -Force |
            Select-Object Status, Message | Format-List
    }
    finally {
        Stop-Transcript | Out-Null
    }
    Restart-Computer -Force
    return
}

# --- Run by Vagrant ----------------------------------------------------------
Write-Host "=== AD DS: forest $($domain.Name) ==="

# DomainRole 4/5 = (primary) domain controller
if ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) {
    Write-Host 'Already a domain controller, nothing to do'
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    if (Test-Path $logFile) {
        Write-Host "--- Promotion log ($logFile) ---"
        Get-Content $logFile | Where-Object { $_ -match '^(Status|Message|WARNING)' } | Write-Host
    }
    return
}

if (-not (Get-WindowsFeature AD-Domain-Services).Installed) {
    Write-Host 'Installing AD DS role'
    Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null
}

# The local Administrator becomes the domain Administrator. On the Vagrant box
# this account doesn't require a password, which makes the promotion fail.
Write-Host 'Setting local Administrator password'
$adminPassword = ConvertTo-SecureString $domain.AdministratorPassword -AsPlainText -Force
Set-LocalUser -Name Administrator -Password $adminPassword
net user Administrator /passwordreq:yes | Out-Null

# The task runs as SYSTEM without Vagrant, so C:\vagrant (the shared folder)
# isn't guaranteed to be available: work from a local copy.
Write-Host "Copying scripts to $localDir"
New-Item -ItemType Directory -Force $localDir | Out-Null
Get-ChildItem C:\vagrant -Exclude .vagrant | Copy-Item -Destination $localDir -Recurse -Force

Write-Host "Scheduling promotion (task $taskName, starts in 30 seconds)"
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$localDir\server1\01-adds.ps1`" -Promote"
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

Write-Host '=== Promotion running in the background; server1 reboots when done ==='
Write-Host 'Wait about 10 minutes until server1 is back up, then run:'
Write-Host '  vagrant provision server1 --provision-with adds,dns,users,iis'
