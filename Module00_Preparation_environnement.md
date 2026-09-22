---
title: "Ateliers pratiques – Préparation de l'environnement"
subtitle: "Services de Bureau à distance sous Windows Server 2025"
author: "Loïc THOBOIS"
lang: fr-FR
---

# Présentation des ateliers

## Situation

Vous êtes administrateur système chez **Avaedos**. Vous construisez la plateforme de services Bureau à distance de l'entreprise sous Windows Server 2025 : ferme de sessions, applications RemoteApp, profils FSLogix, accès externe sécurisé, haute disponibilité et postes de travail virtuels Windows 11.

Chaque atelier s'appuie sur le résultat du précédent. Chaque participant travaille sur son propre environnement. Les machines virtuelles sont créées au fil des ateliers, au moment où elles deviennent nécessaires.

## Conventions

Chaque étape est précédée du nom de la machine sur laquelle elle est réalisée :

| Repère | Machine | Rôle | Créée à |
|---|---|---|---|
| \[MP\] | Machine physique | Hôte Hyper-V de l'environnement | — |
| \[DC\] | RDS-DC1 | Contrôleur de domaine, DNS, DHCP, autorité de certification, partage des profils | Préparation |
| \[SES1\] à \[SES4\] | RDS-SESSION1 à RDS-SESSION4 | Hôtes de session | Préparation |
| \[CB1\] / \[CB2\] | RDS-CBROKER1 / RDS-CBROKER2 | Connection Broker, licences sur RDS-CBROKER1 | Préparation / atelier 4 |
| \[GTW1\] / \[GTW2\] | RDS-GATEWAY1 / RDS-GATEWAY2 | Accès Web et passerelle | Préparation / atelier 4 |
| \[SQL\] | RDS-SQL1 | Base de données du Connection Broker | Atelier 4 |
| \[HV1\] / \[HV2\] | RDS-HYPERV1 / RDS-HYPERV2 | Hôtes de virtualisation VDI | Atelier 5 |
| \[CLI\] | RDS-CLI1 | Poste Windows 11 interne, membre du domaine | Préparation |
| \[EXT\] | RDS-EXT1 | Poste Windows 11 externe, hors domaine | Atelier 3 |

Les commandes PowerShell s'exécutent dans une console **Windows PowerShell** lancée en tant qu'administrateur. Sauf indication contraire, ouvrez la session avec le compte **AVAEDOS\\Administrator** et le mot de passe **P@ssw0rd**.

Le mot de passe unique **P@ssw0rd** est une simplification propre au laboratoire. En production, chaque compte a son propre mot de passe et les comptes d'administration sont protégés.

## Plan d'adressage

Toutes les machines sont reliées au même commutateur virtuel, sur le réseau 172.16.0.0/16 (masque **255.255.0.0**). Serveur DNS : **172.16.1.1**. Passerelle par défaut : **172.16.1.254**, le routeur de la salle.

Le commutateur est celui indiqué par le formateur : **Reseau Salle** pour un réseau isolé, ou **Default Switch** lorsque les machines ont besoin d'un accès Internet, par exemple pour télécharger le client web à l'atelier 3.

| Machine | Adresse IP |
|---|---|
| RDS-DC1 | 172.16.1.1 |
| RDS-CLI1 | 172.16.1.101 |
| RDS-EXT1 | 172.16.1.102 |
| RDS-SESSION1 à RDS-SESSION4 | 172.16.1.111 à 172.16.1.114 |
| RDS-CBROKER1, RDS-CBROKER2 | 172.16.1.115, 172.16.1.116 |
| RDS-GATEWAY1, RDS-GATEWAY2 | 172.16.1.117, 172.16.1.118 |
| Ferme de passerelles `rds.avaedos.lan` (atelier 4) | 172.16.1.119 |
| RDS-SQL1 | 172.16.1.120 |
| RDS-HYPERV1, RDS-HYPERV2 | 172.16.1.121, 172.16.1.122 |
| Postes VDI | 172.16.1.200 à 172.16.1.250 (DHCP) |

## Noms DNS

| Nom | Désigne |
|---|---|
| `rds.avaedos.lan` | L'accès Web et la passerelle : RDS-GATEWAY1, puis la ferme de passerelles à l'atelier 4 |
| `rds-farm.avaedos.lan` | La ferme de Connection Brokers, à partir de l'atelier 4 |

## Comptes et groupes

| Compte ou groupe | Usage |
|---|---|
| AVAEDOS\\Administrator | Administration de la plateforme |
| AVAEDOS\\lthobois (Loïc THOBOIS) | Utilisateur : bureau de session et RemoteApp |
| AVAEDOS\\bnedjimi (Brahim NEDJIMI) | Utilisateur du bureau d'études : bureau de session, RemoteApp et poste virtuel Windows 11 |
| RDS Users | Accès aux collections de sessions et à la passerelle |
| RDS VDI Users | Accès à la collection VDI |
| RDS Servers | Comptes ordinateurs des serveurs RDS |

## Unités d'organisation

| Unité d'organisation | Contenu |
|---|---|
| RD Users | Comptes et groupes d'utilisateurs |
| RD Servers | Serveurs RDS et groupe RDS Servers |
| RD Clients | Postes clients du domaine |
| RD VDI | Postes virtuels créés à l'atelier 5 |

## Ressources fournies par le formateur

- **Modèles de machines virtuelles** Windows Server 2025 et Windows 11 Enterprise, généralisés, de génération 2 ;
- **W11-GOLD** : modèle VDI Windows 11 Enterprise généralisé, destiné à l'atelier 5 ;
- **Dossier des sources**, copié à l'atelier concerné : FSLogix, pilote ODBC Driver 17 for SQL Server, SQL Server 2022 Express, et, en l'absence d'accès Internet, le module et le paquet du client web RDS.

# Préparation de l'environnement

Cette partie construit le socle commun : réseau virtuel, premières machines, domaine Active Directory et autorité de certification. Elle ne relève pas encore de RDS, mais tous les ateliers en dépendent.

## Mise en place du réseau et déploiement des machines

### \[MP\]Lancez le script de préparation

Ce script prépare l'hôte Hyper-V et déploie d'un seul coup les dix machines des ateliers 1 à 4. Le formateur fournit dans **C:\\VirtualMachines** — ou sur le disque **D:** selon la salle — les modèles de machines virtuelles, les images ISO et la bibliothèque **Load-LibVMGuest**, qui automatise le déploiement et la configuration.

Ouvrez une console **PowerShell** en tant qu'administrateur sur la machine physique :

```powershell
#Remove-VMEnvironment -Prefix RDS
Clear-Host

$StartTime = Get-Date

#region Configuration

if (Test-Path -Path "D:\Images ISO")
    { $ImagesIsoPath = "D:\Images ISO" }
elseif (Test-Path -Path "C:\VirtualMachines\Images ISO")
    { $ImagesIsoPath = "C:\VirtualMachines\Images ISO" }
else
    { throw "Le chemin vers les images ISO n'existe pas !" }

$password = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force

$username = "Administrator"
$CredLocal = New-Object System.Management.Automation.PSCredential $username, $password

$username = "AVAEDOS$($IdComputerName)\Administrator"
$CredDomain = New-Object System.Management.Automation.PSCredential $username, $password

$username = "User"
$CredWorkstation = New-Object System.Management.Automation.PSCredential $username, $password

if ((Get-Module -Name "Load-LibVMGuest").Count -eq 1)
    { "Load-LibVMGuest déja chargé !" }
elseif (Test-Path -Path "C:\OneDrive\Scripts\Hyper-V\Load-LibVMGuest.ps1")
    { Import-Module C:\OneDrive\Scripts\Hyper-V\Load-LibVMGuest.ps1 }
elseif (Test-Path -Path "C:\VirtualMachines\Load-LibVMGuest.ps1")
    { Import-Module C:\VirtualMachines\Load-LibVMGuest.ps1 }
else
    { throw "Impossible de charger la librairie Load-LibVMGuest !" }

$IsVmSwitch = (Get-VMSwitch -Name "Reseau Salle" -ErrorAction SilentlyContinue).Count -ne 0
if (!$IsVmSwitch) { New-VMSwitch -Name "Reseau Salle" -SwitchType Private }

#endregion

#region Deploiement des machines virtuelles

Deploy-VMTemplate -Name RDS-DC1 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-CBROKER1 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-SESSION1 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-SESSION2 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-CLI1 -OperatingSystem Windows11US

Deploy-VMTemplate -Name RDS-SESSION3 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-SESSION4 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-CBROKER2 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-GATEWAY1 -OperatingSystem Windows2025Full
Deploy-VMTemplate -Name RDS-GATEWAY2 -OperatingSystem Windows2025Full

#endregion

#region Configuration Hyper-V

Set-VMHost -EnableEnhancedSessionMode $true -NumaSpanningEnabled $true

#endregion
```

**Résultat attendu :** `Get-VM RDS-*` liste les dix machines, et le commutateur **Reseau Salle** apparaît dans le **Gestionnaire Hyper-V**, sous **Gestionnaire de commutateur virtuel**.

Le mode session étendu permet le copier-coller et la redirection de périphériques vers les machines virtuelles ; l'étalement NUMA évite qu'une machine soit refusée faute de mémoire sur un seul nœud. La ligne `Remove-VMEnvironment` en commentaire sert à repartir d'un environnement vierge.

Les machines des ateliers 4 et 5 — **RDS-SQL1**, **RDS-HYPERV1**, **RDS-HYPERV2** — et le poste hors domaine **RDS-EXT1** sont déployées au moment de l'atelier concerné, avec les commandes données sur place.

Les images ISO ne servent qu'à l'atelier 4. Le chemin est repéré dès maintenant pour que les commandes suivantes puissent s'y référer.

Les sections qui suivent reprennent chaque machine une par une : la commande de déploiement y est rappelée pour qui préfère avancer pas à pas, puis vient la configuration réseau et la jonction au domaine, qui reste à faire.

## Création d'une machine virtuelle

Cette section explique le mécanisme. Les commandes de chaque machine sont données au moment où elle est créée, ici puis dans les ateliers suivants : ne déployez rien tout de suite.

### \[MP\]Comprenez le déploiement depuis le modèle

`Deploy-VMTemplate` crée la machine à partir du modèle correspondant au système demandé : un disque différentiel rattaché au modèle, ce qui rend le déploiement quasi instantané et économe en espace disque. Chaque machine se crée ainsi :

```powershell
Deploy-VMTemplate -Name <nom> -OperatingSystem Windows2025Full
Wait-VMToStart -VMName <nom>
Get-VMIntegrationService -VMName <nom> | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
```

Les serveurs utilisent le modèle **Windows2025Full**, les postes de travail le modèle **Windows11US**.

Le service d'invité permet de copier des fichiers de la machine physique vers la machine virtuelle avec `Copy-VMFile`, utilisé pour les sources des ateliers. Il est désigné par son identifiant plutôt que par son nom, qui est traduit sur un hôte francophone.

Si le formateur travaille sur un réseau isolé, raccordez les cartes réseau après le déploiement :

```powershell
Get-VM RDS-* | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName "Reseau Salle"
```

Les modèles étant généralisés, la période d'activation peut être réarmée avec `slmgr /rearm` suivi d'un redémarrage.

### \[Machine\]Configurez TCP/IP, le nom et le domaine

Ouvrez une session avec le compte local **Administrator** et le mot de passe **P@ssw0rd**. Si le formateur le demande, réarmez d'abord la période d'activation avec `slmgr /rearm`, puis redémarrez.

Configurez l'adresse IP selon le plan d'adressage, puis joignez la machine au domaine dans la bonne unité d'organisation. Exemple pour RDS-SESSION1 :

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.111 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
$cred = Get-Credential AVAEDOS\Administrator
Add-Computer -DomainName "avaedos.lan" -NewName RDS-SESSION1 -Credential $cred `
    -OUPath "OU=RD Servers,DC=avaedos,DC=lan" -Restart
```

Les serveurs rejoignent l'UO **RD Servers**, les postes du domaine l'UO **RD Clients**.

**Vérification :** `Resolve-DnsName avaedos.lan` renvoie **172.16.1.1** ; après redémarrage, `(Get-CimInstance Win32_ComputerSystem).Domain` renvoie **avaedos.lan**.

## Ajout du serveur Active Directory

### \[MP\]Créez la machine RDS-DC1

```powershell
Deploy-VMTemplate -Name "RDS-DC1" -OperatingSystem Windows2025Full
Wait-VMToStart -VMName "RDS-DC1"
Get-VMIntegrationService -VMName "RDS-DC1" | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
```

### \[DC\]Configurez TCP/IP et renommez la machine en RDS-DC1

RDS-DC1 est le premier serveur : il n'y a pas encore de domaine à joindre.

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.1 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
Rename-Computer -NewName RDS-DC1 -Restart
```

## Installation du service d'annuaire Active Directory

### \[DC\]Installez le rôle Active Directory Domain Services et créez le domaine avaedos.lan

```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
Install-ADDSForest -DomainName "avaedos.lan" -DomainNetbiosName "AVAEDOS" `
    -DomainMode Win2025 -ForestMode Win2025 -InstallDns `
    -SafeModeAdministratorPassword $mdp -Force
```

Le serveur redémarre automatiquement. Ouvrez ensuite une session avec **AVAEDOS\\Administrator**.

### \[DC\]Vérifiez les enregistrements SRV et le partage SYSVOL

Un domaine fonctionnel publie ses contrôleurs dans le DNS et partage les dossiers SYSVOL et NETLOGON : sans eux, ni la jonction au domaine ni les stratégies de groupe ne fonctionnent.

```powershell
Resolve-DnsName _ldap._tcp.dc._msdcs.avaedos.lan -Type SRV
Get-SmbShare -Name SYSVOL, NETLOGON
```

**Résultat attendu :** l'enregistrement SRV pointe vers **RDS-DC1.avaedos.lan** ; les deux partages existent.

## Configuration des utilisateurs

### \[DC\]Créez les unités d'organisation, les comptes et les groupes

```powershell
"RD Users","RD Servers","RD Clients","RD VDI" |
    ForEach-Object { New-ADOrganizationalUnit -Name $_ -Path "DC=avaedos,DC=lan" }
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$ou = "OU=RD Users,DC=avaedos,DC=lan"
New-ADUser -Name "Loïc THOBOIS" -SamAccountName "lthobois" -UserPrincipalName "lthobois@avaedos.lan" `
    -DisplayName "Loïc THOBOIS" -Path $ou -AccountPassword $mdp -Enabled $true -PasswordNeverExpires $true
New-ADUser -Name "Brahim NEDJIMI" -SamAccountName "bnedjimi" -UserPrincipalName "bnedjimi@avaedos.lan" `
    -DisplayName "Brahim NEDJIMI" -Path $ou -AccountPassword $mdp -Enabled $true -PasswordNeverExpires $true
New-ADGroup -Name "RDS Users" -GroupScope Global -Path $ou
New-ADGroup -Name "RDS VDI Users" -GroupScope Global -Path $ou
New-ADGroup -Name "RDS Servers" -GroupScope Global -Path "OU=RD Servers,DC=avaedos,DC=lan"
Add-ADGroupMember "RDS Users" -Members lthobois, bnedjimi
Add-ADGroupMember "RDS VDI Users" -Members bnedjimi
```

Les hôtes de session sont regroupés dans l'UO **RD Servers** : les stratégies de groupe RDS de l'atelier 2 y seront liées sans toucher aux postes clients.

**Vérification :** `Get-ADGroupMember "RDS Users"` affiche **lthobois** et **bnedjimi**.

## Configuration des services d'infrastructure

### \[DC\]Enregistrez le nom rds.avaedos.lan

Les utilisateurs accèdent au portail et à la passerelle par le nom **rds.avaedos.lan**. Il désigne RDS-GATEWAY1 ; il désignera la ferme de passerelles à l'atelier 4.

```powershell
Add-DnsServerResourceRecordA -ZoneName "avaedos.lan" -Name "rds" -IPv4Address 172.16.1.117
```

### \[DC\]Installez le service DHCP pour les postes VDI

Les postes virtuels créés à l'atelier 5 obtiennent leur adresse automatiquement.

```powershell
Install-WindowsFeature DHCP -IncludeManagementTools
Add-DhcpServerSecurityGroup
Restart-Service DHCPServer
Add-DhcpServerInDC -DnsName RDS-DC1.avaedos.lan -IPAddress 172.16.1.1
Add-DhcpServerv4Scope -Name "Postes VDI" -StartRange 172.16.1.200 `
    -EndRange 172.16.1.250 -SubnetMask 255.255.0.0
Set-DhcpServerv4OptionValue -DnsServer 172.16.1.1 -DnsDomain "avaedos.lan" -Router 172.16.1.254
```

**Vérification :** `Get-DhcpServerv4Scope` affiche l'étendue **Postes VDI** à l'état **Active**.

## Ajout d'une autorité de certification

### \[DC\]Installez l'autorité de certification RDS-CA

Les rôles RDS exigent des certificats approuvés par les clients. Une autorité d'entreprise est automatiquement approuvée par les machines du domaine. L'installer sur le contrôleur de domaine est une simplification de laboratoire.

```powershell
Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
Install-AdcsCertificationAuthority -CAType EnterpriseRootCA -CACommonName "RDS-CA" `
    -KeyLength 2048 -HashAlgorithm SHA256 `
    -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" -Force
```

### \[DC\]Créez et publiez le modèle de certificat WebServer RDS

Le modèle **Web Server** par défaut ne permet ni l'inscription par les ordinateurs ni l'export de la clé privée. Le déploiement RDS a besoin des deux.

Lancez la console **Modèles de certificats** (`certtmpl.msc`).

Cliquez avec le bouton droit sur le modèle **Web Server** puis sélectionnez **Duplicate Template**.

Dans l'onglet **General**, tapez **WebServer RDS** dans le champ **Template display name**. Le champ **Template name** devient **WebServerRDS**.

Dans l'onglet **Request Handling**, cochez **Allow private key to be exported**.

Dans l'onglet **Security**, ajoutez le groupe **Domain Computers** et accordez-lui l'autorisation **Enroll**.

Cliquez sur **OK**.

Lancez la console **Autorité de certification** (`certsrv.msc`), développez **RDS-CA**, cliquez avec le bouton droit sur **Certificate Templates** puis sélectionnez **New** \\ **Certificate Template to Issue**. Sélectionnez **WebServer RDS** puis cliquez sur **OK**.

**Résultat attendu :** le modèle **WebServer RDS** apparaît sous **Certificate Templates**.

## Préparation du partage des profils

### \[DC\]Créez le partage ProfilDisk

Le partage accueille les conteneurs de profil FSLogix de l'atelier 2. L'héberger sur le contrôleur de domaine est une simplification de laboratoire.

```powershell
New-Item -ItemType Directory -Path C:\ProfilDisk
New-SmbShare -Name "ProfilDisk" -Path C:\ProfilDisk `
    -FullAccess "AVAEDOS\Domain Admins" -ChangeAccess "AVAEDOS\RDS Users"
```

Les autorisations NTFS du dossier sont réglées à l'atelier 2.

### \[MP\]Mettez les sources à disposition dans C:\\AVAEDOS

Le réseau de la salle est isolé : les installateurs ne peuvent pas être téléchargés depuis les machines virtuelles. Le formateur fournit un dossier de sources — FSLogix, pilote ODBC, SQL Server Express, client web — qui est déposé dans **C:\\AVAEDOS** sur chaque machine qui en a besoin.

```powershell
$racine = "<chemin du dossier de sources fourni par le formateur>"
$machines = "RDS-SESSION1","RDS-SESSION2","RDS-SESSION3","RDS-SESSION4",
            "RDS-CBROKER1","RDS-GATEWAY1"
foreach ($vm in $machines) {
    Get-VMIntegrationService -VMName $vm | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
    Get-ChildItem $racine -Recurse -File | Where-Object FullName -notlike "*\W11-GOLD\*" | ForEach-Object {
        Copy-VMFile -Name $vm -SourcePath $_.FullName -FileSource Host -CreateFullPath -Force `
            -DestinationPath ("C:\AVAEDOS" + $_.FullName.Substring($racine.Length))
    }
}
```

Les machines créées dans les ateliers suivants — RDS-SQL1, RDS-CBROKER2, RDS-GATEWAY2, RDS-HYPERV1 et RDS-HYPERV2 — reçoivent le dossier de la même façon au moment de leur création. Le modèle VDI **W11-GOLD** est copié à l'atelier 5, directement sur l'hôte de virtualisation.

**Vérification :** sur un hôte de session, `Get-ChildItem C:\AVAEDOS` liste les dossiers **FSLogix**, **ODBC**, **SQL** et **WebClient**.

## Ajout des serveurs Bureau à distance

### \[MP\]Créez les serveurs RDS de la ferme de sessions

```powershell
foreach ($nom in "RDS-SESSION1","RDS-SESSION2","RDS-SESSION3","RDS-SESSION4","RDS-CBROKER1","RDS-GATEWAY1") {
    Deploy-VMTemplate -Name $nom -OperatingSystem Windows2025Full
    Wait-VMToStart -VMName $nom
    Get-VMIntegrationService -VMName $nom | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
}
```

Les six serveurs sont déployés d'un coup. Si la mémoire de la machine physique est limitée, déployez d'abord RDS-CBROKER1, RDS-GATEWAY1, RDS-SESSION1 et RDS-SESSION2, puis les deux autres hôtes de session avant l'atelier 1.

### \[Serveurs\]Configurez chaque serveur et joignez-le au domaine

Appliquez la configuration TCP/IP et la jonction à l'UO **RD Servers** avec l'adresse de chaque serveur :

| Serveur | Adresse IP |
|---|---|
| RDS-SESSION1 | 172.16.1.111 |
| RDS-SESSION2 | 172.16.1.112 |
| RDS-SESSION3 | 172.16.1.113 |
| RDS-SESSION4 | 172.16.1.114 |
| RDS-CBROKER1 | 172.16.1.115 |
| RDS-GATEWAY1 | 172.16.1.117 |

### \[DC\]Ajoutez les serveurs au groupe RDS Servers

```powershell
Get-ADComputer -SearchBase "OU=RD Servers,DC=avaedos,DC=lan" -Filter { Name -like "RDS-*" } |
    ForEach-Object { Add-ADGroupMember -Identity "RDS Servers" -Members $_ }
```

Relancez cette commande chaque fois qu'un serveur RDS rejoint le domaine dans les ateliers suivants.

**Vérification :** `Get-ADGroupMember "RDS Servers" | Select-Object Name` liste les six serveurs.

## Ajout du client

### \[MP\]Créez le poste RDS-CLI1

```powershell
Deploy-VMTemplate -Name "RDS-CLI1" -OperatingSystem Windows11US
Wait-VMToStart -VMName "RDS-CLI1"
Get-VMIntegrationService -VMName "RDS-CLI1" | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
```

### \[CLI\]Configurez RDS-CLI1 et ajoutez-le au domaine

Ouvrez une session avec le compte local fourni par le formateur, puis appliquez la configuration avec l'adresse **172.16.1.101** et l'UO **RD Clients** :

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.101 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
$cred = Get-Credential AVAEDOS\Administrator
Add-Computer -DomainName "avaedos.lan" -NewName RDS-CLI1 -Credential $cred `
    -OUPath "OU=RD Clients,DC=avaedos,DC=lan" -Restart
```

**Vérification :** sur RDS-DC1, `Get-ADComputer -Filter * | Select-Object Name, DistinguishedName` affiche chaque machine dans son unité d'organisation.
