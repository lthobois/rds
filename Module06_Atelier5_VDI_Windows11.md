---
title: "Atelier 5 – Collection VDI Windows 11"
subtitle: "Module 6 : Postes de travail virtuels (VDI)"
author: "Loïc THOBOIS"
lang: fr-FR
---

Cet atelier se réalise individuellement, sur votre propre environnement. Il s'appuie sur le résultat de l'atelier précédent. Les conventions, le plan d'adressage et les comptes sont décrits dans le document de préparation (Module00_Preparation_environnement.md).

# Objectif

Répondre au besoin du bureau d'études : des postes virtuels Windows 11 regroupés, créés à partir d'un modèle unique, répartis sur deux hôtes de virtualisation et publiés dans le même portail que les sessions.

**Livrable :** la collection **RdsVdiColl1** fournit à **bnedjimi** un poste virtuel **VDI-** qui revient à son état initial après déconnexion.

# Préparation des hôtes de virtualisation

## \[MP\]Créez RDS-HYPERV1 et RDS-HYPERV2

Les hôtes de virtualisation exécutent eux-mêmes des machines virtuelles : ils exigent la virtualisation imbriquée, une mémoire statique et l'usurpation d'adresses MAC pour que les postes VDI accèdent au réseau. Ces réglages se font machine arrêtée, avant le premier démarrage.

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

Configurez ensuite chaque hôte avant de vous en servir. Ouvrez une session avec le compte local **Administrator** et le mot de passe **P@ssw0rd**.

Sur RDS-HYPERV1 :

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.121 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
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
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential "AVAEDOS\Administrator", $mdp
Add-Computer -DomainName "avaedos.lan" -NewName RDS-HYPERV2 -Credential $cred `
    -OUPath "OU=RD Servers,DC=avaedos,DC=lan" -Restart
```

Ajoutez ensuite les deux serveurs au groupe **RDS Servers** depuis RDS-DC1 :

```powershell
Add-ADGroupMember "RDS Servers" -Members "RDS-HYPERV1$", "RDS-HYPERV2$"
```

**Vérification :** `Get-VMProcessor -VMName RDS-HYPERV1 | Select-Object ExposeVirtualizationExtensions` renvoie **True**.

Si la mémoire de la machine physique ne permet pas deux hôtes, réalisez l'atelier avec RDS-HYPERV1 seul et deux postes sur cet hôte.

## \[CB1\]Ajoutez les hôtes de virtualisation au déploiement

```powershell
Import-Module RemoteDesktop
foreach ($hote in "rds-hyperv1.avaedos.lan","rds-hyperv2.avaedos.lan") {
    Add-RDServer -Server $hote -Role RDS-VIRTUALIZATION -ConnectionBroker rds-cbroker1.avaedos.lan
}
```

Le rôle installe Hyper-V sur chaque hôte et le redémarre.

**Vérification :** sur chaque hôte, `Get-WindowsFeature Hyper-V` est à l'état **Installed**.

## \[HV1\]\[HV2\]Créez le commutateur virtuel des postes VDI

Les postes virtuels doivent rejoindre le réseau d'Avaedos pour joindre le domaine et obtenir une adresse DHCP. Le commutateur porte le même nom sur les deux hôtes.

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1).Name
New-VMSwitch -Name "VDI" -NetAdapterName $carte -AllowManagementOS $true
New-Item -ItemType Directory -Path C:\VDI -Force
```

Le dossier **C:\\VDI** accueille les disques des postes virtuels créés sur l'hôte.

La connexion réseau de l'hôte est brièvement interrompue pendant la création du commutateur.

## \[HV1\]Importez le modèle W11-GOLD

Le modèle est une machine virtuelle Windows 11 Enterprise de génération 2, avec démarrage sécurisé et TPM virtuel, généralisée par `sysprep /generalize /oobe /shutdown /mode:vm`. Il est fourni pour éviter une préparation longue.

Sur la machine physique, copiez le dossier du modèle dans **C:\\AVAEDOS\\W11-GOLD** de RDS-HYPERV1 :

```powershell
$racine = "<chemin du dossier de sources>\W11-GOLD"
Get-VMIntegrationService -VMName RDS-HYPERV1 | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
Get-ChildItem $racine -Recurse -File | ForEach-Object {
    Copy-VMFile -Name RDS-HYPERV1 -SourcePath $_.FullName -FileSource Host -CreateFullPath -Force `
        -DestinationPath ("C:\AVAEDOS\W11-GOLD" + $_.FullName.Substring($racine.Length))
}
```

Puis sur RDS-HYPERV1 :

```powershell
$source = (Get-ChildItem "C:\AVAEDOS\W11-GOLD\Virtual Machines\*.vmcx").FullName
Import-VM -Path $source -Register
Get-VMNetworkAdapter -VMName W11-GOLD | Connect-VMNetworkAdapter -SwitchName "VDI"
```

Le modèle doit rester arrêté : le démarrer annule sa généralisation.

**Vérification :** `Get-VM W11-GOLD` affiche l'état **Off** et la génération **2**.

## \[DC\]Autorisez les Connection Brokers à créer les comptes des postes

Le Connection Broker joint lui-même les postes virtuels au domaine : il doit pouvoir créer des comptes ordinateurs dans l'UO **RD VDI**. Le groupe **RDS Servers** contient les deux Connection Brokers.

```powershell
$ou = "OU=RD VDI,DC=avaedos,DC=lan"
dsacls $ou /G "AVAEDOS\RDS Servers:CCDC;computer"
dsacls $ou /I:S /G "AVAEDOS\RDS Servers:GA;;computer"
```

# Création de la collection

## \[CB1\]Créez la collection regroupée RdsVdiColl1

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

La création exporte le modèle vers chaque hôte, crée les machines à partir de disques de différenciation, les personnalise et les joint au domaine.

**Résultat attendu :** une machine **VDI-0** sur RDS-HYPERV1 et une machine **VDI-1** sur RDS-HYPERV2.

**Vérification :**

```powershell
Get-RDVirtualDesktop -CollectionName "RdsVdiColl1" -ConnectionBroker rds-cbroker1.avaedos.lan
```

Sur RDS-DC1, `Get-ADComputer -SearchBase "OU=RD VDI,DC=avaedos,DC=lan" -Filter *` liste les deux comptes et `Get-DhcpServerv4Lease -ScopeId 172.16.0.0` montre leurs adresses.

## \[CB1\]Vérifiez le retour à l'état initial

Dans **Server Manager** \\ **Remote Desktop Services** \\ **Collections** \\ **RdsVdiColl1**, ouvrez **Tasks** \\ **Edit Properties** puis **Virtual Desktop Settings** et vérifiez l'option **Automatically roll back the virtual desktop when the user logs off**.

# Utilisation du poste virtuel

## \[EXT\]Connectez-vous au poste virtuel

Dans le client web **https://rds.avaedos.lan/RDWeb/webclient/index.html**, connectez-vous avec **AVAEDOS\\bnedjimi**.

**Résultat attendu :** le client web affiche **RdsVdiColl1** à côté des collections de sessions. La connexion ouvre un bureau Windows 11.

**Vérification :** dans la session, `hostname` renvoie **VDI-0** ou **VDI-1** ; `(Get-CimInstance Win32_OperatingSystem).Caption` renvoie **Microsoft Windows 11 Enterprise**.

## \[EXT\]Vérifiez le retour à l'état initial

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
| Création impossible sur RDS-HYPERV2 | Commutateur **VDI** absent ou nommé différemment | Créer le même commutateur sur les deux hôtes |
| Création impossible : modèle invalide | Modèle démarré après généralisation ou créé sur un Hyper-V d'une autre version | Recréer le modèle et le laisser arrêté |
| Échec lié au TPM virtuel lors du clonage | Protecteur de clé du TPM virtuel non transférable | Point à valider par le formateur lors de la préparation |
