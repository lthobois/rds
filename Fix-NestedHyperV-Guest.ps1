#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "=== Correction Nested Hyper-V : VM ==="

$DG  = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
$CG  = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard"
$POL = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"
$LSA = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"

# Création des clés si nécessaire
New-Item $DG  -Force | Out-Null
New-Item $CG  -Force | Out-Null
New-Item $POL -Force | Out-Null
New-Item $LSA -Force | Out-Null

Write-Host "Desactivation VBS..."

New-ItemProperty `
    -Path $DG `
    -Name EnableVirtualizationBasedSecurity `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

New-ItemProperty `
    -Path $DG `
    -Name RequirePlatformSecurityFeatures `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

Write-Host "Desactivation Credential Guard..."

New-ItemProperty `
    -Path $CG `
    -Name Enabled `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

New-ItemProperty `
    -Path $POL `
    -Name EnableVirtualizationBasedSecurity `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

New-ItemProperty `
    -Path $POL `
    -Name LsaCfgFlags `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

New-ItemProperty `
    -Path $LSA `
    -Name LsaCfgFlags `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

Write-Host ""
Write-Host "=== CONFIGURATION APPLIQUEE ==="

Get-ItemProperty $DG |
    Select-Object EnableVirtualizationBasedSecurity,
                  RequirePlatformSecurityFeatures

Get-ItemProperty $CG |
    Select-Object Enabled

Get-ItemProperty $POL |
    Select-Object EnableVirtualizationBasedSecurity,
                  LsaCfgFlags

Write-Host ""
Write-Host "================================================="
Write-Host " ETAPE SUIVANTE"
Write-Host "================================================="
Write-Host ""
Write-Host "La VM doit maintenant etre COMPLETEMENT arretee."
Write-Host ""
Write-Host "Apres redemarrage, verifie avec :"
Write-Host ""
Write-Host "  VirtualizationFirmwareEnabled           = True"
Write-Host "  SecondLevelAddressTranslationExtensions = True"
Write-Host "  VMMonitorModeExtensions                 = True"
Write-Host "  VirtualizationBasedSecurityStatus       = 0"
Write-Host ""
Write-Host "Puis installe Hyper-V avec :"
Write-Host ""
Write-Host "  Install-WindowsFeature Hyper-V -IncludeManagementTools -Restart"
Write-Host ""
Write-Host "Arret de la VM dans 10 secondes..."
Start-Sleep -Seconds 10

Stop-Computer