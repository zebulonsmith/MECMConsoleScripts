<#
HEY!
Microsoft has changed the supported methods of changing the Click2Run update channel since this was written, so don't use this thing.

See here. https://docs.microsoft.com/en-us/deployoffice/change-update-channels

#>


<#
.DESCRIPTION
Sets Office365 to use the specified channel. OfficeC2rClient does not give us much feedback as to whether or not operations have succeeded, so we can't do a lot of error checking.
Maybe one day we'll have PowerShell cmdlets to do this intead. Troubleshooting can be done by reading the C2R logs in $env:windir\temp.


.PARAMETER Channel
Optional. Specify The a release channel to change to. "Monthly", "MonthlyTargeted", "SemiAnnual", or "SemiAnnualTargeted"
https://blogs.technet.microsoft.com/odsupport/2017/05/10/how-to-switch-channels-for-office-2016-proplus/
https://blogs.technet.microsoft.com/odsupport/2014/03/03/the-new-update-now-feature-for-office-2013-click-to-run-for-office365-and-its-associated-command-line-and-switches/
https://docs.microsoft.com/en-us/sccm/sum/deploy-use/manage-office-365-proplus-updates
https://docs.microsoft.com/en-us/sccm/sum/deploy-use/manage-office-365-proplus-updates#change-the-update-channel-after-you-enable-office-365-clients-to-receive-updates-from-configuration-manager

.PARAMETER ForceAppShutdown
Optional. Set to 1 to force apps to close or 0 to leave them open. Can't use a switch here because the ConfigMgr console only supports Int and String. Default is 0. 
This is not typically needed.

.PARAMETER DisplayLevel
Optional. Set to 1 to allow the user to see the Office dialog when OfficeC2rClient.exe runs, 0 to hide it. Default is 0.

.PARAMETER UpdatePromptUser
Optional. Set to 1 to show the O365 Update dialog asking the user if they'd like to update, or 0 to run silent. Default is 0. Cannot be used with DisplayLevel.

.PARAMETER OfficeC2rClientPath
Optional. If OfficeC2rClientPath isn't installed in $env:CommonProgramFiles, set the path here. 

.EXAMPLE
Configure-O365Channel -Channel "Insiders"

.EXAMPLE
Configure-O365Channel -Channel "Targeted" -UpdatePromptUser
#>


Param (
    # Channel
    [Parameter(Mandatory=$True)]
    [ValidateSet("Monthly","MonthlyTargeted","SemiAnnual","SemiAnnualTargeted","InsiderFast")]
    [STRING]
    $Channel,

    # Force apps to shutdown if needed.
    [Parameter(Mandatory=$false)]
    [INT]
    $ForceAppShutdown = 0,

    # DisplayLevel
    [Parameter(Mandatory=$false)]
    [ValidateRange(0,1)]
    [INT]
    $DisplayLevel = 0,

    # UpdatePromptUser
    [Parameter(Mandatory=$false)]
    [ValidateRange(0,1)]
    [INT]
    $UpdatePromptUser = 0,

    # You really shouldn't need this
    [Parameter(Mandatory=$false)]
    [STRING]
    $OfficeC2rClientPath = ""
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
Write-LogFile -Message "Log entry text" -LogLevel Warn -Path "$($env:windir)\temp\logfile.log"

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


 if ( (test-path "$($env:windir)\ccm\logs\") ) {
    $logdir = "$($env:windir)\ccm\logs"
} else {
    $logdir = "$($env:windir)\temp"
}

$logfile = "$($logdir)\Script_Update365Channel.log"

Write-LogFile -Message "Beginning operation" -LogLevel Information -Path $logfile
Write-Verbose "Logging Output to $logfile"

#Update the release channel by setting the CDNBaseUrl registry value.
#list of channels is at:
#https://docs.microsoft.com/en-us/sccm/sum/deploy-use/manage-office-365-proplus-updates#change-the-update-channel-after-you-enable-office-365-clients-to-receive-updates-from-configuration-manager
$Channels = @{
    "Monthly"                   = "http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60";
    "SemiAnnual"                = "http://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114";
    "MonthlyTargeted"           = "http://officecdn.microsoft.com/pr/64256afe-f5d9-4f86-8936-8840a6a4f5be";
    "SemiAnnualTargeted"        = "http://officecdn.microsoft.com/pr/b8f9b850-328d-4355-9145-c59439a0c4cf";
}

#The normal update channels have a different procedure than the insider ring
if ($channel -ne "InsiderFast") {
    $ConfigRegPath = "hklm:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"

    if ((test-path -path $ConfigRegPath) -eq $false) {
        Write-LogFile -Message "Unable to locate registry key at $ConfigRegPath." -loglevel Error -Path $logfile
        Trow "Unable to locate registry key at $ConfigRegPath."
    } else {
        Write-Logfile -Message "Updating CDNBaseURL value in $ConfigRegPath to '$($Channels.$Channel)' - $Channel channel." -LogLevel Information -Path $logfile
        Try {
            Set-ItemProperty -Path $ConfigRegPath -Name "CDNBaseUrl" -Value $Channels.$channel -Force
        } Catch {
            Write-Logfile -Message "$($_.Exception.Message)" -LogLevel Error -Path $logfile
            Throw $_
        }
    }
}
else {
    $ConfigRegPath = "hklm:\SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate"
    if ((test-path -path $ConfigRegPath) -eq $false) {
        Write-LogFile -Message "Unable to locate registry key at $ConfigRegPath." -loglevel Error -Path $logfile
        Trow "Unable to locate registry key at $ConfigRegPath."
    } else {
        Write-LogFile -Message "Creating 'UpdateBranch' reg key with value 'InsiderFast' in $ConfigRegPath"  -LogLevel Information -Path $logfile
        Try {
            New-ItemProperty -Path $ConfigRegPath -Name "OfficeUpdate" -PropertyType string -Value "InsiderFast" -Force
        } Catch {
            Write-Logfile -Message "$($_.Exception.Message)" -LogLevel Error -Path $logfile
            Throw $_
        }
    }
}


#Make sure that OfficeC2rClient.exe exists
if ([string]::IsNullOrEmpty($OfficeC2rClientPath)) {
    $OfficeC2rClientPath = "$($env:CommonProgramFiles)\microsoft shared\ClickToRun\OfficeC2rClient.exe"
}

if ((Test-path $OfficeC2rClientPath) -eq $false) {
    Write-logfile -LogLevel Error -Path $logfile -message "Unable to validate that $($OfficeC2rClientPath) exists. Will exit."
    Throw "Unable to locate OfficeC2rClient.exe"
}

#Initialize a software update. This will force the channel to change.
$fargs = "/update user"

if ($ForceAppShutdown -eq 1) {$fargs = $fargs + " forceappshutdown=True"}
if ($DisplayLevel -eq 1) {$fargs = $fargs + " displaylevel=True"}
if ($UpdatePromptUser -eq 1) {$fargs = $fargs + " updatepromptuser=True"}

Write-LogFile -LogLevel Information -Path $logfile -message "Initializing O365 Client Update by running '$OfficeC2rClientPath $fargs"
Start-Process -FilePath $OfficeC2rClientPath -ArgumentList $fargs -Wait
Write-LogFile -LogLevel Information -Path $logfile -message "Process complete."