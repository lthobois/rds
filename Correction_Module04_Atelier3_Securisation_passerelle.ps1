## Correction - Atelier 3 : securisation et passerelle
## Prerequis : le module precedent a ete joue.

. "$PSScriptRoot\Correction_Commun.ps1"

#region Atelier 3

Write-Host "Stratégie GPO RD Clients SSO : SSO et éditeur approuvé" -ForegroundColor Cyan
$Thumbprint = Invoke-Command -VMName "RDS-CBROKER1" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    (Get-RDCertificate -Role RDPublishing -ConnectionBroker $using:Broker).Thumbprint
}
Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    New-GPO -Name "GPO RD Clients SSO" | New-GPLink -Target "OU=RD Clients,DC=avaedos,DC=lan"
    # Délégation des informations d'identification par défaut vers TERMSRV/*.avaedos.lan
    $Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation"
    Set-GPRegistryValue -Name "GPO RD Clients SSO" -Key $Key -ValueName "AllowDefaultCredentials" -Type DWord -Value 1
    Set-GPRegistryValue -Name "GPO RD Clients SSO" -Key $Key -ValueName "ConcatenateDefaults_AllowDefault" -Type DWord -Value 1
    Set-GPRegistryValue -Name "GPO RD Clients SSO" -Key "$Key\AllowDefaultCredentials" -ValueName "1" -Type String -Value "TERMSRV/*.avaedos.lan"
    # Editeur approuvé et blocage des fichiers RDP d'éditeurs inconnus (valeurs à contrôler dans la console)
    $Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
    Set-GPRegistryValue -Name "GPO RD Clients SSO" -Key $Key -ValueName "TrustedCertThumbprints" -Type String -Value $using:Thumbprint
    Set-GPRegistryValue -Name "GPO RD Clients SSO" -Key $Key -ValueName "AllowUnsignedFiles" -Type DWord -Value 0
}

Write-Host "Ajout de la passerelle" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-CBROKER1" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    Add-RDServer -Server rds-gateway1.avaedos.lan -Role RDS-GATEWAY -ConnectionBroker $using:Broker -GatewayExternalFqdn rds.avaedos.lan
    Set-RDCertificate -Role RDGateway -ImportPath C:\Certificats\rds-avaedos.pfx -Password $using:password -ConnectionBroker $using:Broker -Force
    Set-RDDeploymentGatewayConfiguration -GatewayMode Custom -GatewayExternalFqdn rds.avaedos.lan -LogonMethod Password -UseCachedCredentials $true -BypassLocal $false -ConnectionBroker $using:Broker -Force
}
Write-Host "Restreindre la CAP et la RAP de RDS-GATEWAY1 au groupe AVAEDOS\RDS Users (tsgateway.msc)" -ForegroundColor Red
Read-Host -Prompt "CAP et RAP restreintes ?"

Write-Host "Installation du client web sur RDS-GATEWAY1" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-GATEWAY1" -Credential $CredDomain -ScriptBlock {
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

#endregion
