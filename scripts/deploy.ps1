# Deploys the complete environment in the right order, run on the HOST
# from the scripts folder:  .\deploy.ps1
#
# Why not just `vagrant up`? After the DC promotion, server1 accepts no WinRM
# requests until it has rebooted, so Vagrant can't wait for it by itself
# (see server1\01-adds.ps1). This script waits instead and then continues.

$ErrorActionPreference = 'Stop'

# TODO: function Invoke-Vagrant: run vagrant with arguments, stop on exit code <> 0

# TODO: function Wait-ForDomainController: every 30 s `vagrant winrm server1`
#       checking (Get-Service NTDS).Status = Running, each attempt in a job with
#       a timeout (it can hang during the promotion), max ~15 minutes

# TODO: 1. vagrant up server1                     (base + schedule promotion)
# TODO: 2. Wait-ForDomainController
# TODO: 3. vagrant provision server1 --provision-with adds,dns,users,iis
# TODO: 4. vagrant up server2                     (base, join, secondary DNS)
# TODO: 5. vagrant up server3                     (base, join, CA, DHCP)
# TODO: 6. vagrant provision server1 --provision-with ca-gpo,firewall
# TODO: 7. vagrant up client                      (base, join, RSAT)
# TODO: show total duration (handy for the readme/video)
