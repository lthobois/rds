## Correction - Preparation de l'environnement
## Premier script a jouer : il deploie les machines et construit le domaine.

. "$PSScriptRoot\Correction_Commun.ps1"

#region Deploiement des machines virtuelles

Deploy-VMTemplate -Name RDS-DC1 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-CBROKER1 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-SESSION1 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-SESSION2 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-CLI1 -OperatingSystem Windows11FR

Deploy-VMTemplate -Name RDS-SESSION3 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-SESSION4 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-CBROKER2 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-GATEWAY1 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-GATEWAY2 -OperatingSystem Windows2025Full

#endregion

#region Preparation - RDS-DC1

$VMName = "RDS-DC1"
Wait-VMToStart -VMName $VMName
Get-VMIntegrationService -VMName $VMName | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService

Write-Host "Activation Windows" -ForegroundColor Cyan
Invoke-Command -VMName $VMName -Credential $CredLocal -ScriptBlock { C:\Windows\System32\slmgr.vbs /rearm }
Reboot-VMComputer -VMName $VMName

Configure-VM -VMName $VMName -Credential $CredLocal -IPAddress "172.16.1.1" -PrefixLength 16 -DNSServer "172.16.1.1" -DefaultGateway "172.16.1.254"

Write-Host "Installation Active directory : $(Get-Date)" -ForegroundColor Cyan
Invoke-Command -VMName $VMName -Credential $CredLocal -ScriptBlock {
    Add-WindowsFeature AD-Domain-Services -IncludeManagementTools
}
Reboot-VMComputer -VMName $VMName

Write-Host "Configuration Active directory : $(Get-Date)" -ForegroundColor Cyan
Invoke-Command -VMName $VMName -Credential $CredLocal -ScriptBlock {
    Install-ADDSForest -CreateDNSDelegation:$false -DatabasePath "C:\Windows\NTDS" -DomainMode Win2025 -DomainName "avaedos.lan" -DomainNetbiosName "AVAEDOS" -ForestMode Win2025 -InstallDns:$true -LogPath "C:\Windows\NTDS" -SafeModeAdministratorPassword $($using:password) -SysvolPath "C:\Windows\SYSVOL" -Force:$true -NoRebootOnCompletion
    Restart-Computer
}

Write-Host "Sleep 420 seconds" -ForegroundColor Magenta
Start-SleepWithProgress -Seconds 420 -Title "Configuration AD"

Write-Host "Finalisation / Unités d'organisation, comptes et groupes" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    # Démarrage du web service AD
    Set-Service -Name ADWS -StartupType Automatic
    Start-Service -Name ADWS

    Import-Module ActiveDirectory
    "RD Users","RD Servers","RD Clients","RD VDI" | ForEach-Object { New-ADOrganizationalUnit -Name $_ -Path "DC=avaedos,DC=lan" }

    $Pwd = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
    New-ADUser -Name "Loïc THOBOIS" -SamAccountName "lthobois" -UserPrincipalName "lthobois@avaedos.lan" -DisplayName "Loïc THOBOIS" -Path "OU=RD Users,DC=avaedos,DC=lan" -CannotChangePassword $true -PasswordNeverExpires $true -AccountPassword $Pwd -Enabled $true
    New-ADUser -Name "Brahim NEDJIMI" -SamAccountName "bnedjimi" -UserPrincipalName "bnedjimi@avaedos.lan" -DisplayName "Brahim NEDJIMI" -Path "OU=RD Users,DC=avaedos,DC=lan" -CannotChangePassword $true -PasswordNeverExpires $true -AccountPassword $Pwd -Enabled $true

    New-ADGroup -Name "RDS Users" -GroupScope Global -Path "OU=RD Users,DC=avaedos,DC=lan"
    New-ADGroup -Name "RDS VDI Users" -GroupScope Global -Path "OU=RD Users,DC=avaedos,DC=lan"
    New-ADGroup -Name "RDS Servers" -GroupScope Global -Path "OU=RD Servers,DC=avaedos,DC=lan"
    Add-ADGroupMember -Identity "RDS Users" -Members lthobois, bnedjimi
    Add-ADGroupMember -Identity "RDS VDI Users" -Members bnedjimi

    # Outils d'administration RSAT
    Add-WindowsFeature RSAT-Role-Tools,RSAT-AD-Tools,RSAT-AD-PowerShell,RSAT-ADDS,RSAT-AD-AdminCenter
}

Write-Host "DNS, DHCP, autorité de certification et partages" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    # Nom d'accès des utilisateurs : RDS-GATEWAY1, puis la ferme de passerelles (atelier 4)
    Add-DnsServerResourceRecordA -Name "rds" -ZoneName "avaedos.lan" -IPv4Address "172.16.1.117"

    # DHCP pour les postes VDI (atelier 5)
    Install-WindowsFeature DHCP -IncludeManagementTools
    Add-DhcpServerSecurityGroup
    Restart-Service DHCPServer
    Add-DhcpServerInDC -DnsName "RDS-DC1.avaedos.lan" -IPAddress 172.16.1.1
    Add-DhcpServerv4Scope -Name "Postes VDI" -StartRange 172.16.1.200 -EndRange 172.16.1.250 -SubnetMask 255.255.0.0
    Set-DhcpServerv4OptionValue -DnsServer 172.16.1.1 -DnsDomain "avaedos.lan" -Router 172.16.1.254

    # Autorité de certification d'entreprise
    Install-WindowsFeature -Name Adcs-Cert-Authority -IncludeManagementTools
    Install-AdcsCertificationAuthority -CAType EnterpriseRootCA -CACommonName "RDS-CA" -KeyLength 2048 -HashAlgorithm SHA256 -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" -Force

    # Partage des profils FSLogix (autorisations NTFS réglées à l'atelier 2)
    New-Item -Path "C:\ProfilDisk" -ItemType Directory -Force
    New-SmbShare -Name "ProfilDisk" -Path "C:\ProfilDisk" -FullAccess "AVAEDOS\Domain Admins" -ChangeAccess "AVAEDOS\RDS Users"
}
Reboot-VMComputer -VMName $VMName

Write-Host "Modèle de certificat WebServer RDS" -ForegroundColor Cyan
# Duplication du modele Web Server en version 2, avec cle exportable et sujet fourni par le
# demandeur, puis publication sur RDS-CA. Equivalent en ligne de commande de certtmpl.msc.
# Valide sur la maquette le 2026-09-22 : objet OID cree, modele cree, Enroll accorde a
# Domain Computers, modele publie sur RDS-CA. En cas d'echec, faire la duplication dans
# certtmpl.msc comme le decrit l'atelier, puis reprendre au bloc suivant.
Invoke-Command -VMName $VMName -Credential $CredDomain -ScriptBlock {
    Import-Module ActiveDirectory
    $Config = (Get-ADRootDSE).configurationNamingContext
    $Base = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$Config"

    if (Get-ADObject -SearchBase $Base -Filter "cn -eq 'WebServerRDS'" -ErrorAction SilentlyContinue) {
        "Modele WebServerRDS deja present"
    }
    else {
        # OID unique, derive de l'OID de la foret
        $OidRoot = (Get-ADObject -Identity "CN=OID,CN=Public Key Services,CN=Services,$Config" -Properties "msPKI-Cert-Template-OID")."msPKI-Cert-Template-OID"
        $Oid = "$OidRoot.$(Get-Random -Minimum 1000000 -Maximum 99999999).$(Get-Random -Minimum 10000000 -Maximum 99999999)"
        New-ADObject -Name "WebServerRDS" -Type "msPKI-Enterprise-Oid" `
            -Path "CN=OID,CN=Public Key Services,CN=Services,$Config" `
            -OtherAttributes @{
                "msPKI-Cert-Template-OID" = $Oid
                "flags"                   = [int]1
                "displayName"             = "WebServer RDS"
            } | Out-Null

        # Le modele reprend Web Server, en version de schema 2
        $Source = Get-ADObject -SearchBase $Base -Filter "cn -eq 'WebServer'" -Properties *
        New-ADObject -Name "WebServerRDS" -Type "pKICertificateTemplate" -Path $Base -OtherAttributes @{
            "displayName"                     = "WebServer RDS"
            "flags"                           = [int]66112
            "revision"                        = [int]100
            "msPKI-Template-Schema-Version"   = [int]2
            "msPKI-Template-Minor-Revision"   = [int]1
            "msPKI-Cert-Template-OID"         = $Oid
            "msPKI-Certificate-Name-Flag"     = [int]1          # le demandeur fournit le sujet et les noms DNS
            "msPKI-Enrollment-Flag"           = [int]0
            "msPKI-Private-Key-Flag"          = [int]16         # cle privee exportable
            "msPKI-Minimal-Key-Size"          = [int]2048
            "msPKI-RA-Signature"              = [int]0
            "pKIDefaultKeySpec"               = [int]1
            "pKIMaxIssuingDepth"              = [int]0
            "pKICriticalExtensions"           = $Source.pKICriticalExtensions
            "pKIExtendedKeyUsage"             = $Source.pKIExtendedKeyUsage
            # Fournisseur de stockage de cles (CNG) uniquement : les roles RDS refusent un certificat
            # emis via un fournisseur cryptographique herite (CSP), copie sinon du modele WebServer d'origine.
            "pKIDefaultCSPs"                  = @("1,Microsoft Software Key Storage Provider")
            "pKIKeyUsage"                     = $Source.pKIKeyUsage
            "pKIExpirationPeriod"             = $Source.pKIExpirationPeriod
            "pKIOverlapPeriod"                = $Source.pKIOverlapPeriod
        } | Out-Null

        # Autorisation Enroll pour Domain Computers
        $Modele = "AD:\CN=WebServerRDS,$Base"
        $Acl = Get-Acl $Modele
        $Sid = (Get-ADGroup "Domain Computers").SID
        $Enroll = [GUID]"0e10c968-78fb-11d2-90d4-00c04f79dc55"
        $Acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $Sid, "GenericRead", "Allow")))
        $Acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $Sid, "ExtendedRight", "Allow", $Enroll)))
        Set-Acl -Path $Modele -AclObject $Acl
        "Modele WebServerRDS cree"
    }

    # Publication sur l'autorite
    certutil -SetCATemplates +WebServerRDS | Out-Null
    (certutil -CATemplates | Select-String "WebServerRDS")
}

#endregion
