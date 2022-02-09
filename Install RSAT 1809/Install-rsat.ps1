
<#
.DESCRIPTION
Installs RSAT tools via Add-WindowsCapability for Windows 10 1809 and greater.

.PARAMETER ADToolsOnly
Installs only the tools commonly needed by T1:
Rsat.ActiveDirectory.DS-LDS.Tools
Rsat.BitLocker.Recovery.Tools
Rsat.GroupPolicy.Management.Tools

Set to 1 to enable or 0 to install all Capabilities listed by Get-Windowscapability -name "RSAT.*" Default is 0

.EXAMPLE
Install-RSAT.ps1 -ADToolsOnly 1

#>


Param (
    # ADToolsOnly
    [Parameter(Mandatory=$false)]
    [INT]
    $ADToolsOnly = 0
)

#installs a WindowsCapability, then checks to validate that it's actually succeeded
#Needed because Add-WindowsCapability doesn't always give us feedback if an install doesn't happen.
Function Start-Install ($name){
    #Try the install
    Write-LogFile "Installing $name" -LogLevel Information -Path $logfile
    Try {
        Add-WindowsCapability -online -Name $name | Out-Null
    } Catch {
        Write-LogFile "Failed to install $name" -LogLevel Warning -Path $logfile
    }

    #Check when we're done just to be sure
    if ( $null -eq (Get-WindowsCapability -online -name $name | where-object {$_.State -eq "Installed"}) ) {
        Write-Logfile "Unable to install $name" -LogLevel Warning -Path $logfile
    }

}

<#
.DESCRIPTION Writes log files

.PARAMETER Message
The string to be written to the log file

.PARAMETER LogLevel
Specify a level of severity for the log item

.PARAMETER Path
Path to the log file

.EXAMPLE
Write-LogFile -Message "Log entry text" -LogLevel Warn -Path "$($env:windir\temp\logfile.log"

 #>
 function Write-LogFile
 {
 
     [CmdletBinding()]
     Param
     (
         [Parameter(Mandatory = $true,ValueFromPipelineByPropertyName = $true)]
         [ValidateNotNullOrEmpty()]
         [string]$Message,
 
         [Parameter(Mandatory = $false)]
         [ValidateSet("Error", "Warning", "Information")]
         [string]$LogLevel = "Information",
         
         [Parameter(Mandatory = $True)]
         [string]$Path,
         
         [Parameter(Mandatory=$false)]
         [string]$BackupPath = "$($env:temp)"
     )
     
     #Get a pretty date string
     $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
     
     # Write message to error, warning, or verbose pipeline and specify $LevelText 
     switch ($LogLevel)
     {
         'Error' {
             Write-Error $Message
             $LevelText = 'ERROR:'
         }
         'Warning' {
             Write-Warning $Message
             $LevelText = 'WARNING:'
         }
         'Information' {
             Write-Verbose $Message
             $LevelText = 'INFORMATION:'
         }
     }
     
     Try {
         "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
     } catch {
 
         $BackupFile = "$BackupPath\$(Split-path -path $path -leaf)"
         Write-Warning "$Path is not writeable. Using $BackupFile"
         "$FormattedDate $LevelText $Message" | Out-File -FilePath $BackupFile -Append
     }
 
     
 }
 

 #Set up our logging dir. We're going to try writing to the default ccm client log dir, if that doesn't work, write to c:\windows\temp
 if ( (test-path "$($env:windir)\ccm\logs\") ) {
     $logdir = "$($env:windir)\ccm\logs\"
 } else {
     $logdir = "$($env:windir)\temp\"
 }
 
 $logfile = "$($logdir)\Script_InstallRSAT.log"
 
 Write-LogFile -Message "Beginning operation" -LogLevel Information -Path $logfile

#First bypass UseWUServer setting as needed
if ($BypassWSUSCOnfiguration -eq 1) {
    $ResetUseWUServer = $true #Will be used later to reset to the original state
}

#Install RSAT Tools
#We're going to run the Enable-BypassWUServer function before each install as it may be re-enabled at any point by the SCCM client / GPO / etc
if ($ADToolsOnly -eq 1) {#Install AD stuff
    Write-Logfile -message "Installing only Tier1 AD Tools." -LogLevel Information -Path $logfile
    $adtools = @("Rsat.ActiveDirectory.DS-LDS.Tools", "Rsat.BitLocker.Recovery.Tools", "Rsat.GroupPolicy.Management.Tools")

    foreach ($tool in $adtools) {
        if ($ResetUseWUServer) {Enable-BypassWUServer}
        Start-Install -name $tool
    }

} else { #Install everything
    Write-Logfile -message "Installing all RSAT Tools" -LogLevel Information -Path $logfile
    $tools = (Get-WindowsCapability -online -name "RSAT*").name
    foreach ($tool in $tools) {
        if ($ResetUseWUServer) {Enable-BypassWUServer}
        Start-Install -name $tool
    }
}

Write-Logfile -message "Operation Completed" -LogLevel Information -Path $logfile