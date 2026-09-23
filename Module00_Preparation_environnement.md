---
title: "Ateliers pratiques – Préparation de l'environnement"
subtitle: "Services de Bureau à distance sous Windows Server 2025"
author: "Loïc THOBOIS"
lang: fr-FR
---

# Présentation des ateliers

## Situation

Vous êtes administrateur système chez **Avaedos**. Vous construisez la plateforme de services Bureau à distance de l'entreprise sous Windows Server 2025 : ferme de sessions, applications RemoteApp, profils FSLogix, accès externe sécurisé, haute disponibilité et postes de travail virtuels Windows 11.

Chaque atelier s'appuie sur le résultat du précédent. Chaque participant travaille sur son propre environnement. Le script de préparation déploie les dix premières machines ; chacune est ensuite configurée — nom, adresse IP, jonction au domaine — dans l'atelier où elle sert pour la première fois.

## Conventions

Chaque étape est précédée du nom de la machine sur laquelle elle est réalisée :

| Repère | Machine | Rôle | Configurée à |
|---|---|---|---|
| \[MP\] | Machine physique | Hôte Hyper-V de l'environnement | — |
| \[DC\] | RDS-DC1 | Contrôleur de domaine, DNS, DHCP, autorité de certification, partage des profils, base SQL du Connection Broker | Préparation |
| \[SES1\] à \[SES4\] | RDS-SESSION1 à RDS-SESSION4 | Hôtes de session | Atelier 1 |
| \[CB1\] / \[CB2\] | RDS-CBROKER1 / RDS-CBROKER2 | Connection Broker, licences sur RDS-CBROKER1 | Atelier 1 / atelier 4 |
| \[GTW1\] / \[GTW2\] | RDS-GATEWAY1 / RDS-GATEWAY2 | Accès Web et passerelle | Atelier 1 / atelier 4 |
| \[HV1\] / \[HV2\] | RDS-HYPERV1 / RDS-HYPERV2 | Hôtes de virtualisation VDI | Atelier 5 |
| \[CLI\] | RDS-CLI1 | Poste Windows 11 interne, membre du domaine | Atelier 1 |

Les commandes PowerShell s'exécutent dans une console **Windows PowerShell** lancée en tant qu'administrateur. Sauf indication contraire, ouvrez la session avec le compte **AVAEDOS\\Administrator** et le mot de passe **P@ssw0rd**.

Le mot de passe unique **P@ssw0rd** est une simplification propre au laboratoire. En production, chaque compte a son propre mot de passe et les comptes d'administration sont protégés.

## Plan d'adressage

Toutes les machines sont reliées au même commutateur virtuel, sur le réseau 172.16.0.0/16 (masque **255.255.0.0**). Serveur DNS : **172.16.1.1**. Passerelle par défaut : **172.16.1.254**, le routeur de la salle.

Le commutateur est celui indiqué par le formateur : **Reseau Salle** pour un réseau isolé, ou **Default Switch** lorsque les machines ont besoin d'un accès Internet, par exemple pour télécharger le client web à l'atelier 3.

| Machine | Adresse IP |
|---|---|
| RDS-DC1 | 172.16.1.1 |
| RDS-CLI1 | 172.16.1.101 |
| RDS-SESSION1 à RDS-SESSION4 | 172.16.1.111 à 172.16.1.114 |
| RDS-CBROKER1, RDS-CBROKER2 | 172.16.1.115, 172.16.1.116 |
| RDS-GATEWAY1, RDS-GATEWAY2 | 172.16.1.117, 172.16.1.118 |
| Ferme de passerelles `rds.avaedos.lan` (atelier 4) | 172.16.1.119 |
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
- **Dossier des sources**, copié à l'atelier concerné : FSLogix, pilote ODBC Driver 17 for SQL Server, SQL Server 2025 Express, et, en l'absence d'accès Internet, le module et le paquet du client web RDS.

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
Deploy-VMTemplate -Name RDS-CLI1 -OperatingSystem Windows11FR

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

Les hôtes de virtualisation de l'atelier 5 — **RDS-HYPERV1** et **RDS-HYPERV2** — sont déployés au moment de l'atelier concerné, avec les commandes données sur place.

Les images ISO ne servent qu'à l'atelier 4. Le chemin est repéré dès maintenant pour que les commandes suivantes puissent s'y référer.

## Ajout du serveur Active Directory

### \[DC\]Configurez TCP/IP et renommez la machine en RDS-DC1

RDS-DC1 est le premier serveur : il n'y a pas encore de domaine à joindre.

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.1 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
Start-Sleep -Seconds 5
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
