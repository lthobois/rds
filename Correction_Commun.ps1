## Correction des ateliers RDS - environnement commun
## Charge par chaque script de correction : . "$PSScriptRoot\Correction_Commun.ps1"

#region Configuration

# Les installateurs des ateliers - FSLogix, ODBC, SQL, client web - sont deja presents
# dans C:\AVAEDOS\_RDS sur chaque machine : aucun chemin de sources n'est necessaire ici.
# Seule l'image Windows11FR.vhdx vient de la machine physique : W11-GOLD s'en construit a l'atelier 5.

$password = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force

$username = "Administrator"
$CredLocal = New-Object System.Management.Automation.PSCredential $username, $password

$username = "AVAEDOS\Administrator"
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

# Deploy-VMTemplate n'accepte que Default Switch, WIRED Network ou Prod_vSwitch : les machines
# restent donc sur Default Switch, qui fournit en plus un acces Internet par NAT (client web).
# Pour un reseau isole, raccorder les cartes a Reseau Salle apres le deploiement :
#   Get-VM RDS-* | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName "Reseau Salle" 

$Broker = "rds-cbroker1.avaedos.lan"

#endregion

#region Configuration Hyper-V

Set-VMHost -EnableEnhancedSessionMode $true -NumaSpanningEnabled $true

#endregion
