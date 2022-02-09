Param (
    # Action to take on the filter
    [Parameter(Mandatory=$true)]
    [ValidateSet("GetStatus","Enable","Disable")]
    [String]
    $FilterAction,

    # Forces a restart after enable/disable
    [Parameter(Mandatory=$false)]
    [Validateset("YES","NO")]
    [STRING]
    $ForceRestart = "NO",

    # Log file path
    [Parameter(mandatory=$false)]
    [string]
    $logpath = "$($env:windir)\ccm\logs\script_ManageUWFFilter.log"

)


#region Initialize some things

#logging
Start-Transcript -Path $logpath -Append
$InformationPreference = "Continue"


#UWF WMI Namespace
$UWFNamespace = "root\standardcimv2\embedded"


#Get the WMI object for the filter
Try {
    Write-Output "Connecting to UWF WMI CLass"
    $objUWFInstance = Get-WMIObject -namespace $UWFNamespace -class UWF_Filter
} Catch {
    Write-Error -Message "$($_.Exception.Message)"
    Stop-Transcript
    Throw $_
}

If ($FilterAction -eq "GetStatus") {
   Stop-Transcript
   Return $objUWFInstance | Select-Object "CurrentEnabled", "NextEnabled"
}

if ($FilterAction -eq "Enable") {
     Try {
        Write-Output "Enabling UWF"
        $objUWFInstance.Enable()
    } Catch {
        Write-Error -Message "$($_.Exception.Message)"
        Stop-Transcript
        Throw $_
    }
    
    
    if ($ForceRestart -eq "YES") {
        Write-Output "Filter Enabled. Rebooting"
        $objUWFInstance.RestartSystem()
    } else {
        Write-Output "Filter will be enabled on next reboot."
    }

    Stop-Transcript
    Return "SUCCESS"
}

if ($FilterAction -eq "Disable") {
     Try {
        Write-Output "Disabling UWF"
        $objUWFInstance.Disable()
    } Catch {
        Write-Error -Message "$($_.Exception.Message)"
        Stop-Transcript
        Throw $_
    }
    
    
    if ($ForceRestart -eq "YES") {
        Write-Output "Filter Disabled. Rebooting"
        $objUWFInstance.RestartSystem()
    } else {
        Write-Output "Filter will be disabled on next reboot."
    }

    Stop-Transcript
    Return "SUCCESS"
}