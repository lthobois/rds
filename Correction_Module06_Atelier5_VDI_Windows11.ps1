## Correction - Atelier 5 : collection VDI Windows 11
## Prerequis : le module precedent a ete joue.

. "$PSScriptRoot\Correction_Commun.ps1"

#region Atelier 5

$ErrorActionPreference = "Stop"

# 64 Go : deux hotes de virtualisation. 32 Go : RDS-HYPERV1 seul, hotes de session, CBROKER2 et GATEWAY2 eteints.
$MemoirePhysique = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
$DeuxHotes = $MemoirePhysique -ge 48
$Hotes = if ($DeuxHotes) { "RDS-HYPERV1", "RDS-HYPERV2" } else { "RDS-HYPERV1" }
$MemoireHote = if ($DeuxHotes) { 12GB } else { 8GB }

# Controles bloquants avant toute creation
# W11-GOLD se construit a partir de l'image Windows 11 FR du dossier _Template de la machine physique
$Image = "C:\VirtualMachines\_Template\Windows11FR.vhdx"
if (-not (Test-Path $Image))
    { throw "L'image $Image est introuvable." }


# Liberer la memoire : hotes de virtualisation eventuellement deja demarres, WSL et, en 32 Go, les machines inutiles
foreach ($VMName in $Hotes) { Get-VM -Name $VMName -ErrorAction SilentlyContinue | Stop-VM -Force }
if (-not $DeuxHotes) {
    wsl --shutdown
    Stop-VM -Name RDS-SESSION1, RDS-SESSION2, RDS-SESSION3, RDS-SESSION4, RDS-CBROKER2, RDS-GATEWAY2 -ErrorAction SilentlyContinue
    Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
        Remove-DnsServerResourceRecord -ZoneName "avaedos.lan" -Name "rds-farm" -RRType A -RecordData 172.16.1.116 -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 5
}
$LibreGo = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
if ($LibreGo -lt ($MemoireHote / 1GB + 1))
    { throw ("Memoire libre insuffisante : {0:N1} Go libres pour {1} Go a reserver. Fermez des applications ou eteignez des machines." -f $LibreGo, ($MemoireHote / 1GB)) }

# Virtualisation imbriquee, memoire statique et usurpation MAC : machine arretee, avant le premier demarrage
foreach ($VMName in $Hotes) {
    if (-not (Get-VM -Name $VMName -ErrorAction SilentlyContinue))
        { Deploy-VMTemplate -Name $VMName -OperatingSystem Windows2025Full -IsStart $false }
    Set-VMProcessor -VMName $VMName -Count 4 -ExposeVirtualizationExtensions $true
    Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -StartupBytes $MemoireHote
    Get-VMNetworkAdapter -VMName $VMName | Set-VMNetworkAdapter -MacAddressSpoofing On
    Start-VM -Name $VMName
    Wait-VMToStart -VMName $VMName
}

# Sans VT-x expose au processeur virtuel, Hyper-V ne s'installe pas sur l'hote
foreach ($VMName in $Hotes) {
    $VtX = Invoke-Command -VMName $VMName -Credential $CredLocal -ScriptBlock { (Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled }
    if (-not $VtX) { throw "$VMName : la virtualisation imbriquee n'est pas exposee (VirtualizationFirmwareEnabled = False). Voir le tableau des erreurs frequentes de l'atelier." }
}

$Serveurs = [ordered]@{ "RDS-HYPERV1" = "172.16.1.121" }
if ($DeuxHotes) { $Serveurs["RDS-HYPERV2"] = "172.16.1.122" }

foreach ($VMName in $Serveurs.Keys) {
    Write-Host "Configuration de $VMName" -ForegroundColor Cyan
    Get-VMIntegrationService -VMName $VMName | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
    Invoke-Command -VMName $VMName -Credential $CredLocal -ScriptBlock { C:\Windows\System32\slmgr.vbs /rearm }
    Reboot-VMComputer -VMName $VMName
    Configure-VM -VMName $VMName -Credential $CredLocal -IPAddress $Serveurs[$VMName] -PrefixLength 16 -DNSServer "172.16.1.1" -DomainName "avaedos.lan" -CredDomain $CredDomain -DefaultGateway "172.16.1.254"
}

Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    foreach ($Nom in $using:Hotes) {
        $Computer = Get-ADComputer -Identity $Nom
        Move-ADObject -Identity $Computer.DistinguishedName -TargetPath "OU=RD Servers,DC=avaedos,DC=lan"
        Add-ADGroupMember -Identity "RDS Servers" -Members $Computer
    }
}
foreach ($VMName in $Serveurs.Keys) { Reboot-VMComputer -VMName $VMName }

Write-Host "Ajout des hôtes de virtualisation" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-CBROKER1" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    # Ajoute le role d'hote de virtualisation au deploiement existant
    $Fqdn = $using:Hotes | ForEach-Object { "$($_.ToLower()).avaedos.lan" }
    New-RDVirtualDesktopDeployment -ConnectionBroker $using:Broker -VirtualizationHost $Fqdn
}

# Add-RDServer redemarre les hotes : attendre qu'Hyper-V soit installe et l'hote joignable
foreach ($VMName in $Hotes) {
    do { Start-Sleep -Seconds 15
         $Etat = Invoke-Command -VMName $VMName -Credential $CredDomain -ScriptBlock { (Get-WindowsFeature Hyper-V).InstallState } -ErrorAction SilentlyContinue
    } until ($Etat -eq "Installed")
}

Write-Host "Commutateur virtuel VDI" -ForegroundColor Cyan
Invoke-Command -VMName $Hotes -Credential $CredDomain -ScriptBlock {
    $Nic = (Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1).Name
    New-VMSwitch -Name "VDI" -NetAdapterName $Nic -AllowManagementOS $true
    New-Item -ItemType Directory -Path C:\VDI -Force | Out-Null
}

Write-Host "Creation de la machine modèle W11-GOLD sur RDS-HYPERV1" -ForegroundColor Cyan
Get-VMIntegrationService -VMName "RDS-HYPERV1" | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
Copy-VMFile -Name "RDS-HYPERV1" -SourcePath $Image -DestinationPath "C:\AVAEDOS\_RDS\W11-GOLD\W11-GOLD.vhdx" -CreateFullPath -FileSource Host -Force
Invoke-Command -VMName "RDS-HYPERV1" -Credential $CredDomain -ScriptBlock {
    # Preparation hors ligne : Bureau a distance actif, pare-feu ouvert, groupe RDS VDI Users autorise
    $Disque = "C:\AVAEDOS\_RDS\W11-GOLD\W11-GOLD.vhdx"
    $Lecteur = (Mount-VHD -Path $Disque -Passthru | Get-Disk | Get-Partition | Get-Volume |
        Where-Object { $_.DriveLetter -and (Test-Path "$($_.DriveLetter):\Windows") }).DriveLetter
    New-Item -ItemType Directory -Path "${Lecteur}:\Windows\Setup\Scripts" -Force | Out-Null
    $Commande = @'
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0; Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'; Add-LocalGroupMember -SID S-1-5-32-555 -Member 'AVAEDOS\RDS VDI Users'"
'@
    Set-Content -Path "${Lecteur}:\Windows\Setup\Scripts\SetupComplete.cmd" -Value $Commande -Encoding Ascii
    Dismount-VHD -Path $Disque
}
Invoke-Command -VMName "RDS-HYPERV1" -Credential $CredDomain -ScriptBlock {
    New-VM -Name W11-GOLD -Generation 2 -MemoryStartupBytes 2GB -Path C:\AVAEDOS\_RDS -VHDPath C:\AVAEDOS\_RDS\W11-GOLD\W11-GOLD.vhdx -SwitchName "VDI"
    Set-VMProcessor -VMName W11-GOLD -Count 2
    Set-VMMemory -VMName W11-GOLD -DynamicMemoryEnabled $true -MinimumBytes 1GB -StartupBytes 2GB -MaximumBytes 4GB
    Set-VMKeyProtector -VMName W11-GOLD -NewLocalKeyProtector
    Enable-VMTPM -VMName W11-GOLD
    # Le modele reste arrete : l'image est deja generalisee, la demarrer annulerait la generalisation
}

Write-Host "Délégation de la création des comptes des postes VDI" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    dsacls "OU=RD VDI,DC=avaedos,DC=lan" /G "AVAEDOS\RDS Servers:CCDC;computer"
    dsacls "OU=RD VDI,DC=avaedos,DC=lan" /I:S /G "AVAEDOS\RDS Servers:GA;;computer"
}

Write-Host "Création de la collection VDI" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-CBROKER1" -Credential $CredDomain -ScriptBlock {
    Import-Module RemoteDesktop
    $Allocation = if ($using:DeuxHotes) { @{"rds-hyperv1.avaedos.lan" = 1; "rds-hyperv2.avaedos.lan" = 1} } else { @{"rds-hyperv1.avaedos.lan" = 2} }
    New-RDVirtualDesktopCollection -CollectionName "RdsVdiColl1" -PooledManaged -VirtualDesktopTemplateName "W11-GOLD" -VirtualDesktopTemplateHostServer rds-hyperv1.avaedos.lan -VirtualDesktopAllocation $Allocation -StorageType LocalStorage -LocalStoragePath "C:\VDI" -VirtualDesktopNamePrefix "VDI" -Domain "avaedos.lan" -OU "RD VDI" -UserGroups "AVAEDOS\RDS VDI Users" -ConnectionBroker $using:Broker
    Get-RDVirtualDesktop -CollectionName "RdsVdiColl1" -ConnectionBroker $using:Broker
}

#endregion
