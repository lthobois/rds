---
title: "Atelier 4 – Haute disponibilité et diagnostic"
subtitle: "Module 5 : Haute disponibilité et exploitation"
author: "Loïc THOBOIS"
lang: fr-FR
---

Cet atelier se réalise individuellement, sur votre propre environnement. Il s'appuie sur le résultat de l'atelier précédent. Les conventions, le plan d'adressage et les comptes sont décrits dans le document de préparation (Module00_Preparation_environnement.md).

# Objectif

Supprimer les points de défaillance uniques : Connection Broker en haute disponibilité avec une base SQL Server, ferme de passerelles et d'accès Web en équilibrage de charge. Pratiquer ensuite la maintenance sans interruption d'un hôte de session et diagnostiquer une panne.

**Livrable :** le déploiement fonctionne avec l'un ou l'autre Connection Broker arrêté, et avec l'une ou l'autre passerelle arrêtée ; RDS-SESSION1 peut être drainé sans couper le service.

# Ajout des nouveaux serveurs

RDS-CBROKER2 et RDS-GATEWAY2 existent déjà : le script de préparation les a déployés. Aucune machine n'est à créer dans cet atelier. Configurez-les avant de vous en servir : ouvrez une session avec le compte local **Administrator** et le mot de passe **P@ssw0rd**.

## \[CB2\]Configurez RDS-CBROKER2

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.116 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
Start-Sleep -Seconds 5
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential "AVAEDOS\Administrator", $mdp
Add-Computer -DomainName "avaedos.lan" -NewName RDS-CBROKER2 -Credential $cred `
    -OUPath "OU=RD Servers,DC=avaedos,DC=lan" -Restart
```

## \[GTW2\]Configurez RDS-GATEWAY2

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NetIPAddress -InterfaceAlias $carte -IPAddress 172.16.1.118 -PrefixLength 16 -DefaultGateway 172.16.1.254
Set-DnsClientServerAddress -InterfaceAlias $carte -ServerAddresses 172.16.1.1
Start-Sleep -Seconds 5
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential "AVAEDOS\Administrator", $mdp
Add-Computer -DomainName "avaedos.lan" -NewName RDS-GATEWAY2 -Credential $cred `
    -OUPath "OU=RD Servers,DC=avaedos,DC=lan" -Restart
```

**Vérification :** `(Get-CimInstance Win32_ComputerSystem).Domain` renvoie **avaedos.lan** sur les deux serveurs.

## \[DC\]Ajoutez les nouveaux serveurs au groupe RDS Servers

```powershell
Add-ADGroupMember "RDS Servers" -Members "RDS-CBROKER2$", "RDS-GATEWAY2$"
Add-DnsServerResourceRecordA -ZoneName "avaedos.lan" -Name "rds-farm" -IPv4Address 172.16.1.115
Add-DnsServerResourceRecordA -ZoneName "avaedos.lan" -Name "rds-farm" -IPv4Address 172.16.1.116
```

Les deux enregistrements **rds-farm** forment le tourniquet DNS qui répartit les clients entre les Connection Brokers.

# Haute disponibilité du Connection Broker

## \[DC\]Installez SQL Server 2025 Express

SQL Server Express suffit pour le laboratoire, où il est hébergé sur RDS-DC1 pour économiser une machine. **En production, on ne fait pas cela** : Microsoft déconseille explicitement d'installer SQL Server sur un contrôleur de domaine, et la base du Connection Broker est placée sur un SQL Server redondant ou sur Azure SQL Database.

Sur un contrôleur de domaine, les services SQL ne peuvent pas tourner sous un compte de service local : le paramètre `/SQLSVCACCOUNT` désigne donc un compte de domaine.

```powershell
Start-Process C:\AVAEDOS\_RDS\SQL\SQLEXPR_x64_ENU.exe -Wait -ArgumentList `
    '/Q /ACTION=Install /FEATURES=SQLEngine /INSTANCENAME=MSSQLSERVER /SQLSYSADMINACCOUNTS="AVAEDOS\Domain Admins" /SQLSVCACCOUNT="AVAEDOS\Administrator" /SQLSVCPASSWORD="P@ssw0rd" /TCPENABLED=1 /UPDATEENABLED=0 /IACCEPTSQLSERVERLICENSETERMS'
New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound `
    -Protocol TCP -LocalPort 1433 -Action Allow
```

**Vérification :** `Get-Service MSSQLSERVER` est à l'état **Running** ; depuis RDS-CBROKER1, `Test-NetConnection rds-dc1 -Port 1433` réussit.

## \[DC\]Autorisez le groupe RDS Servers à créer la base

Les Connection Brokers accèdent à la base avec leur compte ordinateur, membre du groupe **RDS Servers**.

```powershell
$cnx = New-Object System.Data.SqlClient.SqlConnection `
    "Server=localhost;Integrated Security=True;TrustServerCertificate=True"
$cnx.Open()
$cmd = $cnx.CreateCommand()
$cmd.CommandText = "CREATE LOGIN [AVAEDOS\RDS Servers] FROM WINDOWS; " +
                   "ALTER SERVER ROLE dbcreator ADD MEMBER [AVAEDOS\RDS Servers];"
$cmd.ExecuteNonQuery()
$cnx.Close()
```

Le rôle **dbcreator** autorise la création de la base par le premier Connection Broker. Le second devra aussi entrer **dans** la base, créée et possédée par le premier : ce droit est accordé plus loin, une fois la base existante.

## \[CB1\]\[CB2\]Installez le pilote ODBC et redémarrez

Chaque Connection Broker se connecte à SQL Server par le pilote ODBC désigné dans la chaîne de connexion. Le redémarrage prend en compte l'appartenance au groupe **RDS Servers**.

Le pilote exige le **Redistribuable Visual C++**, absent d'une installation neuve de Windows Server 2025 : sans lui, l'installation s'arrête sur l'erreur **1723** puis **1603**.

```powershell
Start-Process C:\AVAEDOS\_RDS\ODBC\vc_redist.x64.exe -Wait `
    -ArgumentList "/install", "/quiet", "/norestart"
Start-Process msiexec.exe -Wait -ArgumentList `
    "/i C:\AVAEDOS\_RDS\ODBC\msodbcsql17.msi /qn IACCEPTMSODBCSQLLICENSETERMS=YES ALLUSERS=1"
Restart-Computer
```

**Vérification :** `Get-OdbcDriver -Name "ODBC Driver 17 for SQL Server"` renvoie le pilote.

## \[CB1\]Configurez le Connection Broker en haute disponibilité

Après le redémarrage, le service **RDMS** met une à deux minutes à démarrer. Lancée trop tôt, la commande échoue sur **A deployment is not present**. Attendez que la commande suivante renvoie la liste des serveurs :

```powershell
Import-Module RemoteDesktop
Get-RDServer -ConnectionBroker rds-cbroker1.avaedos.lan
```

```powershell
Set-RDConnectionBrokerHighAvailability -ConnectionBroker rds-cbroker1.avaedos.lan `
    -DatabaseConnectionString "DRIVER=ODBC Driver 17 for SQL Server;SERVER=rds-dc1.avaedos.lan;Trusted_Connection=Yes;APP=Remote Desktop Services Connection Broker;DATABASE=RDCB-DB" `
    -ClientAccessName rds-farm.avaedos.lan
```

**Résultat attendu :** la base **RDCB-DB** est créée sur RDS-DC1.

**Vérification :**

```powershell
Get-RDConnectionBrokerHighAvailability -ConnectionBroker rds-cbroker1.avaedos.lan
```

La commande affiche **rds-farm.avaedos.lan** comme nom d'accès client.

**Un point à retenir :** **rds-farm.avaedos.lan** est un tourniquet DNS, sans compte ni SPN Kerberos. Il sert aux **connexions des utilisateurs**, jamais au paramètre `-ConnectionBroker` des commandes d'administration : celles-ci échouent alors sur *The RD Connection Broker server is not available*. L'administration continue de désigner un serveur par son nom réel, ici **rds-cbroker1.avaedos.lan**.

## \[DC\]Donnez au groupe RDS Servers l'accès à la base RDCB-DB

La base appartient au Connection Broker qui l'a créée. Sans droit à l'intérieur de la base, le second se voit refuser l'accès : **The database is not reachable from the specified RD Connection Broker server**.

```powershell
$cnx = New-Object System.Data.SqlClient.SqlConnection `
    "Server=localhost;Integrated Security=True;TrustServerCertificate=True;Database=RDCB-DB"
$cnx.Open()
$cmd = $cnx.CreateCommand()
$cmd.CommandText = "CREATE USER [AVAEDOS\RDS Servers] FOR LOGIN [AVAEDOS\RDS Servers]; " +
                   "ALTER ROLE db_owner ADD MEMBER [AVAEDOS\RDS Servers];"
$cmd.ExecuteNonQuery()
$cnx.Close()
```

**Vérification :** les membres du rôle **db_owner** de RDCB-DB sont **dbo** et **AVAEDOS\\RDS Servers**.

## \[CB2\]Autorisez l'interrogation WMI

Le déploiement lit la version du système du serveur à ajouter par **WMI**, et non par WinRM. Si le pare-feu bloque WMI, la lecture échoue et l'ajout est refusé avec un message trompeur : *has to be same OS version as the active RD Connection Broker server*, alors que les deux systèmes sont identiques.

```powershell
Enable-NetFirewallRule -DisplayGroup "Windows Management Instrumentation (WMI)"
```

**Vérification :** depuis RDS-CBROKER1, `Get-CimInstance Win32_OperatingSystem -CimSession (New-CimSession -ComputerName rds-cbroker2.avaedos.lan -SessionOption (New-CimSessionOption -Protocol Dcom))` renvoie le nom du système.

## \[CB1\]Ajoutez RDS-CBROKER2 au déploiement

Tous les serveurs du déploiement doivent être allumés : l'ajout d'un Connection Broker les interroge tous et échoue si l'un d'eux ne répond pas.

```powershell
Add-RDServer -Server rds-cbroker2.avaedos.lan -Role RDS-CONNECTION-BROKER `
    -ConnectionBroker rds-cbroker1.avaedos.lan
```

**Vérification :** `Get-RDServer -ConnectionBroker rds-cbroker1.avaedos.lan` affiche deux serveurs **RDS-CONNECTION-BROKER**.

# Ferme de passerelles et d'accès Web

## \[CB1\]Ajoutez RDS-GATEWAY2 au déploiement

RDS-GATEWAY2 reçoit les mêmes rôles que RDS-GATEWAY1 : accès Web et passerelle.

```powershell
Add-RDServer -Server rds-gateway2.avaedos.lan -Role RDS-WEB-ACCESS -ConnectionBroker rds-cbroker1.avaedos.lan
Add-RDServer -Server rds-gateway2.avaedos.lan -Role RDS-GATEWAY -ConnectionBroker rds-cbroker1.avaedos.lan `
    -GatewayExternalFqdn rds.avaedos.lan
$mdp = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
foreach ($role in "RDRedirector","RDPublishing","RDWebAccess","RDGateway") {
    Set-RDCertificate -Role $role -ImportPath C:\Certificats\rds-avaedos.pfx `
        -Password $mdp -ConnectionBroker rds-cbroker1.avaedos.lan -Force
}
```

Le certificat est réaffecté pour être déployé sur RDS-CBROKER2 et RDS-GATEWAY2. Il couvre déjà leurs noms, prévus dès l'atelier 1.

## \[GTW2\]Reproduisez les stratégies et le client web

Les stratégies CAP et RAP sont stockées sur chaque passerelle. Dans **Remote Desktop Gateway Manager** sur RDS-GATEWAY2, restreignez la CAP et la RAP au groupe **AVAEDOS\\RDS Users**, comme à l'atelier 3. En production, un serveur NPS central partage les CAP entre les passerelles.

Dans les propriétés de chaque passerelle, onglet **Server Farm**, ajoutez **rds-gateway1.avaedos.lan** et **rds-gateway2.avaedos.lan**.

Installez ensuite le client web sur RDS-GATEWAY2 avec les mêmes commandes qu'à l'atelier 3.

## \[GTW1\]\[GTW2\]Installez l'équilibrage de charge réseau

Les deux passerelles répondent à la même adresse, **172.16.1.119**, portée par un cluster NLB.

```powershell
Install-WindowsFeature NLB -IncludeManagementTools
```

Sur RDS-GATEWAY1 :

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
New-NlbCluster -InterfaceName $carte -ClusterPrimaryIP 172.16.1.119 -SubnetMask 255.255.0.0 `
    -OperationMode Multicast -ClusterName "rds.avaedos.lan"
```

Sur RDS-GATEWAY2 :

```powershell
$carte = (Get-NetAdapter | Where-Object Status -eq "Up").Name
Get-NlbCluster -HostName rds-gateway1 | Add-NlbClusterNode -NewNodeName rds-gateway2 -NewNodeInterface $carte
```

**Vérification :** `Get-NlbClusterNode -HostName rds-gateway1` affiche les deux nœuds à l'état **Converged**.

## \[DC\]Faites pointer rds.avaedos.lan vers la ferme

```powershell
Remove-DnsServerResourceRecord -ZoneName "avaedos.lan" -Name "rds" -RRType A -Force
Add-DnsServerResourceRecordA -ZoneName "avaedos.lan" -Name "rds" -IPv4Address 172.16.1.119
```

Sur RDS-CLI1, videz le cache DNS pour prendre en compte la nouvelle adresse : `ipconfig /flushdns`.

**Interprétation :** le nom utilisé par les clients ne change pas ; seule l'adresse qu'il désigne passe d'un serveur à la ferme.

# Tests de tolérance aux pannes

## \[MP\]Testez la perte d'un Connection Broker

```powershell
Stop-VM -Name RDS-CBROKER1 -Force
```

Depuis RDS-CLI1, connectez **lthobois** au bureau par le client web **https://rds.avaedos.lan/RDWeb/webclient/index.html**.

**Résultat attendu :** la connexion aboutit par RDS-CBROKER2 : le service rendu aux utilisateurs continue.

En revanche, les commandes d'administration adressées à RDS-CBROKER2 répondent : *provide an active Remote Desktop management server name*. Le rôle de **serveur de gestion** ne bascule pas de lui-même ; il se désigne explicitement :

```powershell
Set-RDActiveManagementServer -ManagementServer rds-cbroker2.avaedos.lan
```

**Interprétation :** la haute disponibilité couvre le service aux utilisateurs, pas la console d'administration. C'est une distinction à retenir en exploitation : la plateforme continue de fonctionner alors même que vous ne pouvez plus l'administrer sans cette commande.

```powershell
Start-VM -Name RDS-CBROKER1
```

## \[MP\]Testez la perte d'une passerelle

```powershell
Stop-VM -Name RDS-GATEWAY1 -Force
```

Depuis RDS-CLI1, reconnectez-vous au client web puis au bureau.

**Résultat attendu :** la connexion aboutit par RDS-GATEWAY2, après la convergence du cluster NLB.

```powershell
Start-VM -Name RDS-GATEWAY1
```

**Interprétation :** les deux Connection Brokers partagent la même base : la haute disponibilité dépend désormais de RDS-DC1, qui devient à son tour un point de défaillance à protéger en production.

# Maintenance d'un hôte de session

## \[CLI\]Ouvrez deux sessions

Connectez **lthobois** et **bnedjimi** depuis RDS-CLI1 au bureau **RdsSesColl1**, par deux connexions distinctes (par exemple le client web pour l'un, `mstsc` pour l'autre).

## \[CB1\]Drainez RDS-SESSION1 et prévenez ses utilisateurs

```powershell
Set-RDSessionHost -SessionHost rds-session1.avaedos.lan -NewConnectionAllowed No `
    -ConnectionBroker rds-cbroker1.avaedos.lan
msg * /server:RDS-SESSION1 "Maintenance de RDS-SESSION1 : enregistrez votre travail et fermez votre session."
Get-RDUserSession -ConnectionBroker rds-cbroker1.avaedos.lan |
    Select-Object UserName, HostServer, SessionState
```

**Résultat attendu :** les sessions existantes restent ouvertes et reçoivent le message ; toute nouvelle connexion est dirigée vers RDS-SESSION2.

**Vérification :** fermez la session de l'utilisateur hébergé sur RDS-SESSION1, reconnectez-le, puis relancez `Get-RDUserSession` : il est désormais sur RDS-SESSION2.

## \[CB1\]Remettez RDS-SESSION1 en service

```powershell
Set-RDSessionHost -SessionHost rds-session1.avaedos.lan -NewConnectionAllowed Yes `
    -ConnectionBroker rds-cbroker1.avaedos.lan
```

# Supervision et diagnostic

## \[SES1\]Mesurez le délai d'entrée utilisateur

Pendant qu'une session est ouverte sur RDS-SESSION1 :

```powershell
Get-Counter "\User Input Delay per Session(*)\Max Input Delay" -SampleInterval 2 -MaxSamples 5
```

**Interprétation :** la valeur mesure le temps de traitement des actions clavier et souris dans chaque session. Des valeurs durablement élevées traduisent une saturation de l'hôte, ressentie comme une lenteur par l'utilisateur.

## \[CB1\]Diagnostiquez la panne injectée par le formateur

Le formateur provoque une panne sur votre plateforme. Appliquez la méthode vue en cours :

1. Reproduisez l'incident : qui, depuis quel poste, vers quelle ressource.
2. Suivez le parcours de connexion : DNS, passerelle, Connection Broker, hôte de session, licence, profil.
3. Lisez le journal de l'étape qui échoue.
4. Corrigez, puis vérifiez avec l'utilisateur.

Journaux utiles :

```powershell
$journaux = "Microsoft-Windows-TerminalServices-Gateway/Operational",
            "Microsoft-Windows-TerminalServices-SessionBroker/Operational",
            "Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational",
            "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational"
foreach ($j in $journaux) {
    Get-WinEvent -LogName $j -MaxEvents 10 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName, Message
}
```

Chaque journal n'existe que sur les serveurs qui portent le rôle correspondant : exécutez la commande sur le serveur concerné.

**Livrable :** notez l'étape en défaut, le message du journal, la cause et la correction appliquée.

# Ce qu'il faut retenir

La haute disponibilité du Connection Broker déplace le risque vers SQL Server et exige des certificats couvrant le nom de ferme. Les passerelles et l'accès Web se redondent derrière un même nom. Le mode drainage permet de maintenir les hôtes sans couper les utilisateurs, à condition d'avoir dimensionné la ferme pour la perte d'un hôte.

# Erreurs fréquentes

| Symptôme | Cause probable | Correction |
|---|---|---|
| `Set-RDConnectionBrokerHighAvailability` échoue | Pilote ODBC absent ou version différente de la chaîne | Installer le pilote cité dans la chaîne sur chaque Connection Broker |
| L'installation du pilote ODBC s'arrête sur **1723** puis **1603** | Redistribuable Visual C++ absent | Installer `vc_redist.x64.exe` avant le pilote |
| **A deployment is not present** | Service **RDMS** pas encore démarré après le redémarrage | Attendre que `Get-RDServer` réponde, puis relancer |
| **Could not create the database RDCB-DB** | Le Connection Broker n'a pas redémarré depuis son ajout au groupe **RDS Servers** | Redémarrer le Connection Broker pour rafraîchir son jeton Kerberos |
| **has to be same OS version** alors que les deux serveurs sont identiques | Lecture WMI bloquée par le pare-feu du serveur à ajouter | Activer le groupe de règles **Windows Management Instrumentation (WMI)** |
| **The database is not reachable** sur le second Connection Broker | Le groupe **RDS Servers** n'a pas de droit dans la base RDCB-DB | L'ajouter au rôle **db_owner** de la base |
| **deployment servers were not reachable** | Un serveur du déploiement est éteint | Allumer tous les serveurs avant d'ajouter un Connection Broker |
| **The server pool does not match the RD Connection Brokers that are in it** dans Server Manager, les **deux** brokers listés | Le serveur qui héberge la base **RDCB-DB** est injoignable : sans base, le service **tssdis** ne démarre sur aucun des deux | Vérifier `Test-NetConnection <serveur SQL> -Port 1433` depuis un broker, puis `Get-Service tssdis` ; rallumer le serveur de base avant tout le reste |
| Même message, mais un seul broker listé | Services **rdms**, **tssdis** ou **tscpubrpc** pas encore démarrés après le redémarrage | Attendre une à deux minutes ; si le serveur de gestion actif est indisponible, `Set-RDActiveManagementServer` désigne l'autre |
| Échec de connexion à RDS-DC1 | Groupe non pris en compte ou port fermé | Redémarrer les Connection Brokers, vérifier la règle de pare-feu 1433 |
| Erreur de certificat après l'ajout d'un serveur | Certificat non redéployé | Relancer `Set-RDCertificate` pour les quatre rôles |
| Refus sur une seule des deux passerelles | CAP et RAP non reproduites sur RDS-GATEWAY2 | Aligner les stratégies ou utiliser un NPS central |
| Nouvelles sessions toujours sur l'hôte drainé | Reconnexion à une session existante | Normal : seules les nouvelles sessions sont refusées |
