<#
.Description
This script is meant to be used as a wrapper for the dsregcmd.exe utility from within the Configuration Manager console.
It's used to manage and troubleshoot device's AAD Hybrid Join.

.Parameter Action
Join - Instructs a device to join AAD
Leave - Disjoin AAD
Status - Returns the current AAD join status
#>

Param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("Join","Leave", "StatusOnly")]
    [STRING]$Action = "Status",

    [Parameter(Mandatory=$false)]
    [ValidateRange(0,1)]
    [Int]$SimpleOutput = 0
)

$objJoin = "None"

#Attempt to join if requested
if ($Action -eq "Join") {
    $join = dsregcmd /join /debug

    $objJoin = [pscustomobject]@{
        Property = "JoinDebugOutput"
        Status   = $join
    }

    Start-Sleep -Seconds 300
}

#Attempt to leave if requested
if ($Action -eq "Leave") {
    $join = dsregcmd /leave /debug

    $objJoin = [pscustomobject]@{
        Property = "JoinDebugOutput"
        Status   = $join
    }

    Start-Sleep -Seconds 300
}

#Get the current status
$dsregstatus = dsregcmd /status


$TrimmedOutput = ($dsregstatus | where-object {$_ -like "*:*"}).replace(" : ","~") |
        ForEach-Object {$_.Trim() }

$objstatus = [PSCustomObject]@{}

Foreach ($thisStatus in $TrimmedOutput) {
    $tempStatus = $thisStatus | ConvertFrom-String -Delimiter "~"
    $objstatus | Add-Member -MemberType NoteProperty -Name $tempStatus.P1 -Value $tempStatus.P2
}

#Create a new object that tells us if the device is joined, join status details and the output of dsregcmd /join or /leave if it was specified
$objReturn = [PSCustomObject]@{
    AzureADJoined = $objstatus.AzureAdJoined
    StatusDetail = $objstatus
    ActionDetail = $objJoin
}

#Exit Cleanly
if ($SimpleOutput -eq 1) {
    Return ($objReturn | Select-Object -Property azureadjoined)
} else {
    return $objReturn
}

