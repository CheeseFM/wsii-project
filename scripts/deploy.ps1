# Deploys the complete environment in the right order. Run on the HOST from
# the scripts folder:
#   .\deploy.ps1
#
# Why not just `vagrant up`?
#   - After the DC promotion, server1 accepts no WinRM requests until it has
#     rebooted, so Vagrant can't wait for it (see server1\01-adds.ps1). This
#     script waits until AD runs and then continues with server1.
#   - The VMs depend on each other: server2/3 join the domain of server1,
#     the client needs DHCP from server3 and the CA GPO needs the CA on server3.
#   - RSAT on the client (Windows Update, up to an hour) needs no domain, so it
#     runs in the background in parallel with the servers.
#
# Safe to run again: every script only changes what isn't correct yet.

param(
    # VirtualBox becomes very slow / hangs when Windows' hypervisor is active
    [switch]$IgnoreHypervisor
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$started = Get-Date
$timings = [System.Collections.Generic.List[object]]::new()
$logDir  = Join-Path $PSScriptRoot '.vagrant\deploy-logs'
New-Item -ItemType Directory -Force $logDir | Out-Null

# --- Helpers -----------------------------------------------------------------
function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host ''
    Write-Host "##### $Name ($(Get-Date -Format HH:mm)) #####" -ForegroundColor Cyan
    $stepStart = Get-Date
    & $Action
    $timings.Add([pscustomobject]@{ Step = $Name; Minutes = [math]::Round(((Get-Date) - $stepStart).TotalMinutes, 1) })
}

# Runs vagrant and stops the deployment as soon as a command fails
function Invoke-Vagrant {
    & vagrant @args
    if ($LASTEXITCODE -ne 0) { throw "vagrant $($args -join ' ') failed (exit code $LASTEXITCODE)" }
}

# Waits until server1 runs as a domain controller after its self-reboot.
# During the promotion vagrant winrm can hang, so every attempt is a job with a timeout.
function Wait-ForDomainController {
    param([int]$TimeoutMinutes = 25)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ($true) {
        $job = Start-Job { Set-Location $using:PSScriptRoot; vagrant winrm server1 -s powershell -c '(Get-Service NTDS).Status' 2>$null }
        $status = if (Wait-Job $job -Timeout 45) { "$(Receive-Job $job)".Trim() } else { 'no answer (promoting/rebooting)' }
        Remove-Job $job -Force
        Write-Host "  $(Get-Date -Format HH:mm:ss) server1 AD service: $status"
        if ($status -match 'Running') { return }
        if ((Get-Date) -gt $deadline) { throw "server1 not a working domain controller after $TimeoutMinutes minutes" }
        Start-Sleep -Seconds 30
    }
}

# --- Prerequisites -----------------------------------------------------------
if ((Get-CimInstance Win32_ComputerSystem).HypervisorPresent -and -not $IgnoreHypervisor) {
    throw ("Windows' hypervisor is active: VirtualBox then runs via Hyper-V and becomes very slow or hangs. " +
           "Disable it (see readme), or run with -IgnoreHypervisor.")
}
if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) { throw 'vagrant not found: install Vagrant first' }

# After a destroyed VM, VirtualBox sometimes leaves its log folder behind in
# the WS2 group folder; creating the VM again then fails (VERR_ALREADY_EXISTS).
$vbm = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
if (Test-Path $vbm) {
    $machineFolder = ((& $vbm list systemproperties) -match '^Default machine folder:' -replace '^Default machine folder:\s*', '')
    $registered    = (& $vbm list vms) -join "`n"
    foreach ($vm in 'server1', 'server2', 'server3', 'client') {
        $leftover = Join-Path $machineFolder "WS2\$vm"
        if ((Test-Path $leftover) -and $registered -notmatch "`"$vm`"") {
            throw "Leftover folder of a removed VM: $leftover - delete it first, then run deploy.ps1 again."
        }
    }
}

# --- Deployment --------------------------------------------------------------
Invoke-Step '1. server1: base + schedule DC promotion' {
    Invoke-Vagrant up server1 --provision
}

# Client RSAT in the background: only needs internet
$rsatLog = Join-Path $logDir 'client-rsat.log'
Write-Host ''
Write-Host "##### Client: RSAT in the background (log: $rsatLog) #####" -ForegroundColor Cyan
$rsatJob = Start-Job {
    Set-Location $using:PSScriptRoot
    $log = $using:rsatLog
    vagrant up client --provision-with rsat *> $log
    $LASTEXITCODE
}

Invoke-Step '2. server1: wait for DC promotion + reboot' {
    Wait-ForDomainController
}

Invoke-Step '3. server1: DNS, OUs/users, IIS' {
    Invoke-Vagrant provision server1 --provision-with adds,dns,users,iis
}

Invoke-Step '4. server2: base, join, secondary DNS, firewall' {
    Invoke-Vagrant up server2 --provision
}

Invoke-Step '5. server3: base, join, CA, DHCP, firewall' {
    Invoke-Vagrant up server3 --provision
}

Invoke-Step '6. server1: CA trust GPO + firewall' {
    Invoke-Vagrant provision server1 --provision-with ca-gpo,firewall
}

Invoke-Step '7. client: wait for RSAT (background)' {
    $exitCode = Receive-Job (Wait-Job $rsatJob) | Select-Object -Last 1
    Remove-Job $rsatJob
    Get-Content $rsatLog | Select-String 'client: (Installing|===)' | ForEach-Object { $_.Line }
    if ($exitCode -ne 0) { throw "Client RSAT failed, see $rsatLog" }
}

Invoke-Step '8. client: base, join, verify everything' {
    Invoke-Vagrant provision client --provision-with base,join,verify
}

# --- Summary -----------------------------------------------------------------
Write-Host ''
Write-Host '##### Deployment done #####' -ForegroundColor Green
$timings | Format-Table -AutoSize
Write-Host ("Total: {0:N0} minutes" -f ((Get-Date) - $started).TotalMinutes)
