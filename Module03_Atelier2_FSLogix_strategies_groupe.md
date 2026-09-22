---
title: "Atelier 2 – FSLogix et stratégies de groupe"
subtitle: "Module 3 : Expérience utilisateur"
author: "Loïc THOBOIS"
lang: fr-FR
---

Cet atelier se réalise individuellement, sur votre propre environnement. Il s'appuie sur le résultat de l'atelier précédent. Les conventions, le plan d'adressage et les comptes sont décrits dans le document de préparation (Module00_Preparation_environnement.md).

# Objectif

Rendre l'expérience utilisateur identique quel que soit l'hôte : profils FSLogix, paramètres de session par stratégie de groupe, impression et assistance aux utilisateurs.

**Livrable :** le profil de **lthobois** est stocké dans un conteneur VHDX sur **\\\\RDS-DC1\\ProfilDisk** et la stratégie **GPO RD Sessions** s'applique aux hôtes de session.

# Préparation du stockage des profils

## \[DC\]Réglez les autorisations du dossier ProfilDisk

Chaque utilisateur doit pouvoir créer son propre dossier, sans voir celui des autres. Les autorisations suivent la recommandation FSLogix : droit de modification limité au dossier racine pour les utilisateurs, contrôle total du créateur sur son sous-dossier.

```powershell
icacls C:\ProfilDisk /inheritance:r `
    /grant "SYSTEM:(OI)(CI)F" "AVAEDOS\Domain Admins:(OI)(CI)F" `
    "CREATOR OWNER:(OI)(CI)(IO)M" "AVAEDOS\RDS Users:(M)"
```

Le partage **ProfilDisk** a été créé lors de la préparation.

**Vérification :** `icacls C:\ProfilDisk` affiche **(M)** sans **(OI)(CI)** pour **RDS Users** : le droit porte sur ce dossier seulement.

# Déploiement de FSLogix

## \[CB1\]Installez l'agent FSLogix sur les hôtes de session

L'agent doit être installé sur tous les hôtes des deux collections. L'installateur est déjà présent sur chaque machine dans **C:\\AVAEDOS\\_RDS\\FSLogix** : il est lancé localement, sans lecture de partage réseau depuis une session distante.

```powershell
$hotes = "rds-session1","rds-session2","rds-session3","rds-session4"
Invoke-Command -ComputerName $hotes -ScriptBlock {
    Start-Process C:\AVAEDOS\_RDS\FSLogix\FSLogixAppsSetup.exe `
        -ArgumentList "/install /quiet /norestart" -Wait
    "$env:COMPUTERNAME : " + (Get-Service frxsvc -ErrorAction SilentlyContinue).Status
}
```

**Résultat attendu :** le service **frxsvc** est **Running** sur les quatre hôtes.

## \[CB1\]Configurez les conteneurs de profil

```powershell
Invoke-Command -ComputerName $hotes -ScriptBlock {
    $cle = "HKLM:\SOFTWARE\FSLogix\Profiles"
    New-Item -Path $cle -Force | Out-Null
    New-ItemProperty -Path $cle -Name Enabled -Value 1 -PropertyType DWord -Force
    New-ItemProperty -Path $cle -Name VHDLocations -Value "\\RDS-DC1\ProfilDisk" -PropertyType MultiString -Force
    New-ItemProperty -Path $cle -Name VolumeType -Value "VHDX" -PropertyType String -Force
    New-ItemProperty -Path $cle -Name DeleteLocalProfileWhenVHDShouldApply -Value 1 -PropertyType DWord -Force
    New-ItemProperty -Path $cle -Name FlipFlopProfileDirectoryName -Value 1 -PropertyType DWord -Force
    Add-LocalGroupMember -Group "FSLogix Profile Exclude List" -Member "AVAEDOS\Domain Admins"
}
```

**FlipFlopProfileDirectoryName** nomme les dossiers **utilisateur_SID** plutôt que **SID_utilisateur**, plus lisibles pour l'administrateur. Les administrateurs sont exclus : leurs sessions gardent un profil local.

En production, ces paramètres se gèrent par stratégie de groupe avec les modèles d'administration FSLogix.

## \[CLI\]Ouvrez une session et vérifiez le conteneur

Connectez-vous avec **AVAEDOS\\lthobois** au bureau **RdsSesColl1** depuis le portail ou le flux.

Dans la session, modifiez un paramètre visible : l'arrière-plan du bureau par exemple, puis fermez la session (**Se déconnecter**).

**Vérification :** sur RDS-DC1, `Get-ChildItem C:\ProfilDisk -Recurse` affiche un dossier **lthobois_S-1-5-...** contenant **Profile_lthobois.VHDX**.

## \[CB1\]Forcez l'ouverture sur l'autre hôte

Notez l'hôte utilisé par la session précédente (`Get-RDUserSession` pendant la session). Mettez-le en drainage pour obliger le Connection Broker à choisir l'autre hôte. Exemple si la session était sur RDS-SESSION1 :

```powershell
Import-Module RemoteDesktop
Set-RDSessionHost -SessionHost rds-session1.avaedos.lan -NewConnectionAllowed No `
    -ConnectionBroker rds-cbroker1.avaedos.lan
```

Reconnectez **lthobois** au bureau.

**Résultat attendu :** la session s'ouvre sur RDS-SESSION2 avec le même arrière-plan.

Remettez l'hôte en service :

```powershell
Set-RDSessionHost -SessionHost rds-session1.avaedos.lan -NewConnectionAllowed Yes `
    -ConnectionBroker rds-cbroker1.avaedos.lan
```

**Interprétation :** le profil a suivi l'utilisateur d'un hôte à l'autre sans copie de fichiers. Il sert aussi aux RemoteApp de RdsAppColl1, mais pas simultanément : un conteneur ne se monte que dans une session à la fois. Ouvrir en même temps un bureau et une RemoteApp de l'autre collection exige un paramétrage spécifique de FSLogix (`ProfileType`), à défaut la seconde session reçoit un profil temporaire. Le mode drainage, utilisé ici pour l'exercice, est l'outil de maintenance étudié à l'atelier 4.

# Configuration des sessions par stratégie de groupe

## \[DC\]Créez la stratégie GPO RD Sessions liée à l'UO RD Servers

```powershell
$gpo = New-GPO -Name "GPO RD Sessions"
$gpo | New-GPLink -Target "OU=RD Servers,DC=avaedos,DC=lan"
$cle = "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
$parametres = @{
    "MaxDisconnectionTime"  = 3600000   # fermer une session déconnectée après 1 heure
    "MaxIdleTime"           = 7200000   # déconnecter une session inactive après 2 heures
    "fSingleSessionPerUser" = 1         # une seule session par utilisateur
    "fDisableCdm"           = 1         # pas de redirection des lecteurs locaux
    "fForceClientLptDef"    = 1         # imprimante par défaut du client uniquement
    "Shadow"                = 1         # contrôle total avec accord de l'utilisateur
}
foreach ($nom in $parametres.Keys) {
    Set-GPRegistryValue -Name "GPO RD Sessions" -Key $cle -ValueName $nom `
        -Type DWord -Value $parametres[$nom]
}
```

Les délais s'expriment en millisecondes. Chaque valeur correspond à un paramètre de **Configuration ordinateur** \\ **Modèles d'administration** \\ **Composants Windows** \\ **Services Bureau à distance** \\ **Hôte de session Bureau à distance**. La stratégie s'applique aussi aux autres serveurs de l'UO, qui ne portent pas de sessions utilisateur : sans effet sur eux.

## \[DC\]Examinez la stratégie dans la console

Ouvrez **Group Policy Management**, puis modifiez **GPO RD Sessions**.

**Résultat attendu :** les paramètres apparaissent comme **Activé** dans les dossiers **Délais d'expiration de session**, **Connexions**, **Redirection de périphérique et de ressource** et **Redirection d'imprimante**.

## \[SES1\]Mettez à jour et vérifiez les stratégies

Sur chaque hôte de session :

```powershell
gpupdate /force
gpresult /r /scope computer
```

**Résultat attendu :** **GPO RD Sessions** figure dans la liste des objets de stratégie de groupe appliqués.

**Interprétation :** les paramètres définis par stratégie de groupe l'emportent sur les propriétés des collections. Dans Server Manager, les propriétés de **RdsSesColl1** ne reflètent pas ces valeurs.

# Mise en place de l'impression

## \[CLI\]Vérifiez l'imprimante locale

Sur RDS-CLI1, dans **Paramètres** \\ **Bluetooth et appareils** \\ **Imprimantes et scanners**, vérifiez que **Microsoft Print to PDF** est l'imprimante par défaut.

## \[CLI\]Vérifiez la redirection Easy Print

Connectez-vous avec **AVAEDOS\\lthobois** au bureau **RdsSesColl1**. Dans la session, ouvrez **Imprimantes et scanners**.

**Résultat attendu :** une seule imprimante redirigée apparaît, **Microsoft Print to PDF (redirection n)**, qui utilise le pilote **Remote Desktop Easy Print**.

**Vérification :** dans la session, `Get-Printer | Select-Object Name, DriverName` confirme le pilote.

**Interprétation :** aucun pilote constructeur n'a été installé sur l'hôte. C'est la trajectoire imposée par la fin des pilotes d'impression tiers sous Windows Server 2025.

# Gestion des sessions

## \[CB1\]Prenez le contrôle de la session de lthobois

Laissez la session de **lthobois** ouverte sur RDS-CLI1.

Sur RDS-CBROKER1, dans **Server Manager** \\ **Remote Desktop Services** \\ **Collections** \\ **RdsSesColl1**, section **Connections**, cliquez avec le bouton droit sur la session de **lthobois** puis sélectionnez **Shadow**. Choisissez **Control** et laissez cochée **Prompt for user consent**.

## \[CLI\]Acceptez la demande de prise de contrôle

**Résultat attendu :** dans la session de **lthobois**, une fenêtre demande l'autorisation de contrôle. Après acceptation, l'administrateur voit et pilote la session.

## \[CB1\]Envoyez un message et déconnectez la session

```powershell
$s = Get-RDUserSession -ConnectionBroker rds-cbroker1.avaedos.lan | Where-Object UserName -eq "lthobois"
Send-RDUserMessage -HostServer $s.HostServer -UnifiedSessionID $s.UnifiedSessionId `
    -MessageTitle "Maintenance" -MessageBody "Votre session va être déconnectée."
Disconnect-RDUser -HostServer $s.HostServer -UnifiedSessionID $s.UnifiedSessionId -Force
```

**Résultat attendu :** le message s'affiche dans la session puis la session est déconnectée ; elle reste visible à l'état **Disconnected** jusqu'à l'expiration du délai défini par la stratégie.

# Ce qu'il faut retenir

Le conteneur FSLogix rend l'hôte de session interchangeable pour l'utilisateur ; un même profil sert aux bureaux comme aux RemoteApp, une session à la fois. Les stratégies de groupe fixent des limites de session et des redirections cohérentes sur tous les hôtes, et leur valeur prime sur celle des collections.

# Erreurs fréquentes

| Symptôme | Cause probable | Correction |
|---|---|---|
| Profil temporaire à l'ouverture de session | Partage inaccessible ou droits insuffisants | Vérifier `\\RDS-DC1\ProfilDisk` depuis l'hôte, les droits NTFS et le journal `C:\ProgramData\FSLogix\Logs` |
| Aucun conteneur créé | Utilisateur dans la liste d'exclusion ou agent non installé | Vérifier les groupes locaux FSLogix et le service **frxsvc** |
| « Le profil est déjà utilisé » | Session ouverte dans l'autre collection ou sur l'autre hôte | Fermer la session existante, vérifier `fSingleSessionPerUser` |
| Paramètres de session non appliqués | Hôte hors de l'UO **RD Servers** | `gpresult /r` puis déplacer le compte ordinateur |
