---
title: "Atelier 3 – Sécurisation et passerelle RDS"
subtitle: "Module 4 : Sécurisation et accès externe"
author: "Loïc THOBOIS"
lang: fr-FR
---

Cet atelier se réalise individuellement, sur votre propre environnement. Il s'appuie sur le résultat de l'atelier précédent. Les conventions, le plan d'adressage et les comptes sont décrits dans le document de préparation (Module00_Preparation_environnement.md).

# Objectif

Sécuriser l'accès à la plateforme : approbation de l'éditeur des fichiers RDP, authentification unique, passerelle RDS limitée aux utilisateurs autorisés et client web, testés depuis un poste hors domaine.

**Livrable :** **lthobois** se connecte depuis RDS-EXT1, poste hors domaine, par le client web et la passerelle **rds.avaedos.lan** ; un compte non autorisé est refusé.

# Approbation automatique de l'éditeur

## \[CB1\]Notez l'empreinte du certificat de publication

```powershell
Import-Module RemoteDesktop
(Get-RDCertificate -Role RDPublishing -ConnectionBroker rds-cbroker1.avaedos.lan).Thumbprint
```

Notez l'empreinte : elle identifie l'éditeur des fichiers RDP d'Avaedos.

## \[DC\]Créez la stratégie GPO RD Clients SSO liée à l'UO RD Clients

Ouvrez **Group Policy Management**, cliquez avec le bouton droit sur **RD Clients**, puis sur **Create a GPO in this domain, and Link it here**. Nommez la stratégie **GPO RD Clients SSO**.

Modifiez la stratégie et développez **Computer Configuration** \\ **Policies** \\ **Administrative Templates** \\ **Windows Components** \\ **Remote Desktop Services** \\ **Remote Desktop Connection Client**.

Ouvrez **Specify SHA1 thumbprints of certificates representing trusted .rdp publishers**, sélectionnez **Enabled** puis collez l'empreinte notée, sans espace.

Dans le même dossier, ouvrez **Allow .rdp files from unknown publishers** et sélectionnez **Disabled** : les fichiers RDP non signés ou d'éditeurs inconnus sont bloqués.

## \[DC\]Activez l'authentification unique vers les serveurs RDS

Dans **GPO RD Clients SSO**, développez **Computer Configuration** \\ **Policies** \\ **Administrative Templates** \\ **System** \\ **Credentials Delegation**.

Ouvrez **Allow delegating default credentials**, sélectionnez **Enabled** puis cliquez sur **Show**. Ajoutez la ligne **TERMSRV/\*.avaedos.lan**.

## \[CLI\]Mettez à jour les stratégies et testez

```powershell
gpupdate /force
```

Fermez puis rouvrez la session Windows de **lthobois** sur RDS-CLI1, puis lancez **Bloc-notes** depuis le menu **Démarrer** (dossier **Work Resources**).

**Résultat attendu :** l'application s'ouvre sans demande d'identifiants et sans avertissement sur l'éditeur.

**Si les identifiants sont encore demandés :** vérifiez l'état de Credential Guard sur RDS-CLI1 dans `msinfo32`, ligne **Services de sécurité basée sur la virtualisation en cours d'exécution**. Credential Guard, activé par défaut sur les postes Windows 11 éligibles, empêche la délégation des identifiants par défaut.

# Ajout de la passerelle

## \[CB1\]Ajoutez le rôle de passerelle sur RDS-GATEWAY1

```powershell
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
Add-RDServer -Server rds-gateway1.avaedos.lan -Role RDS-GATEWAY `
    -ConnectionBroker rds-cbroker1.avaedos.lan -GatewayExternalFqdn rds.avaedos.lan
Set-RDCertificate -Role RDGateway -ImportPath C:\Certificats\rds-avaedos.pfx `
    -Password $mdp -ConnectionBroker rds-cbroker1.avaedos.lan -Force
Set-RDDeploymentGatewayConfiguration -GatewayMode Custom `
    -GatewayExternalFqdn rds.avaedos.lan -LogonMethod Password `
    -UseCachedCredentials $true -BypassLocal $false `
    -ConnectionBroker rds-cbroker1.avaedos.lan -Force
```

**BypassLocal** désactivé oblige aussi les clients internes à passer par la passerelle : le laboratoire vérifie ainsi la chaîne complète.

**Vérification :** `Get-RDServer -ConnectionBroker rds-cbroker1.avaedos.lan` affiche **RDS-GATEWAY** sur RDS-GATEWAY1 ; `Get-RDCertificate` affiche le rôle **RDGateway** au niveau **Trusted**.

## \[GTW1\]Restreignez les stratégies CAP et RAP

L'ajout du rôle crée des stratégies par défaut, trop larges. La CAP définit qui peut utiliser la passerelle ; la RAP définit vers quelles machines.

Lancez **Remote Desktop Gateway Manager** (`tsgateway.msc`), développez **RDS-GATEWAY1** \\ **Policies** \\ **Connection Authorization Policies**.

Ouvrez la stratégie existante. Dans l'onglet **Requirements**, supprimez les groupes présents, ajoutez **AVAEDOS\\RDS Users** et vérifiez que la méthode **Password** est cochée. Dans l'onglet **Device Redirection**, sélectionnez **Disable device redirection for the following client device types** et cochez **Drives**.

Sous **Resource Authorization Policies**, ouvrez la stratégie existante. Dans l'onglet **User Groups**, remplacez les groupes par **AVAEDOS\\RDS Users**. Dans l'onglet **Network Resource**, conservez le groupe de ressources géré par le déploiement RDS. Dans l'onglet **Allowed Ports**, conservez **3389**.

**Résultat attendu :** une CAP et une RAP, toutes deux limitées à **RDS Users**.

## \[GTW1\]Vérifiez l'écoute de la passerelle

```powershell
Get-NetTCPConnection -LocalPort 443 -State Listen
Get-NetUDPEndpoint -LocalPort 3391
```

**Résultat attendu :** la passerelle écoute en TCP 443 (HTTPS) et en UDP 3391 (transport UDP).

# Installation du client web

## \[GTW1\]Installez et publiez le client web

Le client web exige une passerelle dans le déploiement, un mode de licence par utilisateur et le certificat du Connection Broker.

Le réseau de la salle étant isolé, le module PowerShell et le paquet du client sont déjà présents dans **C:\\AVAEDOS\\_RDS\\WebClient** : c'est la procédure hors ligne de Microsoft.

```powershell
New-Item -ItemType Directory -Path C:\Certificats -Force
Copy-Item \\rds-cbroker1\C$\Certificats\rds-avaedos.cer C:\Certificats\ -Force
$env:PSModulePath += ";C:\AVAEDOS\_RDS\WebClient"
Import-Module RDWebClientManagement
$paquet = (Get-ChildItem C:\AVAEDOS\_RDS\WebClient\rdwebclient-*.zip | Select-Object -Last 1).FullName
Install-RDWebClientPackage -Source $paquet
Import-RDWebClientBrokerCert C:\Certificats\rds-avaedos.cer
Publish-RDWebClientPackage -Type Production -Latest
```

Un avertissement sur les CAL par périphérique peut s'afficher : il est sans objet en mode par utilisateur.

**Avec un accès Internet :** le module et le paquet se téléchargent directement, avec `Install-Module -Name RDWebClientManagement -Force` puis `Install-RDWebClientPackage` sans `-Source`. Acceptez alors l'installation du fournisseur NuGet et du dépôt PSGallery.

**Vérification :** `Get-RDWebClientPackage` affiche la version installée et la colonne **Published**.

## \[CLI\]Testez le client web depuis le réseau interne

Dans **Microsoft Edge**, ouvrez **https://rds.avaedos.lan/RDWeb/webclient/index.html** et connectez-vous avec **AVAEDOS\\lthobois**.

**Résultat attendu :** le client web affiche le bureau et les deux RemoteApp ; le Bloc-notes s'ouvre dans l'onglet du navigateur.

# Connexion depuis un poste hors domaine

## \[MP\]Créez le poste RDS-EXT1

```powershell
Deploy-VMTemplate -Name "RDS-EXT1" -OperatingSystem Windows11US
Wait-VMToStart -VMName "RDS-EXT1"
Get-VMIntegrationService -VMName "RDS-EXT1" | Where-Object Id -like "*6C09BB55*" | Enable-VMIntegrationService
```

RDS-EXT1 reste hors du domaine : ne le joignez pas à **avaedos.lan**.

## \[EXT\]Configurez le poste hors domaine

RDS-EXT1 simule un poste personnel : il n'est pas membre du domaine et ne fait pas confiance à l'autorité de certification d'Avaedos. En laboratoire, il est sur le même réseau que les serveurs ; en production, il se connecterait depuis Internet et seule la passerelle serait joignable.

Ouvrez une session avec le compte local fourni par le formateur, puis :

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.102 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
Start-Sleep -Seconds 5
Rename-Computer -NewName RDS-EXT1 -Restart
```

## \[DC\]Exportez le certificat de l'autorité racine

```powershell
New-Item -ItemType Directory -Path C:\Certificats -Force
certutil -ca.cert C:\Certificats\RDS-CA.cer
New-SmbShare -Name "Certificats" -Path C:\Certificats -ReadAccess "AVAEDOS\Domain Users"
```

Le partage **Certificats** existe le temps de l'atelier : RDS-EXT1 n'étant pas membre du domaine, il ne reçoit pas l'autorité racine par stratégie de groupe.

## \[EXT\]Approuvez l'autorité de certification d'Avaedos

Ouvrez **\\\\RDS-DC1\\Certificats** avec le compte **AVAEDOS\\lthobois**, copiez **RDS-CA.cer** dans **C:\\Certificats**, puis :

```powershell
Import-Certificate -FilePath C:\Certificats\RDS-CA.cer -CertStoreLocation Cert:\LocalMachine\Root
```

En production, le certificat de la passerelle est émis par une autorité publique : cette étape n'existe pas pour les utilisateurs.

## \[EXT\]Connectez-vous par le client web

Dans **Microsoft Edge**, ouvrez **https://rds.avaedos.lan/RDWeb/webclient/index.html** et connectez-vous avec **AVAEDOS\\lthobois**. Lancez le bureau **RdsSesColl1**.

**Résultat attendu :** la session s'ouvre depuis RDS-EXT1, poste hors domaine.

## \[GTW1\]Retrouvez la connexion dans le journal de la passerelle

```powershell
Get-WinEvent -LogName "Microsoft-Windows-TerminalServices-Gateway/Operational" -MaxEvents 20 |
    Format-Table TimeCreated, Id, Message -Wrap
```

**Résultat attendu :** un événement indique que **AVAEDOS\\lthobois** s'est connecté à la ressource, avec l'adresse source **172.16.1.102** : la connexion est bien passée par la passerelle.

## \[EXT\]Vérifiez le refus d'un compte non autorisé

Le portail n'affiche aucune ressource à un compte absent des groupes des collections : le test passe donc par une connexion directe à travers la passerelle.

Lancez **Connexion Bureau à distance** (`mstsc`), cliquez sur **Afficher les options**, onglet **Avancé**, bouton **Paramètres**. Sélectionnez **Utiliser ces paramètres de serveur de passerelle Bureau à distance**, tapez **rds.avaedos.lan** et décochez **Ne pas utiliser de serveur de passerelle Bureau à distance pour les adresses locales**. Dans l'onglet **Général**, tapez **rds-session1.avaedos.lan** puis connectez-vous avec **AVAEDOS\\Administrator**.

**Résultat attendu :** la passerelle refuse la connexion : **Administrator** n'est pas membre de **RDS Users**, la CAP ne l'autorise pas, alors qu'il est administrateur de l'hôte de session.

**Vérification :** le journal de la passerelle contient un événement de refus pour **AVAEDOS\\Administrator** qui cite la stratégie d'autorisation des connexions.

# Démonstration formateur : authentification multifacteur

Le formateur présente l'extension NPS de Microsoft Entra MFA : les CAP de la passerelle sont déportées vers un serveur NPS central, qui ajoute une notification sur l'application Microsoft Authenticator. Cette partie exige un tenant Microsoft Entra et n'est pas réalisée par les participants.

# Ce qu'il faut retenir

La passerelle est le seul point d'entrée depuis Internet : elle n'expose que HTTPS et contrôle chaque connexion par sa CAP et sa RAP. La signature des fichiers RDP et l'approbation de l'éditeur protègent les utilisateurs contre les fichiers RDP piégés.

# Erreurs fréquentes

| Symptôme | Cause probable | Correction |
|---|---|---|
| « Le certificat de la passerelle n'est pas approuvé » | Autorité racine non importée sur RDS-EXT1 | Importer **RDS-CA** dans **Root** de l'ordinateur |
| Client web : ressources visibles mais connexion impossible | Certificat du Connection Broker non importé ou passerelle absente | Relancer `Import-RDWebClientBrokerCert` puis `Publish-RDWebClientPackage` |
| Refus alors que l'utilisateur est autorisé | Groupe modifié dans la CAP mais pas dans la RAP | Aligner les deux stratégies |
| Session lente par la passerelle | UDP 3391 bloqué | Vérifier `Get-NetUDPEndpoint -LocalPort 3391` et le pare-feu |
