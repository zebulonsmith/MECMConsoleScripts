
Param (
    # Enable filter now
    [Parameter(Mandatory=$false)]
    [Validateset("YES","NO")]
    [STRING]
    $EnableFilter = "NO",

    # Forces a restart after enable/disable
    [Parameter(Mandatory=$false)]
    [Validateset("YES","NO")]
    [STRING]
    $ForceRestart = "NO",

    # Log file path
    [Parameter(mandatory=$false)]
    [string]
    $logpath = "$($env:windir)\ccm\logs\script_ConfigureUWF.log"

)



#region Initialize some things

#logging
$InformationPreference = "Continue"

#UWF WMI Namespace
$UWFNamespace = "root\standardcimv2\embedded"

#Make sure uwfmgr.exe exists
$UwfmgrPath = "$($env:windir)\system32\uwfmgr.exe"
Write-Output "Testing for the presence of uwfmgr.exe at '$UwfmgrPath'"
If ( !(test-path -Path $UwfmgrPath) ) {
    Write-Error "$UwfmgrPath does not exist, aborting."
    Throw "File not found."
}


if ($EnableFilter -eq "YES") {
    Try {
        Write-Output "Enabling UWF_Filter"
        $UWF_Filter = Get-WMIObject -namespace $UWFNamespace -class UWF_Filter
        $UWF_Filter.Enable()
    } Catch {
        Write-Error -Message "$($_.Exception.Message)"
        Stop-Transcript
        Throw $_
    }
}

Try {
    Write-Output "Configuring UWF_Overlay"
    $UWF_Overlay = Get-WmiObject -Namespace $UWFNamespace -Query "Select * from UWF_OverlayConfig where CurrentSession = 'false'"
    $UWF_Overlay.SetType(1)
    $UWF_Overlay.SetMaximumSize(4096)
} Catch {
    Write-Error -Message "$($_.Exception.Message)"
    Stop-Transcript
    Throw $_
}




#region add volumes
Try {
    Write-Output "Searching for local disks."
    $volumes = (Get-WmiObject win32_logicaldisk -filter {DriveType=3}).DeviceID
} Catch {
    Write-Error -Message "$($_.Exception.Message)"
    Stop-Transcript
    Throw $_
}



#Enable filter for all local disks. 
#Getting this to work with the native WMI implementation is.... challenging. For now, we're going to use the uwfmgr.exe tool to add volumes.
Foreach ($volume in $volumes) {
    try {
        Write-Output "Adding volume $volume by executing '$UwfmgrPath volume protect $volumes"
        Invoke-Expression  "$UwfmgrPath volume protect $volume"
    } Catch {
        Write-Error -Message "$($_.Exception.Message)"
        Stop-Transcript
        Throw $_
    }
}



#region Set up exclusions

#Registry
$RegExclusions =@(
    "HKLM\SOFTWARE\Microsoft\CCM",
    "HKLM\SOFTWARE\Microsoft\SMS",
    "HKLM\Software\Microsoft\WindowsNT\CurrentVersion\WinLogon",
    "HKLM\System\CurrentControlSet\Services\smstsmgr"
)


Try {
    Write-Output "Creating UWF_RegistryFilter WMI Object"
    $objRegExclusion = Get-WmiObject -Namespace $UWFNamespace -query "Select * from UWF_RegistryFilter where currentSession = 'False'"    
} Catch {
    Write-Error -Message "$($_.Exception.Message)"
    Throw $_
}

Foreach ($thisRegExclusion in $RegExclusions) {
    Try {
        Write-Output "Adding registry exclusion for $thisRegExclusion"
        $objRegExclusion.AddExclusion($thisRegExclusion)
    } Catch {
        if ($_.exception.hresult -eq "-2146233087") {
            Write-Warning "An Exception for $thisRegExclusion already exists"
        } else {
            Write-Error -Message "$($_.Exception.Message)"
            Throw $_
        }
    }
}


#Files
$FileExclusions = @(
    "C:\windows\system32\ccm",
    "C:\windows\ccm",
    "C:\windows\ccmcache",
    "C:\windows\system32\wbem",
    "C:\_smstasksequence",
    "C:\windows\bootstat.dat",
    "C:\windows\regfdata"
)

foreach ($thisFileExclusion in $FileExclusions) {
    try {
        Write-Output "Adding file exclusion by executing '$UwfmgrPath file add-exclusion $thisFileExclusion"
        Invoke-Expression  "$UwfmgrPath file add-exclusion $thisFileExclusion"
    } catch {
        Write-Error -Message "$($_.Exception.Message)"
        Throw $_
    }
}

#endregion




Write-Output "SUCCESS"
If ($ForceRestart -eq "YES") {
    Restart-Computer
}