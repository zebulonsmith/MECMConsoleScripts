<#
.DESCRIPTION
Removes all RSAT tools installed via Add-WindowsCapability. Windows 10 1809 and up.


.EXAMPLE
Remove-RSAT.ps1

#>



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
         [ValidateSet("Logfile", "Warning", "Information")]
         [string]$LogLevel = "Information",
         
         [Parameter(Mandatory = $True)]
         [string]$Path 
     )
     
     #Get a pretty date string
     $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
     
     # Write message to Logfile, warning, or verbose pipeline and specify $LevelText 
     switch ($LogLevel)
     {
         'Logfile' {
             Write-Logfile $Message
             $LevelText = 'Logfile:'
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
 
 

 #Set up our logging dir. We're going to try writing to the default ccm client log dir, if that doesn't work, write to c:\windows\temp
if ( (test-path "$($env:windir)\ccm\logs\") ) {
    $logdir = "$($env:windir)\ccm\logs\"
} else {
    $logdir = "$($env:windir)\temp\"
}
 
$logfile = "$($logdir)\Script_RemoveRSAT.log"
 
Write-LogFile -Message "Beginning operation" -LogLevel Information -Path $logfile

$RSATFeatures = Get-WindowsCapability -Name "*RSAT*" -online | Where-Object {$_.Status -eq "Installed"}

Foreach ($rsat in $RSATFeatures) {

    Try {
        Write-Logfile -message "Removing $($rsat.name)" -loglevel Information -path $logfile
        Remove-WindowsCapability -Name $rsat.name -online | Out-null

    } Catch {
        Write-Logfile -message "Failed to remove $($rsat.name)" -loglevel Warning -path $logfile

    }
}

Write-LogFile -Message "Operation completed." -LogLevel Information -Path $logfile