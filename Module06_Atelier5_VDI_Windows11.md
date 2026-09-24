---
title: "Atelier 5 – Collection VDI Windows 11"
subtitle: "Module 6 : Postes de travail virtuels (VDI)"
author: "Loïc THOBOIS"
lang: fr-FR
---

Cet atelier se réalise individuellement, sur votre propre environnement. Il s'appuie sur le résultat de l'atelier précédent. Les conventions, le plan d'adressage et les comptes sont décrits dans le document de préparation (Module00_Preparation_environnement.md).

# Objectif

Répondre au besoin du bureau d'études : des postes virtuels Windows 11 regroupés, créés à partir d'un modèle unique, répartis sur un ou deux hôtes de virtualisation, selon la machine physique, et publiés dans le même portail que les sessions.

**Livrable :** la collection **RdsVdiColl1** fournit à **bnedjimi** un poste virtuel **VDI-** qui revient à son état initial après déconnexion.

# Choisir la configuration selon la machine physique

Chaque hôte de virtualisation réserve sa mémoire de façon statique : **12 Go** en configuration 64 Go, **8 Go** en configuration 32 Go. La mémoire de la machine physique détermine le nombre d'hôtes.

| Machine physique | Hôtes de virtualisation | Machines à éteindre avant l'atelier | Répartition des postes |
|---|---|---|---|
| **64 Go** | RDS-HYPERV1 et RDS-HYPERV2 | Aucune | VDI-0 sur RDS-HYPERV1, VDI-1 sur RDS-HYPERV2 |
| **32 Go** | RDS-HYPERV1 seul | RDS-SESSION1 à RDS-SESSION4, RDS-CBROKER2 et RDS-GATEWAY2 | VDI-0 et VDI-1 sur RDS-HYPERV1 |

Les étapes qui diffèrent sont signalées par les mentions **64 Go** et **32 Go**. Les autres s'appliquent aux deux configurations.

**Configuration 32 Go : préparez la machine.** La collection VDI ne dépend pas des hôtes de session, et RDS-GATEWAY1 suffit à servir le portail `rds.avaedos.lan`. Libérez d'abord la mémoire de la machine physique : quittez WSL (`wsl --shutdown`) et fermez les applications inutiles, car la mémoire d'un hôte est réservée au démarrage et le démarrage échoue avec l'erreur *Ressources système insuffisantes* (0x800705AA) s'il ne reste pas 8 Go libres. Éteignez ensuite proprement les machines inutiles, depuis la machine physique et avant de démarrer RDS-HYPERV1 :

```powershell
Stop-VM -Name RDS-SESSION1, RDS-SESSION2, RDS-SESSION3, RDS-SESSION4, RDS-CBROKER2, RDS-GATEWAY2
```

Le nom **rds-farm** est un tourniquet DNS entre les deux Connection Brokers. Sur RDS-DC1, supprimez l'enregistrement de RDS-CBROKER2 pour qu'aucun client ne soit dirigé vers une machine éteinte :

```powershell
Remove-DnsServerResourceRecord -ZoneName "avaedos.lan" -Name "rds-farm" -RRType A -RecordData 172.16.1.116 -Force
```

Les collections de sessions restent affichées dans le client web mais ne répondent plus : c'est sans conséquence pour cet atelier. Rallumez les machines et recréez l'enregistrement (`Add-DnsServerResourceRecordA -ZoneName "avaedos.lan" -Name "rds-farm" -IPv4Address 172.16.1.116`) avant de reprendre les ateliers qui les utilisent.

# Préparation des hôtes de virtualisation

## 1. \[MP\]Créez RDS-HYPERV1 et RDS-HYPERV2

Les hôtes de virtualisation exécutent eux-mêmes des machines virtuelles : ils exigent la virtualisation imbriquée, une mémoire statique et l'usurpation d'adresses MAC pour que les postes VDI accèdent au réseau. Ces réglages se font machine arrêtée, avant le premier démarrage.

**32 Go :** ne créez que RDS-HYPERV1, avec `-StartupBytes 8GB` au lieu de 12GB, et ignorez tout ce qui concerne RDS-HYPERV2 dans cette étape et les suivantes.

```powershell
Deploy-VMTemplate -Name RDS-HYPERV1 -OperatingSystem Windows2025Full -IsStart $false
Set-VMProcessor -VMName RDS-HYPERV1 -Count 4 -ExposeVirtualizationExtensions $true
Set-VMMemory -VMName RDS-HYPERV1 -DynamicMemoryEnabled $false -StartupBytes 12GB
Get-VMNetworkAdapter -VMName RDS-HYPERV1 | Set-VMNetworkAdapter -MacAddressSpoofing On
Start-VM -Name RDS-HYPERV1
Wait-VMToStart -VMName RDS-HYPERV1
Get-VMIntegrationService -VMName RDS-HYPERV1 | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
```

```powershell
Deploy-VMTemplate -Name RDS-HYPERV2 -OperatingSystem Windows2025Full -IsStart $false
Set-VMProcessor -VMName RDS-HYPERV2 -Count 4 -ExposeVirtualizationExtensions $true
Set-VMMemory -VMName RDS-HYPERV2 -DynamicMemoryEnabled $false -StartupBytes 12GB
Get-VMNetworkAdapter -VMName RDS-HYPERV2 | Set-VMNetworkAdapter -MacAddressSpoofing On
Start-VM -Name RDS-HYPERV2
Wait-VMToStart -VMName RDS-HYPERV2
Get-VMIntegrationService -VMName RDS-HYPERV2 | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
```

**Vérification :** `Get-VMProcessor -VMName RDS-HYPERV1 | Select-Object ExposeVirtualizationExtensions` renvoie **True**.

## 2. \[HV1\]\[HV2\]Configurez les hôtes de virtualisation

Chaque hôte reçoit son adresse IP et rejoint le domaine. Ouvrez une session avec le compte local **Administrator** et le mot de passe **P@ssw0rd**.

Sur RDS-HYPERV1 :

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.121 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
Start-Sleep -Seconds 5
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential "AVAEDOS\Administrator", $mdp
Add-Computer -DomainName "avaedos.lan" -NewName RDS-HYPERV1 -Credential $cred `
    -OUPath "OU=RD Servers,DC=avaedos,DC=lan" -Restart
```

Sur RDS-HYPERV2 :

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.122 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
Start-Sleep -Seconds 5
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential "AVAEDOS\Administrator", $mdp
Add-Computer -DomainName "avaedos.lan" -NewName RDS-HYPERV2 -Credential $cred `
    -OUPath "OU=RD Servers,DC=avaedos,DC=lan" -Restart
```

**Vérification :** dans la session de chaque hôte, `(Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled` renvoie **True**. Ce contrôle prouve que le processeur virtuel expose la virtualisation : l'étape 4 en dépend.

## 3. \[DC\]Ajoutez les hôtes au groupe RDS Servers

Sur RDS-DC1 :

```powershell
Add-ADGroupMember "RDS Servers" -Members "RDS-HYPERV1$", "RDS-HYPERV2$"
```

**32 Go :** `Add-ADGroupMember "RDS Servers" -Members "RDS-HYPERV1$"`.

## 4. \[CB1\]Ajoutez les hôtes de virtualisation au déploiement

Depuis RDS-CBROKER1, ajoutez au déploiement le rôle d'hôte de virtualisation, qui exécute les postes VDI :

```powershell
Import-Module RemoteDesktop
New-RDVirtualDesktopDeployment -ConnectionBroker rds-cbroker1.avaedos.lan `
    -VirtualizationHost rds-hyperv1.avaedos.lan, rds-hyperv2.avaedos.lan
```

Le rôle installe Hyper-V sur chaque hôte et le redémarre.

**32 Go :** `-VirtualizationHost rds-hyperv1.avaedos.lan`, sans second hôte.

**Vérification :** sur chaque hôte, `Get-WindowsFeature Hyper-V` est à l'état **Installed**.

## 5. \[HV1\]\[HV2\]Créez le commutateur virtuel des postes VDI

Les postes virtuels doivent rejoindre le réseau d'Avaedos pour joindre le domaine et obtenir une adresse DHCP. Le commutateur porte le même nom sur les deux hôtes (**64 Go**) ; en **32 Go**, créez-le sur RDS-HYPERV1 seul.

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1).Name
New-VMSwitch -Name "VDI" -NetAdapterName $carte -AllowManagementOS $true
New-Item -ItemType Directory -Path C:\VDI -Force
```

Le dossier **C:\\VDI** accueille les disques des postes virtuels créés sur l'hôte.

La connexion réseau de l'hôte est brièvement interrompue pendant la création du commutateur.

## 6. \[MP\]Copiez l'image du modèle W11-GOLD dans RDS-HYPERV1

Aucun modèle VDI n'est fourni : vous le créez à partir de l'image **Windows11FR.vhdx**, celle qui sert à déployer RDS-CLI1, dans le dossier **C:\\VirtualMachines\\_Template** de la machine physique. Cette image est un Windows 11 Pro, édition suffisante pour l'atelier, déjà généralisée, et porte le fichier de réponse **Win11_ent_x64.xml** (paramètres régionaux en français, compte local **User**, mot de passe **P@ssw0rd**). Elle sert de disque au modèle, qui ne démarre jamais : chaque poste VDI appliquera le fichier de réponse à son premier démarrage.

Copiez l'image dans RDS-HYPERV1 depuis la machine physique :

```powershell
$image = "C:\VirtualMachines\_Template\Windows11FR.vhdx"
Get-VMIntegrationService -VMName RDS-HYPERV1 | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
Copy-VMFile -Name RDS-HYPERV1 -SourcePath $image -FileSource Host -CreateFullPath -Force `
    -DestinationPath "C:\AVAEDOS\_RDS\W11-GOLD\W11-GOLD.vhdx"
```

**Vérification :** `Test-Path C:\AVAEDOS\_RDS\W11-GOLD\W11-GOLD.vhdx` renvoie **True** sur RDS-HYPERV1.

## 7. \[HV1\]Préparez le disque du modèle pour le Bureau à distance

Une image Windows 11 n'accepte pas les connexions Bureau à distance par défaut, et le modèle ne peut pas être démarré pour la régler : ce serait annuler sa généralisation. Le disque se prépare donc hors ligne, en y déposant un script **SetupComplete.cmd**. Windows l'exécute à la fin du premier démarrage de chaque poste VDI : il active le Bureau à distance, ouvre le pare-feu et autorise le groupe **RDS VDI Users**.

Sur RDS-HYPERV1 :

```powershell
$disque = "C:\AVAEDOS\_RDS\W11-GOLD\W11-GOLD.vhdx"
$lecteur = (Mount-VHD -Path $disque -Passthru | Get-Disk | Get-Partition | Get-Volume |
    Where-Object { $_.DriveLetter -and (Test-Path "$($_.DriveLetter):\Windows") }).DriveLetter

New-Item -ItemType Directory -Path "${lecteur}:\Windows\Setup\Scripts" -Force | Out-Null
@'
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0; Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'; Add-LocalGroupMember -SID S-1-5-32-555 -Member 'AVAEDOS\RDS VDI Users'"
'@ | Set-Content -Path "${lecteur}:\Windows\Setup\Scripts\SetupComplete.cmd" -Encoding Ascii

Dismount-VHD -Path $disque
```

Le groupe local est désigné par son identifiant **S-1-5-32-555** (Utilisateurs du Bureau à distance) et la règle de pare-feu par son groupe : les commandes ne dépendent pas de la langue de Windows.

**Vérification :** `Get-VHD C:\AVAEDOS\_RDS\W11-GOLD\W11-GOLD.vhdx | Select-Object Attached` renvoie **False**. Le disque est démonté, prêt pour l'étape suivante.

## 8. \[HV1\]Créez la machine virtuelle W11-GOLD

Sur RDS-HYPERV1, créez la machine virtuelle de génération 2 avec démarrage sécurisé et TPM virtuel :

```powershell
New-VM -Name W11-GOLD -Generation 2 -MemoryStartupBytes 2GB -Path C:\AVAEDOS\_RDS `
    -VHDPath C:\AVAEDOS\_RDS\W11-GOLD\W11-GOLD.vhdx -SwitchName "VDI"
Set-VMProcessor -VMName W11-GOLD -Count 2
Set-VMMemory -VMName W11-GOLD -DynamicMemoryEnabled $true -MinimumBytes 1GB -StartupBytes 2GB -MaximumBytes 4GB
Set-VMKeyProtector -VMName W11-GOLD -NewLocalKeyProtector
Enable-VMTPM -VMName W11-GOLD
```

Les postes VDI héritent de la configuration mémoire du modèle : ces valeurs conviennent à un hôte de 8 Go.

Le modèle doit rester arrêté : le démarrer annule sa généralisation.

**Vérification :** `Get-VM W11-GOLD` affiche l'état **Off** et la génération **2**.

## 9. \[DC\]Autorisez les Connection Brokers à créer les comptes des postes

Le Connection Broker joint lui-même les postes virtuels au domaine : il doit pouvoir créer des comptes ordinateurs dans l'UO **RD VDI**. Le groupe **RDS Servers** contient les deux Connection Brokers.

```powershell
$ou = "OU=RD VDI,DC=avaedos,DC=lan"
dsacls $ou /G "AVAEDOS\RDS Servers:CCDC;computer"
dsacls $ou /I:S /G "AVAEDOS\RDS Servers:GA;;computer"
```

# Création de la collection

## 10. \[CB1\]Créez la collection regroupée RdsVdiColl1

```powershell
New-RDVirtualDesktopCollection -CollectionName "RdsVdiColl1" `
    -PooledManaged -VirtualDesktopTemplateName "W11-GOLD" `
    -VirtualDesktopTemplateHostServer rds-hyperv1.avaedos.lan `
    -VirtualDesktopAllocation @{"rds-hyperv1.avaedos.lan" = 1; "rds-hyperv2.avaedos.lan" = 1} `
    -StorageType LocalStorage -LocalStoragePath "C:\VDI" `
    -VirtualDesktopNamePrefix "VDI" -Domain "avaedos.lan" `
    -OU "RD VDI" -UserGroups "AVAEDOS\RDS VDI Users" `
    -ConnectionBroker rds-cbroker1.avaedos.lan
```

**32 Go :** un seul hôte reçoit les deux postes. Remplacez l'allocation par `-VirtualDesktopAllocation @{"rds-hyperv1.avaedos.lan" = 2}`.

La création exporte le modèle vers chaque hôte, crée les machines à partir de disques de différenciation, les personnalise et les joint au domaine.

**Résultat attendu :** en **64 Go**, une machine **VDI-0** sur RDS-HYPERV1 et une machine **VDI-1** sur RDS-HYPERV2 ; en **32 Go**, **VDI-0** et **VDI-1** sur RDS-HYPERV1.

**Vérification :**

```powershell
Get-RDVirtualDesktop -CollectionName "RdsVdiColl1" -ConnectionBroker rds-cbroker1.avaedos.lan
```

Sur RDS-DC1, `Get-ADComputer -SearchBase "OU=RD VDI,DC=avaedos,DC=lan" -Filter *` liste les deux comptes et `Get-DhcpServerv4Lease -ScopeId 172.16.0.0` montre leurs adresses.

## 11. \[CB1\]Vérifiez le retour à l'état initial

Dans **Server Manager** \\ **Remote Desktop Services** \\ **Collections** \\ **RdsVdiColl1**, ouvrez **Tasks** \\ **Edit Properties** puis **Virtual Desktop Settings** et vérifiez l'option **Automatically roll back the virtual desktop when the user logs off**.

# Utilisation du poste virtuel

## 12. \[CLI\]Connectez-vous au poste virtuel

Dans le client web **https://rds.avaedos.lan/RDWeb/webclient/index.html**, connectez-vous avec **AVAEDOS\\bnedjimi**.

**Résultat attendu :** le client web affiche **RdsVdiColl1** à côté des collections de sessions. La connexion ouvre un bureau Windows 11.

**Vérification :** dans la session, `hostname` renvoie **VDI-0** ou **VDI-1** ; `(Get-CimInstance Win32_OperatingSystem).Caption` renvoie **Microsoft Windows 11 Pro**.

## 13. \[CLI\]Vérifiez le retour à l'état initial

Créez un fichier **test.txt** sur le bureau du poste virtuel, puis fermez la session Windows (**Se déconnecter**).

Reconnectez-vous avec **bnedjimi**.

**Résultat attendu :** le fichier a disparu : la machine est revenue à l'état du modèle.

**Interprétation :** une collection regroupée ne conserve rien localement. Pour conserver les données de l'utilisateur, on associe à la collection des conteneurs FSLogix, comme pour les sessions.

# Ce qu'il faut retenir

Une collection VDI regroupée se maintient par son modèle : on met à jour une copie du modèle puis on lance `Update-RDVirtualDesktopCollection`. Les postes se répartissent entre les hôtes de virtualisation, et chaque poste consomme une machine virtuelle complète : le VDI est réservé aux besoins que les sessions partagées ne couvrent pas.

# Erreurs fréquentes

| Symptôme | Cause probable | Correction |
|---|---|---|
| Création bloquée à la jonction au domaine | Droits insuffisants dans l'UO **RD VDI** | Vérifier la délégation `dsacls` accordée à **RDS Servers** |
| Postes sans adresse IP | DHCP absent ou usurpation MAC désactivée sur l'hôte | Vérifier l'étendue DHCP et `Set-VMNetworkAdapter -MacAddressSpoofing On` |
| Création impossible sur RDS-HYPERV2 | Commutateur **VDI** absent ou nommé différemment | Créer le même commutateur sur les deux hôtes (64 Go) |
| Création impossible : modèle invalide | Modèle démarré après généralisation ou créé sur un Hyper-V d'une autre version | Recréer le modèle et le laisser arrêté |
| Le démarrage de RDS-HYPERV1 échoue : *Ressources système insuffisantes* (0x800705AA) | La machine physique n'a pas assez de mémoire libre pour la réservation statique | Quitter WSL (`wsl --shutdown`), fermer des applications, éteindre les machines inutiles ; en 32 Go, réserver 8 Go |
| Installation de Hyper-V refusée : *virtualization support is not enabled in the BIOS* | Le processeur virtuel de l'hôte n'expose pas la virtualisation | Arrêter RDS-HYPERV1, refaire `Set-VMProcessor -ExposeVirtualizationExtensions $true`, le redémarrer, puis vérifier `VirtualizationFirmwareEnabled` dans la session de l'hôte ; vérifier aussi que la virtualisation est activée dans le BIOS de la machine physique |
| Connexion au poste refusée ou Bureau à distance indisponible | Le script **SetupComplete.cmd** n'a pas été déposé dans l'image, ou le groupe n'a pas pu être ajouté au démarrage | Vérifier la présence de `C:\Windows\Setup\Scripts\SetupComplete.cmd` dans l'image, puis recommencer l'étape 7 avant de recréer la collection |
| Échec lié au TPM virtuel lors du clonage | Protecteur de clé du TPM virtuel non transférable | Point à valider par le formateur lors de la préparation |
