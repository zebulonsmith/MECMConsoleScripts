Param (
    # SPSS Version
    [Parameter(Mandatory=$true)]
    [int]
    $SPSSRequiredVersion = 26,

    # SPSS Key
    [Parameter(Mandatory=$true)]
    [string]
    $SPSSKey = "EnterKeyHere",

    # SPSS MSI Code
    [Parameter(Mandatory=$true)]
    [string]
    $SPSSMSICode = "{1AC22BAE-DC13-4991-9910-AE3743A4592D}",

    # SPSS License updater exe
    [Parameter(Mandatory=$false)]
    [string]
    $SPSSLicenseUpdaterPath
)


<#
.DESCRIPTION
Writes log file entries including a time stamp and information level on each line. Plays well with cmtrace.exe.

.PARAMETER Message
The text of the log entry

.PARAMETER LogLevel
Information - Write an informational line to the log and write-verbose
Warning - Write a warning line to the log and write-warning
Error - Write an error message to the log and write-error

.PARAMETER Path
File path to write to. It will be created if it doesn't exist and appended otherwise.

.PARAMETER BackupPath
Optionally specify a backup path to write log files to in case the one specified by -Path does not exist or isn't writeable. 
Defaults to $env:temp, which should almost always be writeable.

.EXAMPLE
Write-LogFile -Message "This is a test log entry" -Path 'C:\windows\temp\logtest.log' -loglevel Information
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

Function Invoke-LicenseUpdate {
    Param (
        # Custom object containing app info
        [Parameter(Mandatory=$true)]
        $Appinfo
    )

    #Make sure license activator exists
    if (!(Test-path $Appinfo.LicenseUpdaterPath)){
        Write-Logfile -path $logfile -loglevel Error -message "License update utility at $($appinfo.LicenseUpdaterPath) does not exist."
        Throw "License updater at $($appinfo.LicenseUpdaterPath) does not exist."
    }

    $licenselogfile = "$logdir\Script_licenseActivation_$($appinfo.product).log"
    try {
        Write-Logfile -path $logfile -loglevel information -message "Applying license key $($appinfo.Key) with $($appinfo.LicenseUpdaterPath)"
        Start-process -FilePath $appinfo.LicenseUpdaterPath -argumentlist $SPSSKey -redirectstandardoutput $licenselogfile
    }
    catch {
        Write-Logfile -path $logfile -loglevel Error -message "Failed to launch license activation utility. $($_.exception.message)"
        Throw $_
    } 

    Start-sleep -Seconds 120
    $LicenseActivationLog = Get-content $licenselogfile

    Write-LogFile -Path $logfile -LogLevel Information -Message "~~~~~~~~~~~~~~~~~~~~~License Activation Result~~~~~~~~~~~~~~~~~~~"
    $LicenseActivationLog | % {Write-Logfile -path $logfile -loglevel information -message $_}
    Write-Logfile -path $logfile -loglevel information -message "~~~~~~~~~~~~~~~~~~~~~License Activation Result~~~~~~~~~~~~~~~~~~~"

    if ($LicenseActivationLog -like "*Authorization succeeded*") {
        Write-Logfile -path $logfile -loglevel information -message "Activation log indicates a success."
        Return 
    } else {
        Write-Logfile -path $logfile -loglevel Error -message "Activation log did not indicate success."
        Throw "Could not activate"
    }

}

$logdir = "$($env:windir)\ccm\logs"
$logfile = "$($logdir)\script_Update-SPSSLicense.log"

$ApplicationInfo = @{
    Product             = "SPSS"
    RequiredVersion     = $SPSSRequiredVersion
    Key                 = $SPSSKey
    MSICode             = $SPSSMSICode
    LicenseUpdaterPath  = $SPSSLicenseUpdaterPath
    UpdateResult        = ""
}


Write-Logfile -path $logfile -loglevel information -message "Checking for SPSS version $($ApplicationInfo.Requiredversion)."

$product = Get-CimInstance win32_product |Where-object {$_.IdentifyingNumber -eq $ApplicationInfo.MSICode}
if (($null -ne $product) -and (([version]$product.Version).Major -eq $ApplicationInfo.RequiredVersion) ) {
    Write-Logfile -path $logfile -loglevel information -message "Product found, will attempt to update license information."
    Try {
        Invoke-LicenseUpdate -appinfo $ApplicationInfo
        Write-Logfile -path $logfile -loglevel information -message "No errors encountered."
        $ApplicationInfo.UpdateResult = "Success"
    } Catch {
        Write-Logfile -path $logfile -loglevel information -message "License update failed. $_"
        $ApplicationInfo.UpdateResult = "Failed"
    }

} else {
    $wrongvernothere = "$($ApplicationInfo.Product) is not installed or not version $($ApplicationInfo.RequiredVersion)."
    Write-Logfile -path $logfile -loglevel Error -message $wrongvernothere
    $ApplicationInfo.UpdateResult = $wrongvernothere
}


Return $ApplicationInfo.UpdateResult