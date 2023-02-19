# PowerShell script to finish out windows install
#
# PowerShell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/jlim0930/scripts/master/windows-finish.ps1'))"
#


# Configure ExecutionPolicy to Unrestricted for CurrentUser Scope
if ((Get-ExecutionPolicy -Scope CurrentUser) -notcontains "Unrestricted") {
    Write-Verbose -Message "Setting Execution Policy for Current User..."
    Start-Process -FilePath "PowerShell" -ArgumentList "Set-ExecutionPolicy","-Scope","CurrentUser","-ExecutionPolicy","Unrestricted","-Force" -Verb RunAs -Wait
    Write-Output "Restart/Re-Run script!!!"
    Start-Sleep -Seconds 10
    Break
}

# install scoop
irm get.scoop.sh | iex
scoop install sudo
sudo scoop 7zip -g

# install winget
Add-AppxPackage -Path 'https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'

# Only install OpenSSH Package, if not on Windows 10
if ([Environment]::OSVersion.Version.Major -lt 10) {
    Install-ScoopApp -Package "openssh"
}

# Install OpenSSH.Client on Windows 10+
@'
if ((Get-WindowsCapability -Online -Name OpenSSH.Client*).State -ne "Installed") {
    Add-WindowsCapability -Online -Name OpenSSH.Client*
}
'@ > "${Env:Temp}\openssh.ps1"
Start-Process -FilePath "PowerShell" -ArgumentList "${Env:Temp}\openssh.ps1" -Verb RunAs -Wait -WindowStyle Hidden
Remove-Item -Path "${Env:Temp}\openssh.ps1" -Force

# Configure git
scoop install git
reg import "C:\Users\$env:USERNAME\scoop\apps\7zip\current\install-context.reg"

# Set Timezone
Set-TimeZone -Name "Central Standard Time"

# Add Language
Install-Language ko-KR -AsJob

# Change User variables
[Environment]::SetEnvironmentVariable("TEMP", "C:\temptemp", "User")
[Environment]::SetEnvironmentVariable("TMP", "C:\temptemp", "User")

# Change System variables
sudo [Environment]::SetEnvironmentVariable("TMP", "C:\temptemp", "Machine")
sudo [Environment]::SetEnvironmentVariable("TEMP", "C:\temptemp", "Machine")

# scoop stuff
scoop install curl grep sed less touch

# Add Buckets
scoop bucket add extras
scoop bucket add nonportable
scoop bucket add java
scoop bucket add nerd-fonts
scoop bucket add nirsoft

# scoop packages
scoop install firefox
scoop install brave
scoop install mobaxterm
scoop install putty
scoop install totalcommander
scoop install bitwarden
scoop install sharex
scoop install vscode
reg import "C:\Users\$env:USERNAME\scoop\apps\vscode\current\install-associations.reg"
scoop install notepadplusplus
reg import "C:\Users\$env:USERNAME\scoop\apps\notepadplusplus\current\install-context.reg"
scoop install k-lite-codec-pack-standard-np
scoop install winrar
scoop install vlc
scoop install revo
scoop install revouninstaller
scoop install spotify
scoop install foxit-pdf-reader
scoop install unlocker
scoop install winaero-tweaker
scoop install powertoys
scoop install Noto-CJK-Mega-OTC
scoop isntall clink
scoop install sysinternals

# winget packages
winget install --id="AOMEI.PartitionAssistant"  -e
winget install --id="Microsoft.DotNet.DesktopRuntime.3_1" -e
winget install --id="Microsoft.DotNet.DesktopRuntime.5" -e
winget install --id="Microsoft.DotNet.DesktopRuntime.6" -e
winget install --id="Microsoft.DotNet.DesktopRuntime.7" -e
winget install --id="Google.Chrome" -e

# wsl
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
scoop bucket add wsl https://github.com/KNOXDEV/wsl


# Done
Write-Output "Install complete! Please reboot your machine/worksation!"
Start-Sleep -Seconds 10
