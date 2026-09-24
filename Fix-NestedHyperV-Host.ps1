#Requires -RunAsAdministrator

param(
    [string]$VMName = "RDS-HYPERV1",
    [int]$ProcessorCount = 4
)

$ErrorActionPreference = "Stop"

Write-Host "=== Correction Nested Hyper-V : HOTE ==="

# Vérification Hyper-V
$HyperV = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All

if ($HyperV.State -ne "Enabled") {
    Write-Host "Activation de Hyper-V sur l'hote..."
    Enable-WindowsOptionalFeature `
        -Online `
        -FeatureName Microsoft-Hyper-V-All `
        -All `
        -NoRestart
}

# Vérification de la VM
$VM = Get-VM -Name $VMName -ErrorAction Stop

# La modification du processeur nécessite une VM arrêtée
if ($VM.State -ne "Off") {
    Write-Host "Arret de la VM $VMName..."
    Stop-VM -Name $VMName -Force

    do {
        Start-Sleep -Seconds 2
        $VM = Get-VM -Name $VMName
    }
    until ($VM.State -eq "Off")
}

Write-Host "Configuration du processeur virtuel..."

Set-VMProcessor `
    -VMName $VMName `
    -Count $ProcessorCount `
    -ExposeVirtualizationExtensions $true `
    -CompatibilityForMigrationEnabled $false

# Mémoire dynamique désactivée
Write-Host "Desactivation de la memoire dynamique..."

Set-VMMemory `
    -VMName $VMName `
    -DynamicMemoryEnabled $false

# MAC Spoofing utile pour certaines configurations réseau L2/L3 imbriquées
Write-Host "Activation MAC Address Spoofing..."

Get-VMNetworkAdapter -VMName $VMName |
    Set-VMNetworkAdapter -MacAddressSpoofing On

# Vérification
Write-Host ""
Write-Host "=== VERIFICATION ==="

Get-VM -Name $VMName |
    Format-List Name,State,Generation,Version,ProcessorCount,DynamicMemoryEnabled

Get-VMProcessor -VMName $VMName |
    Format-List Count,
                ExposeVirtualizationExtensions,
                CompatibilityForMigrationEnabled

Get-VMMemory -VMName $VMName |
    Format-List DynamicMemoryEnabled,Startup

Get-VMNetworkAdapter -VMName $VMName |
    Format-List Name,SwitchName,MacAddressSpoofing

Write-Host ""
Write-Host "=== Demarrage de $VMName ==="

Start-VM -Name $VMName

Write-Host ""
Write-Host "Correction HOTE terminee."
Write-Host "Passe maintenant au script de correction dans la VM."