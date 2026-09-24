## Correction - Atelier 4 : haute disponibilite et diagnostic
## Prerequis : le module precedent a ete joue.

. "$PSScriptRoot\Correction_Commun.ps1"

#region Atelier 4

# RDS-CBROKER2 et RDS-GATEWAY2 ont ete deployes par le script du module 0 : il reste a les configurer.
$Serveurs = [ordered]@{
    "RDS-CBROKER2" = "172.16.1.116"
    "RDS-GATEWAY2" = "172.16.1.118"
}

foreach ($VMName in $Serveurs.Keys) {
    Write-Host "Configuration de $VMName" -ForegroundColor Cyan
    Get-VMIntegrationService -VMName $VMName | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
    Invoke-Command -VMName $VMName -Credential $CredLocal -ScriptBlock { C:\Windows\System32\slmgr.vbs /rearm }
    Reboot-VMComputer -VMName $VMName
    Configure-VM -VMName $VMName -Credential $CredLocal -IPAddress $Serveurs[$VMName] -PrefixLength 16 -DNSServer "172.16.1.1" -DomainName "avaedos.lan" -CredDomain $CredDomain -DefaultGateway "172.16.1.254"
}

Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    foreach ($Nom in "RDS-CBROKER2", "RDS-GATEWAY2") {
        $Computer = Get-ADComputer -Identity $Nom
        Move-ADObject -Identity $Computer.DistinguishedName -TargetPath "OU=RD Servers,DC=avaedos,DC=lan"
        Add-ADGroupMember -Identity "RDS Servers" -Members $Computer
    }
}
foreach ($VMName in $Serveurs.Keys) { Reboot-VMComputer -VMName $VMName }
# SQL Server est heberge sur RDS-DC1 : aucune machine supplementaire

Write-Host "Nom de ferme des Connection Brokers" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    Add-DnsServerResourceRecordA -Name "rds-farm" -ZoneName "avaedos.lan" -IPv4Address "172.16.1.115"
    Add-DnsServerResourceRecordA -Name "rds-farm" -ZoneName "avaedos.lan" -IPv4Address "172.16.1.116"
}

Write-Host "Installation de SQL Server 2025 Express sur le controleur de domaine" -ForegroundColor Cyan
# Sur un controleur de domaine, les services SQL exigent un compte de domaine (/SQLSVCACCOUNT)
Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    Start-Process "C:\AVAEDOS\_RDS\SQL\SQLEXPR_x64_ENU.exe" -Wait -ArgumentList '/Q /ACTION=Install /FEATURES=SQLEngine /INSTANCENAME=MSSQLSERVER /SQLSYSADMINACCOUNTS="AVAEDOS\Domain Admins" /SQLSVCACCOUNT="AVAEDOS\Administrator" /SQLSVCPASSWORD="P@ssw0rd" /TCPENABLED=1 /UPDATEENABLED=0 /IACCEPTSQLSERVERLICENSETERMS'
    New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow

    $Cnx = New-Object System.Data.SqlClient.SqlConnection "Server=localhost;Integrated Security=True;TrustServerCertificate=True"
    $Cnx.Open()
    $Cmd = $Cnx.CreateCommand()
    $Cmd.CommandText = "CREATE LOGIN [AVAEDOS\RDS Servers] FROM WINDOWS; ALTER SERVER ROLE dbcreator ADD MEMBER [AVAEDOS\RDS Servers];"
    $Cmd.ExecuteNonQuery()
    $Cnx.Close()
}

Write-Host "Pilote ODBC sur les Connection Brokers" -ForegroundColor Cyan
foreach ($VMName in "RDS-CBROKER1","RDS-CBROKER2") {
    Invoke-Command -VMName $VMName -Credential $CredDomain -ScriptBlock {
        # Le pilote ODBC exige le redistribuable Visual C++ : sans lui, erreur 1723 puis 1603
        Start-Process "C:\AVAEDOS\_RDS\ODBC\vc_redist.x64.exe" -Wait -ArgumentList "/install", "/quiet", "/norestart"
        Start-Process msiexec.exe -Wait -ArgumentList "/i C:\AVAEDOS\_RDS\ODBC\msodbcsql17.msi /qn IACCEPTMSODBCSQLLICENSETERMS=YES ALLUSERS=1"
        (Get-OdbcDriver | Where-Object Name -like "*Driver 17*").Name | Select-Object -First 1
    }
    Reboot-VMComputer -VMName $VMName
}

Write-Host "Haute disponibilité du Connection Broker" -ForegroundColor Cyan
# Le service RDMS met une a deux minutes a demarrer apres le redemarrage : sans cette attente,
# Set-RDConnectionBrokerHighAvailability echoue sur « A deployment is not present ».
Invoke-Command -VMName "RDS-CBROKER1" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    $Fin = (Get-Date).AddMinutes(8)
    do { Start-Sleep -Seconds 20 } until ((Get-RDServer -ConnectionBroker $using:Broker -ErrorAction SilentlyContinue) -or (Get-Date) -gt $Fin)
    Set-RDConnectionBrokerHighAvailability -ConnectionBroker $using:Broker -DatabaseConnectionString "DRIVER=ODBC Driver 17 for SQL Server;SERVER=rds-dc1.avaedos.lan;Trusted_Connection=Yes;APP=Remote Desktop Services Connection Broker;DATABASE=RDCB-DB" -ClientAccessName rds-farm.avaedos.lan
}

# La base appartient au premier broker : sans droit dans la base, le second est refuse
# (« The database is not reachable from the specified RD Connection Broker server »).
Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    $Cnx = New-Object System.Data.SqlClient.SqlConnection "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=RDCB-DB"
    $Cnx.Open()
    $Cmd = $Cnx.CreateCommand()
    $Cmd.CommandText = "CREATE USER [AVAEDOS\RDS Servers] FOR LOGIN [AVAEDOS\RDS Servers]; ALTER ROLE db_owner ADD MEMBER [AVAEDOS\RDS Servers];"
    $Cmd.ExecuteNonQuery()
    $Cnx.Close()
}

# Le deploiement lit la version du systeme par WMI : sans cette regle, l'ajout est refuse
# avec « has to be same OS version » alors que les deux serveurs sont identiques.
Invoke-Command -VMName "RDS-CBROKER2" -Credential $CredDomain -ScriptBlock {
    Enable-NetFirewallRule -DisplayGroup "Windows Management Instrumentation (WMI)"
}

# Tous les serveurs du deploiement doivent etre allumes pour l'ajout d'un Connection Broker
Invoke-Command -VMName "RDS-CBROKER1" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    Add-RDServer -Server rds-cbroker2.avaedos.lan -Role RDS-CONNECTION-BROKER -ConnectionBroker $using:Broker
    Get-RDConnectionBrokerHighAvailability -ConnectionBroker $using:Broker
}
# Le nom de ferme n'a pas de SPN : les commandes d'administration gardent le nom reel du broker

Write-Host "Ferme de passerelles et d'accès Web" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-CBROKER1" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    Add-RDServer -Server rds-gateway2.avaedos.lan -Role RDS-WEB-ACCESS -ConnectionBroker $using:Broker
    Add-RDServer -Server rds-gateway2.avaedos.lan -Role RDS-GATEWAY -ConnectionBroker $using:Broker -GatewayExternalFqdn rds.avaedos.lan
    foreach ($Role in "RDRedirector","RDPublishing","RDWebAccess","RDGateway") {
        Set-RDCertificate -Role $Role -ImportPath C:\Certificats\rds-avaedos.pfx -Password $using:password -ConnectionBroker $using:Broker -Force
    }
    Get-RDServer -ConnectionBroker $using:Broker
}
Write-Host "Restreindre la CAP et la RAP de RDS-GATEWAY2 et déclarer la ferme de passerelles (tsgateway.msc)" -ForegroundColor Red
Read-Host -Prompt "Stratégies de RDS-GATEWAY2 configurées ?"

Invoke-Command -VMName "RDS-GATEWAY2" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    New-Item -ItemType Directory -Path C:\Certificats -Force | Out-Null
    Copy-Item \\rds-cbroker1\C$\Certificats\rds-avaedos.cer C:\Certificats\ -Force
    # Voie hors ligne : le module et le paquet sont fournis dans C:\AVAEDOS\_RDS\WebClient
    $env:PSModulePath += ";C:\AVAEDOS\_RDS\WebClient"
    Import-Module RDWebClientManagement
    $Zip = (Get-ChildItem "C:\AVAEDOS\_RDS\WebClient\rdwebclient-*.zip" | Select-Object -Last 1).FullName
    Install-RDWebClientPackage -Source $Zip
    Import-RDWebClientBrokerCert C:\Certificats\rds-avaedos.cer
    Publish-RDWebClientPackage -Type Production -Latest
}

Write-Host "Configuration du NLB des passerelles" -ForegroundColor Cyan
Invoke-Command -VMName RDS-GATEWAY1,RDS-GATEWAY2 -Credential $CredDomain -ScriptBlock {
    Install-WindowsFeature NLB -IncludeManagementTools
}
Invoke-Command -VMName RDS-GATEWAY1 -Credential $CredDomain -ScriptBlock {
    $Nic = (Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1).Name
    New-NlbCluster -InterfaceName $Nic -ClusterPrimaryIP "172.16.1.119" -SubnetMask "255.255.0.0" -OperationMode Multicast -ClusterName "rds.avaedos.lan"
}
Invoke-Command -VMName RDS-GATEWAY2 -Credential $CredDomain -ScriptBlock {
    $Nic = (Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1).Name
    Get-NlbCluster -HostName "RDS-GATEWAY1" | Add-NlbClusterNode -NewNodeName "RDS-GATEWAY2" -NewNodeInterface $Nic
}
Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    Remove-DnsServerResourceRecord -ZoneName "avaedos.lan" -Name "rds" -RRType A -Force
    Add-DnsServerResourceRecordA -Name "rds" -ZoneName "avaedos.lan" -IPv4Address "172.16.1.119" -TimeToLive 01:00:00
}

#endregion
