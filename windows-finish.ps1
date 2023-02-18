# PowerShell script to finish out windows install
#
# PowerShell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/jlim0930/scripts/master/windows-finish.ps1'))"
#


$VerbosePreference = "Continue"

function Install-ScoopApp {
    param (
        [string]$Package
    )
    Write-Verbose -Message "Preparing to install $Package"
    if (! (scoop info $Package).Installed ) {
        Write-Verbose -Message "Installing $Package"
        scoop install $Package
    } else {
        Write-Verbose -Message "Package $Package already installed! Skipping..."
    }
}

function Install-WinGetApp {
    param (
        [string]$PackageID
    )
    Write-Verbose -Message "Preparing to install $PackageID"
    # Added accept options based on this issue - https://github.com/microsoft/winget-cli/issues/1559
    #$listApp = winget list --exact -q $PackageID --accept-source-agreements
    #if (winget list --exact --id "$PackageID" --accept-source-agreements) {
    #    Write-Verbose -Message "Package $PackageID already installed! Skipping..."
    #} else {
    #    Write-Verbose -Message "Installing $Package"
    #    winget install --silent --id "$PackageID" --accept-source-agreements --accept-package-agreements
    #}
    Write-Verbose -Message "Installing $Package"
    winget install --silent --id "$PackageID" --accept-source-agreements --accept-package-agreements
}

function Extract-Download {
    param (
        [string]$Folder,
        [string]$File
    )
    if (!(Test-Path -Path "$Folder" -PathType Container)) {
        Write-Error "$Folder does not exist!!!"
        Break
    }
    if (Test-Path -Path "$File" -PathType Leaf) {
        switch ($File.Split(".") | Select-Object -Last 1) {
            "rar" { Start-Process -FilePath "UnRar.exe" -ArgumentList "x","-op'$Folder'","-y","$File" -WorkingDirectory "$Env:ProgramFiles\WinRAR\" -Wait | Out-Null }
            "zip" { 7z x -o"$Folder" -y "$File" | Out-Null }
            "7z" { 7z x -o"$Folder" -y "$File" | Out-Null }
            "exe" { 7z x -o"$Folder" -y "$File" | Out-Null }
            Default { Write-Error "No way to Extract $File !!!"; Break }
        }
    }
}

function Download-CustomApp {
    param (
        [string]$Link,
        [string]$Folder
    )
    if ((curl -sIL "$Link" | Select-String -Pattern "Content-Disposition") -ne $Null) {
        $Package = $(curl -sIL "$Link" | Select-String -Pattern "filename=" | Split-String -Separator "=" | Select-Object -Last 1).Trim('"')
    } else {
        $Package = $Link.split("/") | Select-Object -Last 1
    }
    Write-Verbose -Message "Preparing to download $Package"
    aria2c --quiet --dir="$Folder" "$Link"
    Return $Package
}

function Install-CustomApp {
    param (
        [string]$URL,
        [string]$Folder
    )
    $Package = Download-CustomApp -Link $URL -Folder "$Env:UserProfile\Downloads\"
    if (Test-Path -Path "$Env:UserProfile\Downloads\$Package" -PathType Leaf) {
        if (Test-Path Variable:Folder) {
            if (!(Test-Path -Path "$Env:UserProfile\bin\$Folder")) {
                New-Item -Path "$Env:UserProfile\bin\$Folder" -ItemType Directory | Out-Null
            }
            Extract-Download -Folder "$Env:UserProfile\bin\$Folder" -File "$Env:UserProfile\Downloads\$Package"
        } else {
            Extract-Download -Folder "$Env:UserProfile\bin\" -File "$Env:UserProfile\Downloads\$Package"
        }
        Remove-Item -Path "$Env:UserProfile\Downloads\$Package"
    }
}

function Install-CustomPackage {
    param (
        [string]$URL
    )
    $Package = Download-CustomApp -Link $URL
    if (Test-Path -Path "$Env:UserProfile\Downloads\$Package" -PathType Leaf) {
        Start-Process -FilePath ".\$Package" -ArgumentList "/S" -WorkingDirectory "${Env:UserProfile}\Downloads\" -Verb RunAs -Wait #-WindowStyle Hidden
        Remove-Item -Path "$Env:UserProfile\Downloads\$Package"
    }
}

function Remove-InstalledApp {
    param (
        [string]$Package
    )
    Write-Verbose -Message "Uninstalling: $Package"
    Start-Process -FilePath "PowerShell" -ArgumentList "Get-AppxPackage","-AllUsers","-Name","'$Package'" -Verb RunAs -WindowStyle Hidden
}

function Enable-Bucket {
    param (
        [string]$Bucket
    )
    if (!($(scoop bucket list).Name -eq "$Bucket")) {
        Write-Verbose -Message "Adding Bucket $Bucket to scoop..."
        scoop bucket add $Bucket
    } else {
        Write-Verbose -Message "Bucket $Bucket already added! Skipping..."
    }
}


###############################

# Configure ExecutionPolicy to Unrestricted for CurrentUser Scope
if ((Get-ExecutionPolicy -Scope CurrentUser) -notcontains "Unrestricted") {
    Write-Verbose -Message "Setting Execution Policy for Current User..."
    Start-Process -FilePath "PowerShell" -ArgumentList "Set-ExecutionPolicy","-Scope","CurrentUser","-ExecutionPolicy","Unrestricted","-Force" -Verb RunAs -Wait
    Write-Output "Restart/Re-Run script!!!"
    Start-Sleep -Seconds 10
    Break
}

# Install Scoop, if not already installed
#$scoopInstalled = Get-Command "scoop"
if ( !(Get-Command -Name "scoop" -CommandType Application -ErrorAction SilentlyContinue | Out-Null) ) {
    Write-Verbose -Message "Installing Scoop..."
    iex ((New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh'))
}

# Install WinGet, if not already installed
# From crutkas's gist - https://gist.github.com/crutkas/6c2096eae387e544bd05cde246f23901
#$hasPackageManager = Get-AppPackage -name "Microsoft.DesktopAppInstaller"
if (!(Get-AppPackage -name "Microsoft.DesktopAppInstaller")) {
    Write-Verbose -Message "Installing WinGet..."
@'
# Set URL and Enable TLSv12
$releases_url = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Dont Think We Need This!!!
#Install-PackageProvider -Name NuGet
# Install Nuget as Package Source Provider
Register-PackageSource -Name Nuget -Location "http://www.nuget.org/api/v2" -ProviderName Nuget -Trusted
# Install Microsoft.UI.Xaml (This is not currently working!!!)
Install-Package Microsoft.UI.Xaml -RequiredVersion 2.7.1
# Grab "Latest" release
$releases = Invoke-RestMethod -uri $releases_url
$latestRelease = $releases.assets | Where { $_.browser_download_url.EndsWith('msixbundle') } | Select -First 1
# Install Microsoft.DesktopAppInstaller Package
Add-AppxPackage -Path $latestRelease.browser_download_url
'@ > $Env:Temp\winget.ps1
    Start-Process -FilePath "PowerShell" -ArgumentList "$Env:Temp\winget.ps1" -Verb RunAs -Wait
    Remove-Item -Path $Env:Temp\winget.ps1 -Force
}

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
Install-WinGetApp -PackageID "Git.Git"
Start-Sleep -Seconds 5
refreshenv
Start-Sleep -Seconds 5
if (!$(git config --global credential.helper) -eq "manager-core") {
    git config --global credential.helper manager-core
}
if (!($Env:GIT_SSH)) {
    Write-Verbose -Message "Setting GIT_SSH User Environment Variable"
    [System.Environment]::SetEnvironmentVariable('GIT_SSH', (Resolve-Path (scoop which ssh)), 'USER')
}
if ((Get-Service -Name ssh-agent).Status -ne "Running") {
    Start-Process -FilePath "PowerShell" -ArgumentList "Set-Service","ssh-agent","-StartupType","Manual" -Verb RunAs -Wait -WindowStyle Hidden
}

# Add Buckets
Enable-Bucket -Bucket "extras"
Enable-Bucket -Bucket "java"
Enable-Bucket -Bucket "nirsoft"
Enable-Bucket -Bucket "nonportable"
Enable-Bucket -Bucket "nerd-fonts"

# Set Timezone
Set-TimeZone -Name "Central Standard Time"

# Add Language
Install-Language ko-KR -AsJob

# Change User variables
[Environment]::SetEnvironmentVariable("TEMP", "C:\temptemp", "User")
[Environment]::SetEnvironmentVariable("TMP", "C:\temptemp", "User")

# Change System variables
[Environment]::SetEnvironmentVariable("TMP", "C:\temptemp", "Machine")
[Environment]::SetEnvironmentVariable("TEMP", "C:\temptemp", "Machine")

# Install Scoop Packages
$Scoop = @(
    "scoop-tray",
    "curl",
    "sudo",
    "putty",
    "rufus",
    "brave",
    "firefox",
    "mobaxterm",
    "totalcommander",
    "bitwarden",
    "sharex",
    "k-lite-codec-pack-standard-np",
    "winrar",
    "vlc",
    "revouninstaller",
    "fixit-pdf-reader",
    "unlocker",
    "winaero-tweaker",
    "Noto-CJK-Mega-OTC",
    "ffmpeg",
    "musicbee",
    "mp3tag",
    "spotify",
    "clink",
    "powertoys",
    "vscode",
    "notepadplusplus",
    "sysinternals")
foreach ($item in $Scoop) {
    Install-ScoopApp -Package "$item"
}

# Fix for vscode and notepad++
reg import "C:\Users\$env:USERNAME\scoop\apps\vscode\current\install-associations.reg"
reg import "C:\Users\$env:USERNAME\scoop\apps\notepadplusplus\current\install-context.reg"


# Install winget Packages
$WinGet = @(
    #"Microsoft.dotNetFramework",
    "Microsoft.DotNet.DesktopRuntime.3_1",
    "Microsoft.DotNet.DesktopRuntime.5",
    "Microsoft.DotNet.DesktopRuntime.6",
    "Microsoft.DotNet.DesktopRuntime.7",
    "Google.Chrome",
    "AOMEI.PartitionAssistant"
    )
foreach ($item in $WinGet) {
    Install-WinGetApp -PackageID "$item"
}

# Install Windows SubSystems for Linux
$wslInstalled = Get-Command "wsl" -CommandType Application -ErrorAction Ignore
if (!$wslInstalled) {
    Write-Verbose -Message "Installing Windows SubSystems for Linux..."
    Start-Process -FilePath "PowerShell" -ArgumentList "wsl","--install" -Verb RunAs -Wait -WindowStyle Hidden
}

scoop bucket add wsl https://github.com/KNOXDEV/wsl


# Done
Write-Output "Install complete! Please reboot your machine/worksation!"
Start-Sleep -Seconds 10
