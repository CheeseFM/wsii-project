# OUs and users, read by server1\03-ous-users.ps1.
# Requirements: at least 3 OUs, at least 4 users, of which at least 2 Domain
# Admins (Admin = $true) and at least 2 regular Domain Users.
# Lab environment only - passwords are documented in readme.pdf.

@{
    # Name = OU name, created directly under the domain
    OUs = @(
        @{ Name = 'IT' }
        @{ Name = 'Lectoren' }
        @{ Name = 'Studenten' }
    )

    # OU = name of an OU above; Admin = $true -> member of Domain Admins
    Users = @(
        @{ SamAccountName = 'jelle.devreeze';  GivenName = 'Jelle';  Surname = 'De Vreeze';  OU = 'IT';    Admin = $true;  Password = 'Admin123!' }
        @{ SamAccountName = 'jeroen.janssens';  GivenName = 'Jeroen';   Surname = 'Janssens'; OU = 'IT';    Admin = $true;  Password = 'Admin123!' }
        @{ SamAccountName = 'sanne.maes';     GivenName = 'Sanne';  Surname = 'Maes';     OU = 'Lectoren'; Admin = $false; Password = 'User123!' }
        @{ SamAccountName = 'ben.scout';   GivenName = 'Ben';   Surname = 'Scout';  OU = 'Studenten';    Admin = $false; Password = 'User123!' }
    )
}
