<#
.DESCRIPTION
Enable the UWF feature in Windows.
This script only installs the feature
It DOES NOT configure UWF
A restart will be required before the feature begins working

.PARAMETER ForceRestart
Set to "1" to force a restart after the installation. *Note: SCCM Script exection does not support [SWITCH] parameters, so we have to be janky

.PARAMETER LogPath
Path to a .log file where script output will be saved


.EXAMPLE
Install-UWF -ForceRestart
#>
Param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("0","1")]
    [INT]$ForceRestart = "0",

    [Parameter(Mandatory=$false)]
    [STRING]$LogPath = "$env:windir\temp\KSUInstall-UWF.log"

)


Function Update-Status {
    
    Param (
        [Parameter(Mandatory = $true)]
        $Outfile,

        [Parameter(Mandatory = $true)]
        $Message
    )

    Write-Verbose $Message

    Try {
        $Message | Out-File -FilePath $Outfile -Append
    }
    Catch {
        Write-Verbose "Failed to write to log file $Outfile. 'n $($_.Exception.Message)"
    }
    
}



Update-Status -OutFile $LogPath -Message "Beginning install on $(get-date -format g)..."

#Import the DISM module
#Import-Module -Name DISM

#Install the features requred
Update-Status -OutFile $LogPath -Message "Beginning Feature install for UWF (Client-UnifiedWriteFilter)" -ForegroundColor Cyan
Try {
    if ($ForceRestart -eq 0) {
        Update-Status -Outfile $LogPath -Message "Installing Client-UnifiedWriteFilter feature with reboots suppressed."
        Enable-WindowsOptionalFeature -FeatureName "Client-UnifiedWriteFilter" -online -NoRestart -all | Out-Null
    } elseif ($ForceRestart -eq 1) {
        Update-Status -Outfile $LogPath -Message "Installing Client-UnifiedWriteFilter feature with mandatory reboot."
        Enable-WindowsOptionalFeature -FeatureName "Client-UnifiedWriteFilter" -online | Out-Null
    }
} catch {
    Update-Status -Outfile $LogPath -Message "ERROR: Failed to install Client-UnifiedWriteFilter feature"
    Throw "ERROR: Failed to install Client-UnifiedWriteFilter feature"
}
