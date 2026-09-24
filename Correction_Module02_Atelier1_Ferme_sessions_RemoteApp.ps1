## Correction - Atelier 1 : ferme de sessions et RemoteApp
## Prerequis : le module precedent a ete joue.

. "$PSScriptRoot\Correction_Commun.ps1"

#region Configuration des machines de la ferme et du poste client

# Les machines ont ete deployees par le script du module 0 : il reste a les configurer.
$Serveurs = [ordered]@{
    "RDS-SESSION1" = "172.16.1.111"
    "RDS-SESSION2" = "172.16.1.112"
    "RDS-SESSION3" = "172.16.1.113"
    "RDS-SESSION4" = "172.16.1.114"
    "RDS-CBROKER1" = "172.16.1.115"
    "RDS-GATEWAY1" = "172.16.1.117"
}

foreach ($VMName in $Serveurs.Keys) {
    Write-Host "Configuration de $VMName" -ForegroundColor Cyan
    Get-VMIntegrationService -VMName $VMName | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
    Invoke-Command -VMName $VMName -Credential $CredLocal -ScriptBlock { C:\Windows\System32\slmgr.vbs /rearm }
    Reboot-VMComputer -VMName $VMName
    Configure-VM -VMName $VMName -Credential $CredLocal -IPAddress $Serveurs[$VMName] -PrefixLength 16 -DNSServer "172.16.1.1" -DomainName "avaedos.lan" -CredDomain $CredDomain -DefaultGateway "172.16.1.254"
}

Write-Host "Unite d'organisation RD Servers et groupe RDS Servers" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ArgumentList (, [string[]]$Serveurs.Keys) -ScriptBlock {
    param($Serveurs)
    foreach ($Nom in $Serveurs) {
        $Computer = Get-ADComputer -Identity $Nom
        Move-ADObject -Identity $Computer.DistinguishedName -TargetPath "OU=RD Servers,DC=avaedos,DC=lan"
        Add-ADGroupMember -Identity "RDS Servers" -Members $Computer
    }
}
foreach ($VMName in $Serveurs.Keys) { Reboot-VMComputer -VMName $VMName }

$VMName = "RDS-CLI1"
if ((Get-VM -Name $VMName).State -ne "Running") { Start-VM -Name $VMName }

Configure-VM -VMName $VMName -Credential $CredWorkstation -IPAddress "172.16.1.101" -PrefixLength 16 -DNSServer "172.16.1.1" -DomainName "avaedos.lan" -CredDomain $CredDomain -DefaultGateway "172.16.1.254"

Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    $Computer = Get-ADComputer -Identity "RDS-CLI1"
    Move-ADObject -Identity $Computer.DistinguishedName -TargetPath "OU=RD Clients,DC=avaedos,DC=lan"
}

#endregion

#region Atelier 1

Write-Host "Installation de la ferme RDS" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-CBROKER1" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    New-RDSessionDeployment -ConnectionBroker $using:Broker -WebAccessServer rds-gateway1.avaedos.lan -SessionHost rds-session1.avaedos.lan,rds-session2.avaedos.lan,rds-session3.avaedos.lan,rds-session4.avaedos.lan
}

Write-Host "Configuration du serveur de licence" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-CBROKER1" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    Add-RDServer -Server $using:Broker -Role RDS-LICENSING -ConnectionBroker $using:Broker
    Set-RDLicenseConfiguration -LicenseServer $using:Broker -Mode PerUser -ConnectionBroker $using:Broker -Force
    Get-RDLicenseConfiguration -ConnectionBroker $using:Broker
}

Write-Host "Certificat du déploiement" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-CBROKER1" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    gpupdate /force | Out-Null
    New-Item -ItemType Directory -Path C:\Certificats -Force | Out-Null
    $Request = Get-Certificate -Template WebServerRDS -SubjectName "CN=rds.avaedos.lan" -DnsName rds.avaedos.lan,rds-farm.avaedos.lan,rds-cbroker1.avaedos.lan,rds-cbroker2.avaedos.lan,rds-gateway1.avaedos.lan,rds-gateway2.avaedos.lan -CertStoreLocation Cert:\LocalMachine\My
    Export-PfxCertificate -Cert $Request.Certificate -FilePath C:\Certificats\rds-avaedos.pfx -Password $using:password
    Export-Certificate -Cert $Request.Certificate -FilePath C:\Certificats\rds-avaedos.cer
    foreach ($Role in "RDRedirector","RDPublishing","RDWebAccess") {
        Set-RDCertificate -Role $Role -ImportPath C:\Certificats\rds-avaedos.pfx -Password $using:password -ConnectionBroker $using:Broker -Force
    }
    Get-RDCertificate -ConnectionBroker $using:Broker
}

Write-Host "Création des collections" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-CBROKER1" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    New-RDSessionCollection -CollectionName "RdsSesColl1" -CollectionDescription "Bureaux de session" -SessionHost rds-session1.avaedos.lan,rds-session2.avaedos.lan -ConnectionBroker $using:Broker
    Set-RDSessionCollectionConfiguration -CollectionName "RdsSesColl1" -UserGroup "AVAEDOS\RDS Users" -ConnectionBroker $using:Broker

    New-RDSessionCollection -CollectionName "RdsAppColl1" -CollectionDescription "Applications RemoteApp" -SessionHost rds-session3.avaedos.lan,rds-session4.avaedos.lan -ConnectionBroker $using:Broker
    Set-RDSessionCollectionConfiguration -CollectionName "RdsAppColl1" -UserGroup "AVAEDOS\RDS Users" -ConnectionBroker $using:Broker
}

Write-Host "Configuration d'une collection d'application" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-CBROKER1" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    # WordPad n'existe plus dans Windows Server 2025
    New-RDRemoteApp -Alias Notepad -DisplayName "Bloc-notes" -FilePath "C:\Windows\System32\notepad.exe" -ShowInWebAccess $true -CollectionName "RdsAppColl1" -ConnectionBroker $using:Broker
    New-RDRemoteApp -Alias Charmap -DisplayName "Table des caractères" -FilePath "C:\Windows\System32\charmap.exe" -ShowInWebAccess $true -CollectionName "RdsAppColl1" -ConnectionBroker $using:Broker
    Get-RDRemoteApp -ConnectionBroker $using:Broker
}

#endregion
