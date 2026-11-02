# Server1 - step 3: OUs and users
#   - at least 3 OUs, at least 4 users (structure in ous.psd1)
#   - at least 2 Domain Admins, at least 2 regular Domain Users
#
# Safe to run multiple times: only creates what doesn't exist yet.
# Run after the promotion reboot:
#   vagrant provision server1 --provision-with users

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\common\config.ps1"
$cfg = Get-LabConfig
$ous = Import-PowerShellDataFile -Path "$PSScriptRoot\..\ous.psd1"

$zone     = $cfg.Domain.Name
$domainDn = 'DC=' + ($zone.Split('.') -join ',DC=')    # WS26-JDV.hogent -> DC=WS26-JDV,DC=hogent

Write-Host "=== OUs and users for $zone ==="

# --- Check ous.psd1 against the requirements first ----------------------------
$admins = @($ous.Users | Where-Object Admin)
$normal = @($ous.Users | Where-Object { -not $_.Admin })
if ($ous.OUs.Count -lt 3 -or $ous.Users.Count -lt 4 -or $admins.Count -lt 2 -or $normal.Count -lt 2) {
    throw "ous.psd1 doesn't meet the requirements: $($ous.OUs.Count) OUs (min 3), " +
          "$($admins.Count) admins (min 2), $($normal.Count) regular users (min 2)"
}

# --- Wait until AD Web Services is ready -------------------------------------
# The AD cmdlets go through ADWS, which starts a while after boot.
for ($i = 1; -not (Get-ADDomain -ErrorAction SilentlyContinue); $i++) {
    if ($i -gt 30) { throw 'AD Web Services not available after 5 minutes' }
    Write-Host 'Waiting for AD Web Services...'
    Start-Sleep -Seconds 10
}

# --- OUs ---------------------------------------------------------------------
foreach ($ou in $ous.OUs) {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$($ou.Name)'" -SearchBase $domainDn -SearchScope OneLevel)) {
        Write-Host "Creating OU $($ou.Name)"
        New-ADOrganizationalUnit -Name $ou.Name -Path $domainDn
    }
}

# --- Users -------------------------------------------------------------------
foreach ($user in $ous.Users) {
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($user.SamAccountName)'")) {
        Write-Host "Creating user $($user.SamAccountName) in OU $($user.OU)"
        New-ADUser `
            -Name "$($user.GivenName) $($user.Surname)" `
            -GivenName $user.GivenName `
            -Surname $user.Surname `
            -SamAccountName $user.SamAccountName `
            -UserPrincipalName "$($user.SamAccountName)@$zone" `
            -Path "OU=$($user.OU),$domainDn" `
            -AccountPassword (ConvertTo-SecureString $user.Password -AsPlainText -Force) `
            -PasswordNeverExpires $true `
            -Enabled $true
    }

    # Domain Admins membership exactly as in ous.psd1 (also removes it again)
    $isAdmin = [bool](Get-ADGroupMember 'Domain Admins' |
        Where-Object SamAccountName -eq $user.SamAccountName)
    if ($user.Admin -and -not $isAdmin) {
        Write-Host "Adding $($user.SamAccountName) to Domain Admins"
        Add-ADGroupMember 'Domain Admins' -Members $user.SamAccountName
    }
    elseif (-not $user.Admin -and $isAdmin) {
        Write-Host "Removing $($user.SamAccountName) from Domain Admins"
        Remove-ADGroupMember 'Domain Admins' -Members $user.SamAccountName -Confirm:$false
    }
}

# --- Result (for the demo) ---------------------------------------------------
$adminNames = (Get-ADGroupMember 'Domain Admins').SamAccountName
foreach ($ou in $ous.OUs) {
    Write-Host "--- OU $($ou.Name)"
    Get-ADUser -Filter * -SearchBase "OU=$($ou.Name),$domainDn" |
        Format-Table SamAccountName, Name, Enabled,
            @{ n = 'DomainAdmin'; e = { $_.SamAccountName -in $adminNames } } -AutoSize |
        Out-String | Write-Host
}

Write-Host '=== OUs and users done ==='
