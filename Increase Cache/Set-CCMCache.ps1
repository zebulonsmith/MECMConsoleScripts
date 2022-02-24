<#
.DESCRIPTION
This script is intended to be used in conjunction with SCCM Application or Package deployments that require a larger 
than normal CCMCache reservation. It will validate that sufficient free space is available, then change the cache size to a specified value and clear it if requested.

Will attempt to write a log file to $env:windir\ccm\logs\Script_IncreaseCCMCache.ps1, but falls back to $env:temp 
if the CCM\Logs dir is not accessable.

.PARAMETER CCMCacheSizeMB
Size in MB that the ccmcache will be temporarily expanded to. Defaults to 20GB if not specified.

.PARAMETER FallBackPercentage
Fallback to this percentage of free disk space if the specified cache size is too large. Useful when running against devices with small disks. 

.PARAMETER ClearExistingCache
Set this to 1 to clear the existing cache. This is an integer as opposed to a switch so that the script can be imported into the 'Run Scripts' feature in SCCM without modification




.EXAMPLE
Set-CCMCache.ps1 -CCMCacheSizeMB 20000 -FallBackPercentage 20 -ClearExistingCache 1



#>



param
(
    #Specify the size of the cache.
    [Parameter(Mandatory=$false)]
    [ValidateRange(1024,[int]::MaxValue)]
    [int]$CCMCacheSizeMB = 20360,

    #Fallback to this percentage of free disk space if the specified cache size is too large. Useful when reducing the cache size after an install
    [Parameter(Mandatory=$false)]
    [int]$FallbackPercentage = 0,

    #If enabled, clears the existing cache.
    [Parameter(Mandatory=$false)]
    [ValidateRange(0,1)]
    [int]$ClearExistingCache = 0

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
		'Info' {
			Write-Verbose $Message
			$LevelText = 'INFORMATION:'
		}
	}
	
	"$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
}


#Set up our logging dir. We're going to try writing to the default ccm client log dir, if that doesn't work, write to c:\windows\temp
if ( (test-path "$($env:windir)\ccm\logs\") ) {
    $logdir = "$($env:windir)\ccm\logs\"
} else {
    $logdir = "$($env:windir)\temp\"
}

$logfile = "$($logdir)\Script_SetCCMCache.log"

Write-LogFile -Message "Beginning operation" -LogLevel Information -Path $logfile


#region Create COM Objects
#Create the COM objects that we'll need later on early so that we can fail immediately if something isn't working. 
Write-LogFile -Message "Creating COM Object references" -LogLevel Information -Path $logfile

#Create COM object for referencing the ConfigMgr GUI
Try {
    
    $UIResource = New-object -ComObject UIResource.UIResourceMgr
} Catch {
    Write-Logfile -LogLevel Error -Message "Failed to create UIResource.UIResourceMgr COM object.`n$($_.exception.message) $($_.Exception.Hresult)" -path $logfile
    Throw $_.Exception.Hresult
}

#endregion

#region validate free disk

Write-LogFile -Message "Validating available free disk space." -LogLevel Information -Path $logfile


#Convert the path string to the cache to a path object
$CurrentCacheLocation = ($UIResource.GetCacheInfo()).location
$CachePath = Resolve-Path $CurrentCacheLocation
Write-LogFile -Message "CCMCache drive is located at $($CurrentCacheLocation)." -LogLevel Information -Path $logfile



#Check for enough free disk to expand the cache
$RequiredFreeSpace =[math]::round($CCMCacheSizeMB - ($UIResource.GetCacheInfo()).TotalSize)
Write-LogFile -message "Will need $($RequiredFreeSpace)MB to update cache." -LogLevel Information -Path $logfile

$AvailableFreeSpace = [math]::round($CachePath.Drive.Free / 1MB)
Write-LogFile -Message "Drive $($Cachepath.Drive.Root) has $($AvailableFreeSpace)MB free." -LogLevel Information -Path $logfile


#If we have enough disk, increase the cache to the specified size. Otherwise, increase by percentage if requested
if ($RequiredFreeSpace -lt $AvailableFreeSpace) {
    $TargetCacheSize = [math]::round($CCMCacheSizeMB)
    Write-LogFile -Message "Found $($AvailableFreeSpace)MB free. Will attempt to increase cache to $($TargetCacheSize)MB." -LogLevel Information -Path $logfile

} else {
    Write-LogFile -Message "Requested cache change to $($CCMCacheSizeMB)MB on drive $($Cachepath.Drive.Root), but there is only $($AvailableFreeSpace)MB free." -LogLevel Warning -Path $logfile

    if ($FallbackPercentage -ne 0)  {
        $TargetCacheSize = [int][math]::round($AvailableFreeSpace * ($FallbackPercentage /100))
        Write-LogFile -Message "Will attempt to set cache to $($FallBackPercentage)% ($($TargetCacheSize))MB of free disk" -LogLevel Information -Path $logfile
        
    } else {
        Write-LogFile "$($RequiredFreeSpace) is needed. Found $($AvailableFreeSpace) on drive $($Cachepath.Drive.Root). FallBackPercentage was not specified, cache will not be modified." -LogLevel Information -Path $logfile
        $ex = [System.IO.IOException]::New("Insufficient disk space on $($Cachepath.Drive.Root)")
        Throw $ex
    }
}

#endregion


#region Set and clear Cache

#We do this last so that we don't manipulate anything important before all of the other steps have completed

#Clear cache as applicable
if ($ClearExistingCache) {
    Write-LogFile -Message "Clearing CCMCache" -LogLevel Information -Path $logfile
    $ccmcache = $UIResource.GetCacheInfo()
    $CacheElements = $ccmcache.GetCacheElements()
    Foreach ($CacheElement in $CacheElements) {
        Write-LogFile -Message "Removing content ID $($CacheElement.CacheElementID) from $($CacheElement.Location)" -LogLevel Information -Path $logfile
        Try {
            $ccmcache.DeleteCacheElement($Cacheelement.CacheElementID)
        } Catch {
            #Warn in the logs but do not terminate if we can't delete something
            Write-LogFile -Message "Unable to delete cache element $($CacheElement.CacheElementID)`n$($_.Exception.Message) $($_.Exception.Hresult)" -LogLevel Warning -Path $logfile
        }

    }
}

Write-LogFile -Message "Increasing CCMCache to $($TargetCacheSize)MB" -LogLevel Information -Path $logfile
Try {
    ($UIResource.GetCacheInfo()).TotalSize = [int]$TargetCacheSize
} Catch {
    Write-LogFile -Message "Unable to increase cache size.`n$($_.exception.message) $($_.Exception.Hresult)" -LogLevel Error -Path $logfile
    Throw $_
}

#Double-check, just to be sure
if ( ($UIResource.GetCacheInfo()).TotalSize -ne $TargetCacheSize ) {
    Write-LogFile -Message "Cache size did not increase as expected." -LogLevel Error -Path $logfile
    Throw $_
} else {
    Write-LogFile -Message "Verified that new CCMCache size is $(($UIResource.GetCacheInfo()).TotalSize)MB" -LogLevel Information -Path $logfile    
}



#endregion

Write-LogFile "Operation Completed" -LogLevel Information -Path $logfile

