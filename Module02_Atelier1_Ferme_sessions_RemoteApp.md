---
title: "Atelier 1 – Ferme de sessions et RemoteApp"
subtitle: "Module 2 : Déploiement et publication des ressources"
author: "Loïc THOBOIS"
lang: fr-FR
---

Cet atelier se réalise individuellement, sur votre propre environnement. Il s'appuie sur l'environnement construit dans le document de préparation. Les conventions, le plan d'adressage et les comptes sont décrits dans le document de préparation (Module00_Preparation_environnement.md).

# Objectif

Déployer la ferme de sessions d'Avaedos, installer le serveur de licences et les certificats, publier un bureau de session et des applications RemoteApp dans deux collections distinctes, puis les utiliser depuis le poste RDS-CLI1.

**Livrable :** la collection **RdsSesColl1** (RDS-SESSION1 et RDS-SESSION2) publie le bureau de session ; la collection **RdsAppColl1** (RDS-SESSION3 et RDS-SESSION4) publie deux RemoteApp. Les deux sont accessibles à **lthobois**.

# Configuration des machines de la ferme

Ces six machines ont été déployées avec le script de préparation, mais elles n'ont encore ni nom, ni adresse, ni domaine. Configurez chacune avant de vous en servir : ouvrez une session avec le compte local **Administrator** et le mot de passe **P@ssw0rd**, puis collez le bloc correspondant.

## \[CB1\]Configurez RDS-CBROKER1

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.115 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential "AVAEDOS\Administrator", $mdp
Add-Computer -DomainName "avaedos.lan" -NewName RDS-CBROKER1 -Credential $cred `
    -OUPath "OU=RD Servers,DC=avaedos,DC=lan" -Restart
```

## \[SES1\]Configurez RDS-SESSION1

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.111 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential "AVAEDOS\Administrator", $mdp
Add-Computer -DomainName "avaedos.lan" -NewName RDS-SESSION1 -Credential $cred `
    -OUPath "OU=RD Servers,DC=avaedos,DC=lan" -Restart
```

## \[SES2\]Configurez RDS-SESSION2

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.112 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential "AVAEDOS\Administrator", $mdp
Add-Computer -DomainName "avaedos.lan" -NewName RDS-SESSION2 -Credential $cred `
    -OUPath "OU=RD Servers,DC=avaedos,DC=lan" -Restart
```

## \[SES3\]Configurez RDS-SESSION3

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.113 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential "AVAEDOS\Administrator", $mdp
Add-Computer -DomainName "avaedos.lan" -NewName RDS-SESSION3 -Credential $cred `
    -OUPath "OU=RD Servers,DC=avaedos,DC=lan" -Restart
```

## \[SES4\]Configurez RDS-SESSION4

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.114 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential "AVAEDOS\Administrator", $mdp
Add-Computer -DomainName "avaedos.lan" -NewName RDS-SESSION4 -Credential $cred `
    -OUPath "OU=RD Servers,DC=avaedos,DC=lan" -Restart
```

## \[GTW1\]Configurez RDS-GATEWAY1

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.117 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential "AVAEDOS\Administrator", $mdp
Add-Computer -DomainName "avaedos.lan" -NewName RDS-GATEWAY1 -Credential $cred `
    -OUPath "OU=RD Servers,DC=avaedos,DC=lan" -Restart
```

## \[CLI\]Configurez RDS-CLI1

Ouvrez une session avec le compte local fourni par le formateur, puis collez :

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.101 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential "AVAEDOS\Administrator", $mdp
Add-Computer -DomainName "avaedos.lan" -NewName RDS-CLI1 -Credential $cred `
    -OUPath "OU=RD Clients,DC=avaedos,DC=lan" -Restart
```

Le poste rejoint l'UO **RD Clients** : c'est elle qui portera la stratégie **GPO RD Clients SSO** de l'atelier 3.

## \[DC\]Ajoutez les serveurs au groupe RDS Servers

```powershell
Add-ADGroupMember "RDS Servers" -Members "RDS-SESSION1$", "RDS-SESSION2$", "RDS-SESSION3$", `
    "RDS-SESSION4$", "RDS-CBROKER1$", "RDS-GATEWAY1$"
```

**Vérification :** `Get-ADGroupMember "RDS Servers" | Select-Object Name` liste les six serveurs, et `Get-ADComputer RDS-CLI1` le place dans l'UO **RD Clients**.

# Installation du service Bureau à distance

## \[CB1\]Déployez les services de rôle

Le déploiement se pilote depuis RDS-CBROKER1, qui installe les rôles à distance sur les autres serveurs. L'accès Web est installé sur RDS-GATEWAY1, qui recevra aussi la passerelle à l'atelier 3 : les deux rôles exposés aux utilisateurs sont ainsi regroupés.

```powershell
Import-Module RemoteDesktop
New-RDSessionDeployment -ConnectionBroker rds-cbroker1.avaedos.lan `
    -WebAccessServer rds-gateway1.avaedos.lan `
    -SessionHost rds-session1.avaedos.lan, rds-session2.avaedos.lan, `
                 rds-session3.avaedos.lan, rds-session4.avaedos.lan
```

Les hôtes de session redémarrent pendant l'installation.

**Résultat attendu :** la commande se termine sans erreur.

**Vérification :**

```powershell
Get-RDServer -ConnectionBroker rds-cbroker1.avaedos.lan
```

La liste affiche **RDS-CONNECTION-BROKER** sur RDS-CBROKER1, **RDS-WEB-ACCESS** sur RDS-GATEWAY1 et **RDS-RD-SERVER** sur les quatre hôtes de session.

## \[CB1\]Observez le déploiement dans Server Manager

Dans **Server Manager**, ajoutez les serveurs RDS au pool (**Manage** \\ **Add Servers**), puis créez un groupe de serveurs **RDS** qui les contient. Ouvrez **Remote Desktop Services** \\ **Overview**.

**Résultat attendu :** le schéma **Deployment Overview** montre l'accès Web, le Connection Broker et les hôtes de session installés ; la passerelle et les licences restent à ajouter.

# Déploiement du serveur de licences

## \[CB1\]Ajoutez le serveur de licences et définissez le mode de licence

Le serveur de licences consomme peu de ressources : il est installé sur RDS-CBROKER1. Le mode **par utilisateur** est exigé par le client web installé à l'atelier 3.

```powershell
Add-RDServer -Server rds-cbroker1.avaedos.lan -Role RDS-LICENSING `
    -ConnectionBroker rds-cbroker1.avaedos.lan
Set-RDLicenseConfiguration -LicenseServer rds-cbroker1.avaedos.lan `
    -Mode PerUser -ConnectionBroker rds-cbroker1.avaedos.lan -Force
Get-RDLicenseConfiguration -ConnectionBroker rds-cbroker1.avaedos.lan
```

## \[CB1\]Examinez le serveur de licences

Lancez **Remote Desktop Licensing Manager** (`licmgr.exe`). Le serveur **RDS-CBROKER1** apparaît avec l'état **Not activated**.

Lancez **RD Licensing Diagnoser** (`lsdiag.msc`).

**Résultat attendu :** l'outil signale que le serveur de licences n'est pas activé et qu'aucune CAL n'est disponible, et indique la période de grâce en cours.

L'activation du serveur et l'installation des CAL exigent un accord de licence : elles ne sont pas réalisées en formation. La période de grâce de 120 jours couvre le laboratoire. En production, activez le serveur par l'assistant **Activate Server**, puis installez les CAL par **Install Licenses** ; des CAL 2025 exigent un serveur de licences Windows Server 2025.

# Installation des certificats du déploiement

## \[CB1\]Demandez le certificat du déploiement

Un seul certificat couvre tous les noms utilisés : **rds.avaedos.lan** pour l'accès Web et la passerelle, **rds-farm.avaedos.lan** pour la ferme de Connection Brokers de l'atelier 4, et les noms des serveurs concernés.

RDS-CBROKER1 a rejoint le domaine avant la création de l'autorité : actualisez d'abord ses stratégies pour qu'il reçoive le certificat racine de **RDS-CA**.

```powershell
gpupdate /force
New-Item -ItemType Directory -Path C:\Certificats -Force
$demande = Get-Certificate -Template WebServerRDS -SubjectName "CN=rds.avaedos.lan" `
    -DnsName rds.avaedos.lan, rds-farm.avaedos.lan, `
             rds-cbroker1.avaedos.lan, rds-cbroker2.avaedos.lan, `
             rds-gateway1.avaedos.lan, rds-gateway2.avaedos.lan `
    -CertStoreLocation Cert:\LocalMachine\My
$cert = $demande.Certificate
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
Export-PfxCertificate -Cert $cert -FilePath C:\Certificats\rds-avaedos.pfx -Password $mdp
Export-Certificate -Cert $cert -FilePath C:\Certificats\rds-avaedos.cer
```

**Résultat attendu :** `$demande.Status` vaut **Issued** ; les fichiers **rds-avaedos.pfx** et **rds-avaedos.cer** existent.

**Si la demande échoue :** vérifiez que le modèle **WebServer RDS** est publié sur l'autorité et que **Domain Computers** dispose de l'autorisation **Enroll**, puis relancez `gpupdate /force`. La même demande peut aussi se faire dans la console `certlm.msc`, en renseignant le nom commun et les noms DNS.

## \[CB1\]Affectez le certificat aux rôles du déploiement

```powershell
foreach ($role in "RDRedirector","RDPublishing","RDWebAccess") {
    Set-RDCertificate -Role $role -ImportPath C:\Certificats\rds-avaedos.pfx `
        -Password $mdp -ConnectionBroker rds-cbroker1.avaedos.lan -Force
}
```

Les rôles se lisent ainsi : **RDRedirector** pour l'authentification unique vers les hôtes, **RDPublishing** pour la signature des fichiers RDP, **RDWebAccess** pour le portail. Le rôle **RDGateway** est ajouté à l'atelier 3.

**Vérification :**

```powershell
Get-RDCertificate -ConnectionBroker rds-cbroker1.avaedos.lan
```

Les trois rôles affichent le niveau **Trusted** et le sujet **CN=rds.avaedos.lan**.

# Création des collections

## \[CB1\]Créez la collection de bureaux RdsSesColl1

```powershell
New-RDSessionCollection -CollectionName "RdsSesColl1" -CollectionDescription "Bureaux de session" `
    -SessionHost rds-session1.avaedos.lan, rds-session2.avaedos.lan `
    -ConnectionBroker rds-cbroker1.avaedos.lan
Set-RDSessionCollectionConfiguration -CollectionName "RdsSesColl1" `
    -UserGroup "AVAEDOS\RDS Users" -ConnectionBroker rds-cbroker1.avaedos.lan
```

La collection ajoute automatiquement le groupe autorisé au groupe local **Remote Desktop Users** de chaque hôte : aucun ajout manuel n'est nécessaire.

**Vérification :** `Get-RDSessionCollectionConfiguration -CollectionName RdsSesColl1 -UserGroup -ConnectionBroker rds-cbroker1.avaedos.lan` affiche **AVAEDOS\\RDS Users**.

## \[CB1\]Créez la collection d'applications RdsAppColl1

Une collection est typée : RdsSesColl1 publie des bureaux, RdsAppColl1 publie des applications. Chaque hôte appartient à une seule collection.

```powershell
New-RDSessionCollection -CollectionName "RdsAppColl1" -CollectionDescription "Applications RemoteApp" `
    -SessionHost rds-session3.avaedos.lan, rds-session4.avaedos.lan `
    -ConnectionBroker rds-cbroker1.avaedos.lan
Set-RDSessionCollectionConfiguration -CollectionName "RdsAppColl1" `
    -UserGroup "AVAEDOS\RDS Users" -ConnectionBroker rds-cbroker1.avaedos.lan
```

**Vérification :** `Get-RDSessionCollection -ConnectionBroker rds-cbroker1.avaedos.lan` liste les deux collections.

## \[CLI\]Connectez-vous au bureau de session

Ouvrez une session sur RDS-CLI1 avec **AVAEDOS\\lthobois**.

Lancez **Connexion Bureau à distance** (`mstsc`) et connectez-vous à **rds-session1.avaedos.lan**.

**Résultat attendu :** le bureau de session s'ouvre. Le Connection Broker peut rediriger la connexion vers RDS-SESSION2 : c'est le comportement normal d'une collection.

**Vérification :** dans la session, `hostname` indique l'hôte réellement utilisé. Sur RDS-CBROKER1 :

```powershell
Get-RDUserSession -ConnectionBroker rds-cbroker1.avaedos.lan
```

Fermez la session Bureau à distance (**Démarrer** \\ **Se déconnecter**).

# Déploiement d'applications distantes

## \[CB1\]Publiez le Bloc-notes et la Table des caractères en RemoteApp

WordPad n'existe plus dans Windows Server 2025. Le Bloc-notes et la Table des caractères sont présents sur tous les hôtes : une application publiée doit être installée à l'identique sur chaque hôte de la collection.

```powershell
New-RDRemoteApp -CollectionName "RdsAppColl1" -Alias "Notepad" -DisplayName "Bloc-notes" `
    -FilePath "C:\Windows\System32\notepad.exe" -ShowInWebAccess $true `
    -ConnectionBroker rds-cbroker1.avaedos.lan
New-RDRemoteApp -CollectionName "RdsAppColl1" -Alias "Charmap" -DisplayName "Table des caractères" `
    -FilePath "C:\Windows\System32\charmap.exe" -ShowInWebAccess $true `
    -ConnectionBroker rds-cbroker1.avaedos.lan
```

**Vérification :** `Get-RDRemoteApp -CollectionName RdsAppColl1 -ConnectionBroker rds-cbroker1.avaedos.lan` liste les deux applications.

## \[CLI\]Lancez les ressources depuis le portail d'accès Web

Si RDS-CLI1 n'a pas redémarré depuis l'installation de l'autorité, actualisez ses stratégies pour qu'il approuve **RDS-CA** : `gpupdate /force`.

Dans **Microsoft Edge**, ouvrez **https://rds.avaedos.lan/RDWeb** et connectez-vous avec **AVAEDOS\\lthobois**.

**Résultat attendu :** le portail affiche le bureau **RdsSesColl1**, le **Bloc-notes** et la **Table des caractères**, sans avertissement de certificat.

Cliquez sur **Bloc-notes**, ouvrez le fichier RDP téléchargé puis cliquez sur **Connect**.

**Résultat attendu :** le Bloc-notes s'ouvre dans une fenêtre qui s'intègre au bureau de RDS-CLI1. La boîte de dialogue de connexion indique l'éditeur **rds.avaedos.lan** : le fichier est signé par le certificat de publication.

## \[CLI\]Comparez avec l'application locale

Lancez le Bloc-notes local de RDS-CLI1.

Quelle différence observez-vous entre les deux fenêtres ? Comment l'utilisateur peut-il savoir laquelle est distante ?

Fermez les deux fenêtres.

## \[CLI\]Abonnez le poste au flux RemoteApp

Le flux d'abonnement intègre les ressources au menu **Démarrer**, sans passer par le portail.

Ouvrez **Panneau de configuration** \\ **Connexions RemoteApp et Bureau à distance** puis cliquez sur **Accéder aux RemoteApp et aux bureaux**.

Tapez **https://rds.avaedos.lan/RDWeb/Feed/webfeed.aspx** puis suivez l'assistant avec le compte **AVAEDOS\\lthobois**.

**Résultat attendu :** un dossier **Work Resources (RADC)** apparaît dans le menu **Démarrer** avec les deux applications et le bureau.

# Ce qu'il faut retenir

Le déploiement repose sur le Connection Broker : c'est lui qui choisit l'hôte, signe les ressources publiées et fournit le flux. Une collection est typée, bureau ou applications ; une application publiée doit exister sur tous les hôtes de sa collection, sinon l'utilisateur rencontre des erreurs aléatoires selon l'hôte choisi.

# Erreurs fréquentes

| Symptôme | Cause probable | Correction |
|---|---|---|
| `New-RDSessionDeployment` échoue sur un serveur | Serveur injoignable ou redémarrage en attente | Vérifier `Test-WSMan <serveur>`, redémarrer puis relancer |
| Avertissement de certificat sur le portail | Certificat non affecté au rôle RDWebAccess ou nom différent | Relancer `Set-RDCertificate` ; utiliser l'URL **rds.avaedos.lan** |
| « Vous n'avez pas accès à cette session » | Utilisateur hors de **RDS Users** ou jeton non actualisé | Vérifier l'appartenance, fermer puis rouvrir la session Windows |
| RemoteApp absente du portail | Application publiée dans une autre collection ou visibilité limitée | `Get-RDRemoteApp` puis `Set-RDRemoteApp -UserGroups` |
| Le poste client refuse le certificat du portail | L'autorité **RDS-CA** n'est pas encore dans les racines de confiance | `gpupdate /force` sur le poste, puis rouvrir le navigateur |
| Une commande `*-RD*` renvoie « n'est pas reconnu » dans une session distante | Le module n'est pas chargé automatiquement hors session interactive | Débuter le bloc par `Import-Module RemoteDesktop` |
| Un test `if (Get-RDSessionCollection -CollectionName …)` se comporte comme si la collection existait | La commande renvoie un objet même quand la collection est absente | Tester sur la liste : `(Get-RDSessionCollection).CollectionName -contains "…"` |
