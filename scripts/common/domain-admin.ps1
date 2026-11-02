# Helpers for steps that need domain admin rights.
# Vagrant works as the LOCAL vagrant user, which has no rights in AD.
#
# Dot-source in a script:
#   . "$PSScriptRoot\..\common\domain-admin.ps1"
#   $cred = Get-DomainAdminCredential -Config $cfg
#   Invoke-AsDomainAdmin -Config $cfg -Parameters @{ Name = 'x' } -ScriptBlock { ... $Name ... }

function Get-DomainAdminCredential {
    param([Parameter(Mandatory)] $Config)
    $password = ConvertTo-SecureString $Config.Domain.AdministratorPassword -AsPlainText -Force
    New-Object PSCredential("$($Config.Domain.NetBiosName)\Administrator", $password)
}

# Runs a script block as the domain Administrator via a temporary scheduled
# task. Needed for cmdlets without a -Credential parameter (e.g.
# Add-DhcpServerInDC): Invoke-Command -Credential to the machine itself fails
# on the double hop (the credentials don't reach AD), a scheduled task gets
# a full logon. Parameters become variables with the same name (strings only).
function Invoke-AsDomainAdmin {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [scriptblock]$ScriptBlock,
        [hashtable]$Parameters = @{},
        [int]$TimeoutSeconds = 600
    )

    $dir      = 'C:\ws2\domain-admin'
    $taskName = 'WS2-DomainAdmin'
    $script   = "$dir\task.ps1"
    $log      = "$dir\task.log"
    New-Item -ItemType Directory -Force $dir | Out-Null
    Remove-Item $log -ErrorAction SilentlyContinue

    $variables = $Parameters.GetEnumerator() | ForEach-Object {
        "`$$($_.Key) = '$("$($_.Value)".Replace("'", "''"))'"
    }
    @(
        '$ErrorActionPreference = ''Stop'''
        $variables
        'try {'
        $ScriptBlock.ToString()
        '    exit 0'
        '} catch { $_ | Out-String; exit 1 }'
    ) | Set-Content -Path $script -Encoding UTF8

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
        "-NoProfile -ExecutionPolicy Bypass -Command `"& '$script' *>&1 | Out-File '$log' -Encoding utf8; exit `$LASTEXITCODE`"")
    $user = "$($Config.Domain.NetBiosName)\Administrator"
    Register-ScheduledTask -TaskName $taskName -Action $action -User $user `
        -Password $Config.Domain.AdministratorPassword -RunLevel Highest -Force | Out-Null

    try {
        Start-ScheduledTask -TaskName $taskName
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        do {
            Start-Sleep -Seconds 2
            if ((Get-Date) -gt $deadline) { throw "Task as $user did not finish within $TimeoutSeconds seconds" }
        } while ((Get-ScheduledTask -TaskName $taskName).State -eq 'Running')

        if (Test-Path $log) { Get-Content $log | Where-Object { $_ } | Write-Host }
        $result = (Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult
        if ($result -ne 0) { throw "Task as $user failed (exit code $result)" }
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Remove-Item $script -ErrorAction SilentlyContinue
    }
}
