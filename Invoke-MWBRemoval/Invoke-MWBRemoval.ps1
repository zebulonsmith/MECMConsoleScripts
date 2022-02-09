#Removes MalwareBytes Anti-Malware from a device

[CmdletBinding()]
param (

    # Download URL
    [Parameter(Mandatory=$false)]
    [string]
    $MWBRemovalToolURL = "https://support.malwarebytes.com/hc/en-us/article_attachments/360061674534/mbstcmd-1.0.2.34.exe",

    # Full path including name for the file to be downloaded
    [Parameter(Mandatory=$false)]
    [string]
    $DownloadFilePath = "$env:temp\mbstcmd-1.0.2.34.exe",

     # Optional Log Dir
     [Parameter(Mandatory=$false)]
     [string]
     $logdirectory 
)


#Writes log info
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


<#
.DESCRIPTION Launches a process and monitors it until the process ends. Returns the exit code.

.PARAMETER Filename Name of the file that will be executed. Include the path to the file (c:\windows\system32\notepad.exe) if it is not in a location specified by $env:path.

.PARAMETER WorkingDirectory Optionally specify a working directory for the process.

.PARAMETER Arguments Any arguments that need to be passed to the executable.

.PARAMETER UpdateSeconds Interval for writing status updates to the log file. One line will be written indicating the status of the running process every time this interval is reached.

.PARAMETER logfile Path to the log file that will be used for status updates.

.EXAMPLE
Start-InstallWrapperProcess -Filename "C:\windows\system32\notepad.exe"
#>
Function Start-InstallWrapperProcess {
	Param (
		# Name of the file that will be executed. Include the path to the file (c:\windows\system32\notepad.exe) if it is not in a location specified by $env:path.
		[Parameter(Mandatory=$true)]
		[String]
		$Filename,

        # Working directory for the file to be executed
		[Parameter(Mandatory=$false)]
		[String]
		$WorkingDirectory,

		# Arguments to pass to the command being executed
		[Parameter(Mandatory=$False)]
		[String]
		$arguments = "",

		#Interval for writing status updates to the log file. A value of '60' means that every 60 seconds a line will be written to the file indicating that the process is running
		[Parameter(Mandatory=$false)]
		[Int]
		$UpdateSeconds = 300,

		# Log file to be used. This should be the same as the file used everywhere else.
		[Parameter(Mandatory=$true)]
		[String]
		$logfile
	)

	$processinfo = New-Object System.Diagnostics.ProcessStartInfo
	$processinfo.FileName = $filename
    $processinfo.WorkingDirectory = $WorkingDirectory
	$processinfo.RedirectStandardError = $true
	$processinfo.RedirectStandardOutput = $true
	$processinfo.UseShellExecute = $false
	$processinfo.Arguments = $arguments
	$processinfo.LoadUserProfile = $false
	$processinfo.CreateNoWindow = $true

	Write-LogFile -Message "Executing: $($processinfo.filename) `n   Arguments: $($processinfo.arguments) `n   WorkingDirectory: $($processInfo.WorkingDirectory)" -LogLevel Information -Path $logfile
	
	$currentprocess = New-Object System.Diagnostics.Process
	$currentprocess.StartInfo = $processinfo
	$currentprocess.Start() | out-null

    Write-LogFile -Message "Process Started with ID $($currentprocess.ID)" -LogLevel Information -Path $logfile
    Write-LogFile -Message "     Process Modules: `n$($currentprocess.Modules)" -LogLevel Information -Path $logfile


	$ExecutionTime = 0

	#Loop until the process finishes. Write to the log file every 60 seconds.
	$SleepSeconds = 1
	while ($currentprocess.hasexited -eq $false) {
			Start-sleep -Seconds $SleepSeconds
			$ExecutionTime = $ExecutionTime + $SleepSeconds
			if (($ExecutionTime % $UpdateSeconds) -eq 0) {
				Write-LogFile -Message "$($processinfo.filename) has been running for $($ExecutionTime) seconds." -LogLevel Information -Path $logfile

				if ($currentprocess.responding -eq $false) {
					Write-logfile -Message "     Process is not responding." -LogLevel Warning -Path $logfile
				}
			}			
	}

	#exit
	Write-Logfile -message "Process Exited on $($currentprocess.ExitTime) with Exit Code $($currentprocess.ExitCode)" -LogLevel Information -Path $logfile

	Return $currentprocess.ExitCode
}


#Set up our logging dir. We're going to try writing to the default ccm client log dir, if that doesn't work, write to c:\windows\temp
if ($null -ne $logdirectory) {
    $logdir = $logdirectory
}
elseif ( (test-path "$($env:windir)\ccm\logs\") ) {
    $logdir = "$($env:windir)\ccm\logs\"
} else {
    $logdir = "$($env:windir)\temp\"
}

$logfile = "$($logdir)\Script_RemoveMWB_$($env:computername).log"

Write-LogFile -Message "Beginning operation" -LogLevel Information -Path $logfile



#Download the latest version of the removal tool
Write-LogFile -Message "Downloading MWB removal tool from $MWBRemovalToolURL" -LogLevel Information -Path $logfile
try {
    Invoke-WebRequest -Uri $MWBRemovalToolURL -UseBasicParsing -OutFile $DownloadFilePath
}
catch {
    Write-LogFile -LogLevel Error -Path $logfile -Message "$($_)"
    Throw $_
}


#Run the thing
$arg = "/y /cleanup /noreboot"
Write-LogFile -LogLevel Information -Path $logfile -Message "Running MWB removal tool using '$DownloadFilePath $args"
$Process = Start-InstallWrapperProcess -Filename $DownloadFilePath -arguments $arg -logfile $logfile

Write-LogFile -LogLevel Information -Path $logfile -Message "Process exited with code $process"

Return $Process