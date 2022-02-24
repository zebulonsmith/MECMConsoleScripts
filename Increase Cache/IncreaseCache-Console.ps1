<#
.DESCRIPTION
This script is intended to be used with SCCM >1709's "Run Script" feature when there is a need to temporarily expand the ccmcache size of one or more clients.
It will validate that sufficient free space is available, increase the cache size, and then create a reg key in
HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce to set cache back to the starting size at the next restart.

Restoring the cache is a best effort operation, but is almost 100% reliable. The RestoreCacheMaxRetryCount and RestoreCacheRetryTimeout
parameters are used to tune the number of attempts and time spent on each to restore the cache. This cannot be done until the ccmexec
service is up and running, so the next user logon after the execution of this script will take longer than normal, depending on
hardware speed and the level of reliability desired. Normally, issues only occurr on older devices, or when there is some software
issue causing slow performance.

The script will attempt to write a log file to $env:windir\ccm\logs\Script_IncreaseCCMCache.ps1, but falls back to $env:temp
if the CCM\Logs dir is not accessable.



.PARAMETER CCMCacheSizeMB
Size in MB that the ccmcache will be temporarily expanded to. Defaults to 30GB if not specified.

.PARAMETER ClearExistingCache
Set this to 1 to clear the existing cache.

.PARAMETER ResetCacheSize
Set to reset the ccmcache back to its original starting value on the next reboot. Writes an entry in HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce.

.PARAMETER RestoreCacheMaxRetryCount
Number of times to retry to reset the ccmcache. If the client is busy, it may not be able to update the setting. The script will, by default, retry 15 times before failing.

.PARAMETER RestoreCacheRetryTimeout
Seconds to wait in between attempting to restore.


#>



param
(
    #Specify the size of the cache.
    [Parameter(Mandatory=$false)]
    [ValidateRange(1024,[Uint32]::MaxValue)]
    [int]$CCMCacheSizeMB = 30720,

    #Clears the cache after it's been expanded.
    [Parameter(Mandatory=$false)]
    [ValidateRange(0,1)]
    [int]$ClearExistingCache = 0,

    # Enable to reset the cache size back to the original size after a reboot
    [Parameter(Mandatory=$false)]
    [ValidateRange(0,1)]
    [int]$ResetCacheSize = 0,

    #Number of times to retry to restore the cache after a reboot.
    [Parameter(Mandatory=$false)]
    [int]$RestoreCacheMaxRetryCount= 15,

    #Timeout in between retries when restoring the cache.
    [Parameter(Mandatory=$false)]
    [int]$RestoreCacheRetryTimeout = 30

)


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
		[Parameter(Mandatory = $true,
				   ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Message,
		[Parameter(Mandatory = $false)]
		[ValidateSet("Error", "Warning", "Information")]
		[string]$LogLevel = "Information",

		[Parameter(Mandatory = $True)]
		[string]$Path
	)

	#Get a pretty date string
	$FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

	# Write message to error, warning, or verbose pipeline and specify $LevelText
	switch ($Level)
	{
		'Error' {
			Write-Error $Message
			$LevelText = 'ERROR:'
		}
		'Warning' {
			Write-Warning $Message
			$LevelText = 'WARNING:'
		}
		'Info' {
			Write-Verbose $Message
			$LevelText = 'INFORMATION:'
		}
	}

	"$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
}

<#
#This tomfoolery is to make up for the fact that we can't use a [SWITCH] param in a console script.
if ($ClearExistingCache -eq 0) {
    $ClearExistingCache = $false
} else {
    $ClearExistingCache = $true
}

if ($DoNotResetCacheSize -eq 0) {
    $DoNotResetCacheSize = $false
} else {
    $DoNotResetCacheSize = $true
}#>

#Set up our logging dir. We're going to try writing to the default ccm client log dir, if that doesn't work, write to c:\windows\temp
if ( (test-path "$($env:windir)\ccm\logs\") ) {
    $logdir = "$($env:windir)\ccm\logs\"
} else {
    $logdir = "$($env:windir)\temp\"
}

$logfile = "$($logdir)\Script_IncreaseCCMCache.log"

Write-LogFile -Message "Beginning operation" -LogLevel Information -Path $logfile


#region Create COM Objects
#Create the COM objects that we'll need later on early so that we can fail immediately if something isn't working.
Write-LogFile -Message "Creating COM Object references" -LogLevel Information -Path $logfile

#Create COM object for referencing the ConfigMgr GUI
Try {
    $UIResource = New-object -ComObject UIResource.UIResourceMgr
} Catch {
    Write-Logfile -LogLevel Error -Message "Failed to create UIResource.UIResourceMgr COM object. `n $($_.exception.message) $($_.Exception.Hresult)" -path $logfile
    Throw $_.Exception.Hresult #-2147221164
}

#Create a COM object for the SMS Client
Try {
    $SMSClient = New-object -ComObject Microsoft.SMS.Client
} Catch {
    Write-Logfile -LogLevel Error -Message "Failed to create Microsoft.SMS.Client COM object. `n $($_.exception.message) $($_.Exception.Hresult)" -Path $logfile
    Throw $_.Exception.Hresult #-2147221164
}

#endregion

#region validate parameters

<#
Validate that there's enough disk space to expand the cache to the specified size
#>
Write-LogFile -Message "Validating available free disk space." -LogLevel Information -Path $logfile


#Figure out where the ccmcache currently resides
$CurrentCacheLocation = ($UIResource.GetCacheInfo()).location
if ([STRING]::IsNullOrEmpty($CurrentCacheLocation) ) {
    $ex = [System.IO.DirectoryNotFoundException]::New('Unable to get the current CCMCache location')
    Write-LogFile -Message "Unable to get the current CCMCache location. $($ex.HResult)" -LogLevel Error -Path $logfile
    throw $ex.HResult #-2147024893
}

Try {
    $CachePath = Resolve-Path $CurrentCacheLocation
} Catch {
    Write-Logfile -Message "Unable to resolve path $($CurrentCacheLocation). $($_.Exception.Hresult)" -LogLevel Error -Path $logfile
    Throw $_.Exception.Hresult #-2146233087
}


Write-LogFile -Message "CCMCache drive is $($CachePath.Drive.Root) ." -LogLevel Information -Path $logfile

    $RequiredFreeSpace  = $CCMCacheSizeMB - ($UIResource.GetCacheInfo()).TotalSize
    $AvailableFreeSpace = $CachePath.Drive.Free / 1MB

    if ($RequiredFreeSpace -gt $AvailableFreeSpace) {
        $ex = [System.IO.IOException]::New("Insufficient disk space on $($CachePath.Drive.Root)")
        Write-LogFile -Message "Increased Cache requires $($RequiredFreeSpace)MB on drive $($CachePathPath.Drive.Root), but there is only $($AvailableFreeSpace)MB free. $($ex.HResult)" -LogLevel Error -Path $logfile
        Throw $ex.HResult #-2146232800
    } else {
        Write-LogFile "Found $($AvailableFreeSpace) on drive $($InstallPath.Drive.Root)" -LogLevel Information -Path $logfile
    }


#endregion


#region Get Site Information
#Get SCCM Site Code
Try {
    $CMSite = $SMSClient.GetAssignedSite()
    Write-LogFile -Message "Discoverd CMSite code $($CMSite)" -LogLevel Information -Path $logfile
} Catch {
    Write-LogFile -Message "Unable to discover Config Manager Site Code. Client may be unhealthy. `n $($_.Exception.Message) $($_.Exception.Hresult)" -LogLevel Error -Path $logfile
    Throw $_.Exception.Hresult
}
#Would be hard for this to not work, but error checking is good
if ([STRING]::IsNullOrEmpty($CMSite) ){
    $ex = [System.Runtime.InteropServices.InvalidComObjectException]::New("Unable to discover ConfigMgr Site Code. Client may be unhealthy.")
    Write-LogFile -Message "$($ex.Message) $($ex.hresult)" -LogLevel Error -Path $logfile
    Throw $ex.HResult
}

#Get the current cache size
Try {
    $CurrentCacheSize = ($UIResource.GetCacheInfo()).TotalSize
} Catch {
    $ex = [System.Runtime.InteropServices.InvalidComObjectException]::New("Unable to get current CCMCache size. Client may be unhealthy.")
    Write-LogFile -Message "$($ex.Message) $($ex.hresult)" -LogLevel Error -Path $logfile
    Throw $ex.HResult
}
if ([STRING]::IsNullOrEmpty($CurrentCacheSize) ){
    $ex = [System.Runtime.InteropServices.InvalidComObjectException]::New("Unable to get current CCMCache size. Client may be unhealthy.")
    Write-LogFile -Message "$($ex.Message) $($ex.hresult)" -LogLevel Error -Path $logfile
    Throw $ex.HResult
}
#EndRegion



#region code to restore cache

<#
This section creates a RunOnce reg key to set the cache back to its original value 
on the next reboot, if desired.
#>
if ($ResetCacheSize -eq 1) {

$ResetCacheOneLiner = @"
powershell.exe -WindowStyle "Hidden" -noprofile -command "& {for (`$i=1; `$i -le $RestoreCacheMaxRetryCount; `$i++){try{((New-object -ComObject UIResource.UIResourceMgr).GetCacheInfo()).TotalSize = $CurrentCacheSize;break} Catch {Start-sleep -Seconds $RestoreCacheRetryTimeout}}}"
"@

    $RegRunOnce = "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"

    Write-LogFile -Message "Writing RunOnce value 'RestoreCCMCache' to $($RegRunOnce) with value '$($ResetCacheOneLiner)'" -LogLevel Information -Path $logfile

    Try {
        New-ItemProperty -Path $RegRunOnce -Name "RestoreCCMCache" -Value $ResetCacheOneLiner -PropertyType String -Force | Out-Null
    } Catch {
        Write-LogFile -Message "Unable to add RestoreCCMCache RunOnce value to the registry. $($_.Exception.Hresult)" -LogLevel Error -Path $logfile
        Throw $_.Exception.Hresult
    }
} else {
    Write-LogFile -Message "DoNotResetCacheSize is enabled. Will not restore ccmcache to its original value." -LogLevel Information -Path $logfile
}
#endregion



#region Increase/Clear Cache

#We do this last so that we don't manipulate anything important before all of the other steps have completed
Write-LogFile -Message "Increasing CCMCache to $($CCMCacheSizeMB)MB" -LogLevel Information -Path $logfile
Try {
    ($UIResource.GetCacheInfo()).TotalSize = $CCMCacheSizeMB
} Catch {
    $ex = [System.Runtime.InteropServices.InvalidComObjectException]::New("Unable to increase CCMCache size.")
    Write-LogFile -Message "Unable to increase cache size. $($ex.HResult)" -LogLevel Error -Path $logfile
    Throw $ex.HResult #-2146233049
}

#Double-check, just to be sure
if ( ($UIResource.GetCacheInfo()).TotalSize -ne $CCMCacheSizeMB ) {
    $ex = [System.Runtime.InteropServices.InvalidComObjectException]::New("Unable to increase CCMCache size.")
    Write-LogFile -Message "Unable to increase cache size. $($ex.HResult)" -LogLevel Error -Path $logfile
    Throw $ex.HResult #-2146233049
} else {
    Write-LogFile -Message "Verified that new CCMCache size is $(($UIResource.GetCacheInfo()).TotalSize)MB" -LogLevel Information -Path $logfile
}

#Clear cache as applicable
if ($ClearExistingCache -eq 1) {
    Write-LogFile -Message "Clearing CCMCache" -LogLevel Information -Path $logfile
    $ccmcache = $UIResource.GetCacheInfo()
    $CacheElements = $ccmcache.GetCacheElements()
    Foreach ($CacheElement in $CacheElements) {
        Write-LogFile -Message "Removing content ID $($CacheElement.CacheElementID) from $($CacheElement.Location)" -LogLevel Information -Path $logfile
        Try {
            $ccmcache.DeleteCacheElement($Cacheelement.CacheElementID)
        } Catch {
            #Warn in the logs but do not terminate if we can't delete something
            Write-LogFile -Message "Unable to delete cache element $($CacheElement.CacheElementID)." -LogLevel Warning -Path $logfile
        }

    }
} else {
    Write-LogFile -Message "ClearExistingCache was not specified. Will not clean ccmcache." -LogLevel Information -Path $logfile
}

#endregion

Write-LogFile "Operation Completed" -LogLevel Information -Path $logfile