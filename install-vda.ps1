<#
.SYNOPSIS
    Installs Citrix Virtual Delivery Agent (VDA) and optionally Workspace Environment Management (WEM) on a remote server.

.DESCRIPTION
    This script automates the installation of Citrix VDA and optionally WEM on a remote Windows server.
    It handles various scenarios including Windows Server 2012 compatibility,
    and multiple installation attempts if necessary.

.PARAMETER ServerName
    The name of the remote server where VDA/WEM will be installed.

.PARAMETER SoftwareShareRoot
    The root path of the network share containing the installation files.

.PARAMETER CloudConnectors
    A space separated list of Cloud Connectors to be used for VDA installation.

.PARAMETER InstallWEM
    Switch to indicate if WEM should be installed after VDA installation.

.EXAMPLE
    .\Install-CitrixVDA.ps1 -ServerName "SERVER01" -SoftwareShareRoot "\\SHARE\CitrixInstall" -CloudConnectors "CC01 CC02"

    This example installs VDA on SERVER01 using the specified software share and Cloud Connectors.

.EXAMPLE
    .\Install-CitrixVDA.ps1 -ServerName "SERVER02" -SoftwareShareRoot "\\SHARE\CitrixInstall" -CloudConnectors "CC01 CC02" -InstallWEM

    This example installs both VDA and WEM on SERVER02.

.NOTES
    File Name      : Install-VDA.ps1
    Author         : Derrick Foos (derrickfoos@hotmail.com)
    Prerequisite   : PowerShell 5.0 or later
    Creation Date  : 2023-08-26
    Version        : 1.0
    Change History :
        v1.0 - Initial script creation

.LINK
    https://github.com/dfoos/install-vda

#>

# Script parameters
param (
    [Parameter(Mandatory=$true, HelpMessage="Name of the remote server to install VDA/WEM on")]
    [string]$ServerName,

    [Parameter(Mandatory=$true, HelpMessage="Root path of the software share on the network")]
    [string]$SoftwareShareRoot,

    [Parameter(Mandatory=$true, HelpMessage="List of Cloud Connectors to use for VDA installation")]
    [string]$CloudConnectors,

    [Parameter(HelpMessage="Install WEM after VDA installation")]
    [switch]$InstallWEM = $false
)

# Define paths for VDA and WEM installers
$server2012Vda = "$SoftwareShareRoot\VDAServerSetup\VDAServerSetup_1912.exe"
$serverVda = "$SoftwareShareRoot\VDAServerSetup\VDAServerSetup_2203.exe"

$server2012Wem = "$SoftwareShareRoot\WorkspaceEnvironemntManagement\Citrix Workspace Environment Management Agent 2112.exe"
$serverWem = "$SoftwareShareRoot\WorkspaceEnvironemntManagement\Citrix Workspace Environment Management Agent.exe"

# Define installation arguments
$vdaArgs = "/controllers `"$CloudConnectors`" /quiet /noreboot /noresume /disableexperiencemetrics /virtualmachine /optimize /enable_hdx_ports /enable_hdx_udp_ports /components `"vda`" /includeadditional `"Citrix VDA Upgrade Agent`",`"Citrix Supportability Tools`",`"Citrix User Profile Manager`",`"Citrix User Profile Manager WMI Plugin`"' /exclude `"Citrix Telemetry Service','User personalization layer','AppDisks VDA Plug-in','Citrix Files for Outlook','Citrix Files for Windows','Citrix Personalization for App-V - VDA`",`"Machine Identity Service`",`"Personal vDisk`""
$wemCloudConnectors = $CloudConnectors -replace " ", ","

$wemArgs = "/quiet Cloud=1 CloudConnectorList=$wemCloudConnectors"
$softwareFolder = "C$\software\vda_install"

$Global:RemoteFolderPath = "\\$ServerName\$softwareFolder"

# Function to write log messages
function Write-Log {
    param (
        [string]$Message,
        [string]$LogFilePath = "$Global:RemoteFolderPath\vda_installer.log"
    )

    $logDirectory = [System.IO.Path]::GetDirectoryName($LogFilePath)
    if (-not (Test-Path $logDirectory)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logMessage = "$timestamp - $Message"
    $logMessage | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    Write-Host $logMessage
}

# Function to handle errors
function Handle-Error {
    param (
        [string]$ErrorMessage,
        [string]$ExitMessage = "Press Enter to exit..."
    )

    Write-Host "Error: $ErrorMessage" -ForegroundColor Red
    Read-Host $ExitMessage
    exit
}

# Function to handle successful completion
function Handle-Completed {
    param (
        [string]$CompletedMessage,
        [string]$ExitMessage = "Press Enter to exit..."
    )

    Write-Log $CompletedMessage
    Read-Host $ExitMessage
    exit
}

# Function to ensure remote folder exists
function Ensure-RemoteFolder {
    try {
        $folderPath = $Global:RemoteFolderPath

        if (-not (Test-Path -Path $Global:RemoteFolderPath)) {
            New-Item -Path $Global:RemoteFolderPath -ItemType Directory -Force
            Write-Log "Folder created at $Global:RemoteFolderPath"
        } 
        else {
            Write-Log "Folder already exists at $Global:RemoteFolderPath"
        }
    }
    catch {
        Handle-Error "An error occurred: $_"
    }
}

# Function to test UNC path accessibility
function Test-RemoteUNC {
    param (
        [string]$RemoteServerName
    )

    try {
        if (Test-Path -Path "\\$RemoteServerName\c$") {
            return $true
        } 
        else {
            return $false
        }
    }
    catch {
        Handle-Error "An error occurred while testing the UNC path: $_"
        return $false
    }
}

# Function to test WinRM connectivity
function Test-RemoteWinRM {
    param (
        [string]$RemoteServerName
    )

    try {
        $result = Test-WSMan -ComputerName $RemoteServerName -ErrorAction Stop

        if ($result) {
            return $true
        }
    }
    catch {
        return $false
    }
}

# Function to test remote server version
function Test-RemoteServerVersion {
    param (
        [string]$RemoteServerName
    )

    try {
        $scriptBlock = {
            $os = Get-WmiObject -Class Win32_OperatingSystem
            return $os.Version
        }

        $osVersion = Invoke-Command -ComputerName $RemoteServerName -ScriptBlock $scriptBlock -ErrorAction Stop

        $windowsServer2012Version = "6.2.9200"

        if ($osVersion -eq $windowsServer2012Version) {
            Write-Log "$RemoteServerName is running Windows Server 2012."
            return $true
        } 
        else {
            Write-Log "$RemoteServerName is not running Windows Server 2012. Version detected: $osVersion"
            return $false
        }
    }
    catch {
        Handle-Error "An error occurred: $_"
    }
}

# Function to test remote server reboot
function Test-RemoteReboot {
    param (
        [string]$RemoteServerName
    )

    $timeout = 300
    $startTime = Get-Date

    try {
        Restart-Computer -ComputerName $RemoteServerName -Force -Wait
    } 
    catch {
        Handle-Error "Failed to restart the computer: $_"
        return $false
    }

    # Helper function to test connection with timeout
    function Test-ConnectionWithTimeout {
        param (
            [string]$ServerName,
            [int]$Timeout
        )

        $elapsedTime = 0
        while (-not (Test-Connection -ComputerName $ServerName -Count 1 -Quiet)) {
            Start-Sleep -Seconds 10
            $elapsedTime = (Get-Date) - $startTime
            if ($elapsedTime.TotalSeconds -ge $Timeout) {
                return $false
            }
        }
        return $true
    }

    if (-not (Test-ConnectionWithTimeout -ServerName $RemoteServerName -Timeout $timeout)) {
        Handle-Error "Computer did not shut down in time."
        return $false
    }

    $startTime = Get-Date
    if (-not (Test-ConnectionWithTimeout -ServerName $RemoteServerName -Timeout $timeout)) {
        Handle-Error "Computer did not come back online in time."
        return $false
    }

    $elapsedTime = (Get-Date) - $startTime
    while ($elapsedTime.TotalSeconds -lt $timeout) {
        try {
            Test-WsMan -ComputerName $RemoteServerName -ErrorAction Stop | Out-Null
            Write-Log "WinRM is available."
            return $true
        } 
        catch {
            Start-Sleep -Seconds 10
            $elapsedTime = (Get-Date) - $startTime
        }
    }

    Handle-Error "WinRM did not become available in time."
    return $false
}

# Function to install VDA
function Install-VDA {
    param (
        [string]$RemoteServerName,
        [string]$VDAInstallerPath,
        [string]$VDAArgs = $null
    )

    if ($VDAArgs) {
        Write-Log "Starting VDA installation at $VDAInstallerPath on $RemoteServerName with arguments: $VDAArgs"
    } 
    else {
        Write-Log "Continuing VDA installation at $VDAInstallerPath on $RemoteServerName"
    }
    
    $command = {
        if ($Using:VDAArgs) {
            $process = Start-Process -FilePath $Using:VDAInstallerPath -ArgumentList $Using:VDAArgs -Wait -PassThru
        } 
        else {
            $process = Start-Process -FilePath $Using:VDAInstallerPath -Wait -PassThru
        }

        return $process.ExitCode
    }

    $result = Invoke-Command -ComputerName $RemoteServerName -ScriptBlock $command

    return $result
}

# Function to install WEM
function Install-WEM {
    param (
        [string]$RemoteServerName,
        [string]$WEMInstallerPath,
        [string]$WEMArgs
    )

    Write-Log "Starting WEM installation at $WEMInstallerPath on $RemoteServerName with arguments: $WEMArgs"

    $command = {
        $process = Start-Process -FilePath $Using:WEMInstallerPath -ArgumentList $Using:WEMArgs -Wait -PassThru
        return $process.ExitCode
    }

    $result = Invoke-Command -ComputerName $RemoteServerName -ScriptBlock $command

    return $result
}

# Function to handle installation results
function Handle-Results { 
    param (
        [int]$InstallResult,
        [string]$RemoteServerName
    )

    $validExitCodes = @(0, 3, 8, 3010)
    $successExitCodes = @(0, 8, 3010)

    Write-Log "Installer exit code [$InstallResult]."
    
    if ($InstallResult -notin $validExitCodes) {
        Handle-Error -ErrorMessage "Failed to install application. Exiting script."
    }

    if ($InstallResult -in $successExitCodes) {
        Write-Log "Application installed successfully. Rebooting server."
        $secondReboot = Test-RemoteReboot -RemoteServerName $RemoteServerName

        if ($secondReboot) {
            Write-Log "Remote server restarted successfully."
            Handle-Completed -CompletedMessage "Application installed successfully."
        } 
        else {
            Handle-Error -ErrorMessage "Failed to restart the remote server. Exiting script."
        }
    }

    if ($installResult -eq 3) {
        Write-Log "Application installer needs to be run again. Rebooting server."

        Write-Log "Restarting the remote server before starting install..."
        $secondReboot = Test-RemoteReboot -RemoteServerName $RemoteServerName
        if ($secondReboot) {
            Write-Log "Remote server restarted successfully."
        } 
        else {
            Handle-Error -ErrorMessage "Failed to restart the remote server. Exiting script."
        }
    }
}

# Main script execution starts here
$isWinRMAccessible = Test-RemoteWinRM -RemoteServerName $ServerName
$isUNCPathAccessible = Test-RemoteUNC -RemoteServerName $ServerName

if ($isWinRMAccessible -and $isUNCPathAccessible) {
    Write-Log "Server is reachable via UNC and WinRM"
    $vdaInstaller = $serverVda
    $wemInstaller = $serverWem
    
    # Check if the server is running Windows Server 2012
    $isServer2012 = Test-RemoteServerVersion -RemoteServerName $ServerName
    if ($isServer2012) {
        $vdaInstaller = $server2012Vda
        $wemInstaller = $server2012Wem
    }

    # Prepare remote folder and copy installers
    Ensure-RemoteFolder -RemoteServerName $ServerName -FolderPath $softwareFolder
    Copy-Item -Path $vdaInstaller -Destination "\\$ServerName\$softwareFolder\VDAServerSetup.exe" -Force
    Copy-Item -Path $wemInstaller -Destination "\\$ServerName\$softwareFolder\Citrix Workspace Environment Management Agent.exe" -Force
    if ($?) {
        Write-Log "VDA installer copied to $ServerName"
    } 
    else {
        Handle-Error -ErrorMessage "Failed to copy VDA installer to $ServerName. Exiting script."
    }
    $localVdaInstaller = "$softwareFolder\VDAServerSetup.exe"
    $localVdaInstaller = $localVdaInstaller -replace '\$', ':'

    # Restart the remote server before installation
    Write-Host "Restarting the remote server before starting install..."
    $firstReboot = Test-RemoteReboot -RemoteServerName $ServerName
    if ($firstReboot) {
        Write-Log "Remote server restarted successfully."
    } 
    else {
        Handle-Error -ErrorMessage "Failed to restart the remote server. Exiting script."
    }

    # Install VDA
    $maxIterations = 5
    $iteration = 0

    while ($iteration -lt $maxIterations) {
        Write-Log "Installing VDA on the remote server. Pass $($iteration + 1)..."
        
        $installResult2 = Install-VDA -RemoteServerName $ServerName -VDAInstallerPath $localVdaInstaller -VDAArgs $vdaArgs
        Handle-Results -InstallResult $installResult2 -RemoteServerName $ServerName

        $iteration++
    }

    # Install WEM if specified
    if ($InstallWEM -eq $false) {
        Handle-Completed "VDA Install completed successfully."
    } 
    else {
        Write-Log "VDA install completed successfully."
        Write-Log "Installing WEM on the remote server..."
        $installResult = Install-WEM -RemoteServerName $ServerName -WEMInstallerPath $localVdaInstaller -WEMArgs $wemArgs
        Handle-Results -InstallResult $installResult -RemoteServerName $ServerName
        Handle-Completed "VDA and WEM install completed successfully."
    }
} 
else {
    Handle-Error -ErrorMessage "Server is not reachable via UNC and WinRM. Exiting script."
}
