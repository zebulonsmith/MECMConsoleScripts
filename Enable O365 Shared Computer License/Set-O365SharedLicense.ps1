<#
.DESCRIPTION
Enabled Office 365 Shared License

.PARAMETER EnableSharedLicensing
Set to 0 to disable shared licensing, or 1 to enable.

.EXAMPLE
Enable-O365SharedLicense

#>

Param (
    # Enable Shared License
    [Parameter(Mandatory=$true)]
    [ValidateRange(0,1)]
    [int]
    $EnableSharedLicense

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
     
     # Write message to Logfile, warning, or LogfiWrite-LogFile -LogLevel Message -Path $logfile -message pipeline and specify $LevelText 
     switch ($Level)
     {
         'Logfile' {
             Write-Logfile $Message
             $LevelText = 'ERROR:'
         }
         'Warning' {
             Write-Warning $Message
             $LevelText = 'WARNING:'
         }
         'Info' {
             Write-Logfile $Message
             $LevelText = 'INFORMATION:'
         }
     }
     
     "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
 }
 
 if ( (test-path "$($env:windir)\ccm\logs\") ) {
    $logdir = "$($env:windir)\ccm\logs\"
} else {
    $logdir = "$($env:windir)\temp\"
}

$logfile = "$($logdir)\Script_SetSharedLicense.log"

Write-LogFile -Message "Beginning operation" -LogLevel Information -Path $logfile

#Verify that Shared Computer Licensing value exists in HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration
$regpath = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
Try {
    $ItemProperty = Get-ItemProperty -Path $regpath -Name "SharedComputerLicensing"
    Write-LogFile -Message "Verified that SharedComputerLicensing exists at $regpath" -Path $logfile -LogLevel Information
} catch {
    Write-LogFile -Message "Unable to read SharedComputerLicensing value from $regpath." -Path $logfile -LogLevel Error
    Throw $_.Exception.Message
}

#Set the value to 1
Write-LogFile -message "Setting SharedComputerLicensing to $EnableSharedLicense" -LogLevel Error -Path $logfile
Try {
    Set-ItemProperty -path $regpath -name "SharedComputerLicensing" -Value $EnableSharedLicense
    Write-LogFile -Message "Success" -Path $logfile -LogLevel Information
} Catch {
    Write-LogFile -Message "Failed to change registry value. `n $_.exception.message" -LogLevel Error -Path $logfile
    Throw $_.exception.message
}