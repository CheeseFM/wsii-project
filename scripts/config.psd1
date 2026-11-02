# Central configuration for the WS-II environment.
# Every script reads this file via common\config.ps1 -> Get-LabConfig.
# Change values here only; never hardcode IPs/names in the scripts themselves.
#
# Note: a .psd1 is pure data, so values cannot reference each other.
# Scripts derive related values (e.g. DNS server IPs) from the Nodes section.

@{
    Domain = @{
        Name           = 'WS26-JDV.hogent'
        NetBiosName    = 'WS26-JDV'
        ForestMode     = 'Win2025'
        DomainMode     = 'Win2025'
        # Lab environment only - documented in readme.pdf
        SafeModePassword = 'Vagrant123!'
        # Local Administrator on server1 = domain Administrator after promotion
        AdministratorPassword = 'Vagrant123!'
    }

    Network = @{
        # Host-only network. VirtualBox DHCP on this network must be disabled.
        NetworkId    = '192.168.26.0'
        PrefixLength = 24
        # No default gateway on the host-only adapter: internet goes via NAT.

        # VirtualBox NAT always hands out 10.0.2.x; used to tell the adapters apart.
        NatSubnet    = '10.0.2.*'
    }

    # Keys match the VM names in the Vagrantfile (vagrant up server1, ...).
    Nodes = @{
        server1 = @{
            Hostname = 'ad-web-dns'
            IP       = '192.168.26.10'
        }
        server2 = @{
            Hostname = 'sec-dns'
            IP       = '192.168.26.20'
        }
        server3 = @{
            Hostname = 'ca-dhcp'
            IP       = '192.168.26.30'
        }
        client = @{
            Hostname = 'client'
            IP       = $null    # dynamic, via DHCP on server3
        }
    }

    Dns = @{
        PrimaryNode   = 'server1'
        SecondaryNode = 'server2'
        ReverseZone   = '26.168.192.in-addr.arpa'
        # Empty = root hints via NAT (tested: works). Don't use the host's DNS
        # servers here: they only exist on that one network.
        Forwarders    = @()
        # Extra records on top of the A/PTR per server.
        # CNAME so each server keeps exactly one A record.
        Records = @(
            @{ Name = 'intranet'; Type = 'CNAME'; Target = 'ad-web-dns' }
        )
    }

    Dhcp = @{
        ScopeName      = 'Host-only clients'
        StartRange     = '192.168.26.100'
        EndRange       = '192.168.26.200'
        SubnetMask     = '255.255.255.0'
        ExclusionStart = '192.168.26.151'
        ExclusionEnd   = '192.168.26.200'
        LeaseDuration  = '8.00:00:00'
        # Options: 006 DNS servers (primary + secondary) and 015 DNS domain name.
        # 003 Router is deliberately omitted: the host-only network has no uplink.
    }

    Ca = @{
        CommonName    = 'WS26-JDV-Root-CA'
        Type          = 'EnterpriseRootCa'
        ValidityYears = 5
        GpoName       = 'Trust WS26-JDV Root CA'
    }

    Iis = @{
        SiteName = 'Intranet'
        HostName = 'intranet'    # + Domain.Name -> intranet.WS26-JDV.hogent
        Port     = 80
    }

    # Inbound firewall per node. Default policy: block inbound, allow outbound.
    # Groups = built-in Windows firewall rule groups (DisplayGroup), enabled as a whole.
    #   Some groups only exist after the matching role is installed,
    #   so apply the firewall at the end of each server script.
    # Rules  = custom rules for traffic without a suitable built-in group.
    Firewall = @{
        DefaultInbound  = 'Block'
        DefaultOutbound = 'Allow'

        # Applied on every server
        Common = @{
            Groups = @(
                'Windows Remote Management'    # WinRM 5985: Vagrant + remote PowerShell
            )
            Rules = @(
                @{ Name = 'WS2-Ping-In'; Protocol = 'ICMPv4'; IcmpType = '8' }
            )
        }

        server1 = @{
            Groups = @(
                'Active Directory Domain Services'    # LDAP, GC, RPC, SMB (SYSVOL/GPO), W32Time
                'Active Directory Web Services'       # 9389: RSAT AD PowerShell / ADAC
                'Kerberos Key Distribution Center'    # 88: authentication
                'DNS Service'                         # 53 + RPC for DNS Manager
                'World Wide Web Services (HTTP)'      # 80: intranet site
            )
            Rules = @()
        }

        server2 = @{
            Groups = @(
                'DNS Service'                         # 53 (queries + zone transfer) + RPC
            )
            Rules = @()
        }

        server3 = @{
            Groups = @(
                'DHCP Server'                         # 67/68 + RPC for DHCP console
                'Certification Authority'             # RPC/DCOM certificate requests
                'World Wide Web Services (HTTP)'      # 80: /CertSrv web enrollment
            )
            Rules = @()
        }
    }
}
