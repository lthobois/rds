## Correction - Atelier 2 : FSLogix et strategies de groupe
## Prerequis : le module precedent a ete joue.

. "$PSScriptRoot\Correction_Commun.ps1"

#region Atelier 2

Write-Host "Autorisations du dossier ProfilDisk" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    icacls "C:\ProfilDisk" /inheritance:r /grant "SYSTEM:(OI)(CI)F" "AVAEDOS\Domain Admins:(OI)(CI)F" "CREATOR OWNER:(OI)(CI)(IO)M" "AVAEDOS\RDS Users:(M)"
}

Write-Host "Installation et configuration de FSLogix" -ForegroundColor Cyan
$SessionHosts = "RDS-SESSION1","RDS-SESSION2","RDS-SESSION3","RDS-SESSION4"
Invoke-Command -VMName $SessionHosts -Credential $CredDomain -ScriptBlock {
    Start-Process "C:\AVAEDOS\_RDS\FSLogix\FSLogixAppsSetup.exe" -ArgumentList "/install /quiet /norestart" -Wait
    $Key = "HKLM:\SOFTWARE\FSLogix\Profiles"
    New-Item -Path $Key -Force | Out-Null
    New-ItemProperty -Path $Key -Name Enabled -Value 1 -PropertyType DWord -Force
    New-ItemProperty -Path $Key -Name VHDLocations -Value "\\RDS-DC1\ProfilDisk" -PropertyType MultiString -Force
    New-ItemProperty -Path $Key -Name VolumeType -Value "VHDX" -PropertyType String -Force
    New-ItemProperty -Path $Key -Name DeleteLocalProfileWhenVHDShouldApply -Value 1 -PropertyType DWord -Force
    New-ItemProperty -Path $Key -Name FlipFlopProfileDirectoryName -Value 1 -PropertyType DWord -Force
    Add-LocalGroupMember -Group "FSLogix Profile Exclude List" -Member "AVAEDOS\Domain Admins"
}
foreach ($VMName in $SessionHosts) { Reboot-VMComputer -VMName $VMName }

Write-Host "Stratégie GPO RD Sessions" -ForegroundColor Cyan
Invoke-Command -VMName "RDS-DC1" -Credential $CredDomain -ScriptBlock {
    New-GPO -Name "GPO RD Sessions" | New-GPLink -Target "OU=RD Servers,DC=avaedos,DC=lan"
    $Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
    $Values = @{ MaxDisconnectionTime = 3600000; MaxIdleTime = 7200000; fSingleSessionPerUser = 1; fDisableCdm = 1; fForceClientLptDef = 1; Shadow = 1 }
    foreach ($Name in $Values.Keys) {
        Set-GPRegistryValue -Name "GPO RD Sessions" -Key $Key -ValueName $Name -Type DWord -Value $Values[$Name]
    }
}
Invoke-Command -VMName $SessionHosts -Credential $CredDomain -ScriptBlock { gpupdate /force }

#endregion
