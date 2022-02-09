<#
.Synopsis
   Checks for encrypted internal BitLocker volumes on a device and initiates a backup to Azure AD. It's primarily designed to be used within 
   Microsoft Endpoint Manager Configuration Manager as an on-demand script, or inside of a Configuration Item.


.DESCRIPTION
   This script is designed to run periodically on a client to ensure that BitLocker keys are being backed up to Azure Active Directory / Intune.
   It will:

   Check for encrypted internal volumes
      Verify that each encrypted volume has a RecoveryPassword keyprotector assigned
      Trigger a keyprotector backup to AAD

   By default, log will be written to "$($env:windir)\ccm\logs\" if it exists, otherwise it'll go to "$($env:windir)\temp\".
   This can be changed by specifying a value for the logdirectory parameter. The log file name will always be 'Script_BackupBitlockerKeys.log'

   This is not intended to use to determine BitLocker compliance, only to attempt to ensure that keys are backed up to Azure AD.

   Zeb Smith
   Twitter @zebulonsmith

.EXAMPLE
   Backup-BitlocerkeysToAAD

   Runs with the default options, logging to the config manager client log directory and returning $true if there are no errors.
   The script can be copy/pasted directly into a Configuration Item with no modification.


.Example
   Backup-BitlockerKeystoAAD -logdirectory c:\somedir -ReturnType Object

   Logs to c:\somedir and will return an object that includes the results of the backup attempts. 
#>

Param (
    # Optional Log Directory. Uses Config Manager Client's log directory by default.
    [Parameter(Mandatory=$false)]
    [string]
    $logdirectory,

    #Set to "Boolean" to return True/False if the operation completed without errors, 
    #otherwise an object with more information will be returned.
    #Boolean is useful for when this script is used in a config baseline or a package.
    #Object will return more info if the script is ran manually from the console.
    [Parameter(Mandatory=$false)]
    [ValidateSet("Object","Boolean")]
    [String]
    $ReturnType = "Boolean"
)




#Function to write out to a log file
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
			#Write-Error $Message
			$LevelText = 'ERROR:'
		}
		'Warning' {
			#Write-Warning $Message
			$LevelText = 'WARNING:'
		}
		'Information' {
			#Write-Verbose $Message
			$LevelText = 'INFORMATION:'
		}
	}

	Try {
		"$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
	} catch {

		$BackupFile = "$BackupPath\$(Split-path -path $path -leaf)"
		#Write-Warning "$Path is not writeable. Using $BackupFile"
		"$FormattedDate $LevelText $Message" | Out-File -FilePath $BackupFile -Append
	}


}

#Set up our logging dir. We're going to try writing to the default ccm client log dir, if that doesn't work, write to c:\windows\temp
if (!([string]::IsNullOrEmpty($logdirectory))) {
   $logdir = $logdirectory
} elseif ( (test-path "$($env:windir)\ccm\logs\") ) {
   $logdir = "$($env:windir)\ccm\logs\"
} else {
   $logdir = "$($env:windir)\temp\"
}

#Set log file name and manually write the first entry to it so that the file is started clean
$logfile = "$($logdir)\Script_BackupBitlockerKeys.log"
"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" | Out-file -FilePath $logfile -Force

Write-LogFile -Message "Beginning operation" -LogLevel Information -Path $logfile
Write-logfile -message "Computer name: $($env:computername)" -loglevel Information -path $logfile

#Make sure we can import the Windows BitLocker module
Try {
   Write-LogFile -Path $logfile -LogLevel Information -Message "Importing BitLocker powershell module."
   Import-module Bitlocker -DisableNameChecking
} Catch {
   Write-LogFile -Path $logfile -LogLevel Error -Message "Failed to import Bitlocker module."
   Throw "Failed to import Bitlocker module. $($_.Exception.Message)."
}

#region Get an array of all encrypted volumes and make sure that all of them have a recoverypassword
#Will ignore any volumes that are in status 'FullyDecrypted' to avoid creating keyprotectors for disks that we wouldn't normally encrypt
Try {
   $Volumes = Get-BitLockerVolume |Where-Object {$_.VolumeStatus -ne "FullyDecrypted"}
   Write-Logfile -path $logfile -loglevel Information -message "Found $($volumes.count) encrypted volume(s) to process."
} Catch {
   Write-LogFile -Path $logfile -LogLevel Error -Message "Failed to get BitLocker Volumes."
   Throw "Failed to get BitLocker Volumes $($_.Exception.Message)"
}

if ($Volumes.count -eq 0) {
   Write-LogFile -Path $logfile -LogLevel Error -Message "No encrypted volumes found."    
   Throw "No Encrypted Volumes Found." #Error out if we don't find any encrypted volumes
}

$AADBackupFails = @() #Keep track of any volumes that fail to backup their key to make it easy to return results later.
$BackupResults = @{} #Will be used as a return object when $ReturnType is set to 'Object'
Foreach ($volume in $volumes) {
	$RecoveryPassword = @($volume.KeyProtector | Where-Object {$_.KeyprotectorType -eq "RecoveryPassword"})
    Foreach ($rpwd in $RecoveryPassword) {

		#Backup to AAD.
        $AADBKUP = BackupToAAD-BitLockerKeyProtector -MountPoint $volume.MountPoint -KeyProtectorId $rpwd.KeyProtectorId
        if ($null -eq $AADBKUP) {
            Write-LogFile -Path $logfile -LogLevel Error -message "Failed to backup recovery key $($rpwd.KeyProtectorId) for $($volume.mountpoint) to Azure Active Directory"
            Write-Error "Failed to backup recovery key $($rpwd.KeyProtectorId) for $($volume.mountpoint) to Azure Active Directory"
            $AADBackupFails+=$volume.MountPoint
            $BackupResults.Add($volume.mountpoint,"FAIL")
        } else {
            Write-LogFile -Path $logfile -LogLevel Information -message "Backed recovery key $($rpwd.KeyProtectorId) for $($volume.mountpoint) to Azure Active Directory"
            $BackupResults.add($volume.mountpoint,"SUCCESS")
        }
    }

}

#Return results appropriately based on the results of the backup attempts. 
if ($ReturnType -eq "Boolean") {
   if ($AADBackupFails.count -gt 0) {
      $failedVolumeString = $AADBackupFails -join ","
      Write-LogFile -Path $logfile -LogLevel Error -Message "Failed to back up RecoveryPassword keyprotectors for the following volume(s): $failedVolumeString."
      Write-Logfile -Path $logfile -LogLevel Information -Message "Operation Completed."

      Throw "Failed to back up RecoveryPassword keyprotectors for the following volumes: $failedVolumeString."
   } else {
      Return $true #Exit cleanly if there's no errors.
   }
} else {
   Return $BackupResults #Return the results of the AAD key backup attempt.
}