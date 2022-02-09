#Work in Progress
#This script is meant to trigger the execution of a Task Sequence with a 'Required' Deployment type

Param (
    # Task Sequence Name
    [Parameter(Mandatory=$true)]
    [String]
    $TaskSequenceName,

    # A little extra validation
    [Parameter(Mandatory = $true)]
    [validateSet("YES")]
    [STRING]
    $IUnderstandThatThisDeviceWillBeReimaged

)

#WMI Namespaces that will be used
$CCMPolicyNamespace = "root\ccm\policy\machine\actualconfig"
$CCMSchedulerNamespace = "root\ccm\scheduler"

#Get the Software Distribution object for the Task Sequence. 
#We need to get the AdvertisementID from this property so that we can find the CCM_TaskSequence object
$qry = "Select * from CCM_SoftwareDistribution where PKG_Name = '$TaskSequenceName'"

Try {
    $TSDistObject = Get-CimInstance -Query $qry -Namespace $CCMPolicyNamespace
} Catch {
    Throw "Unable to query CCM_SoftwareDistribution WMI Object. $($_.Exception.message)"
}

if ($TSDistObject.PKG_Name -ne $TaskSequenceName) {
    Throw "Task Sequence Name mismatch."
}

#Leave if we don't find anything (Task Sequence probably isn't deployed to the device)
if ($null -eq $TSDistObject) {
    Return "Task Sequence $TaskSequenceName is not deployed to this device."    
}

#Get the CCM Task Sequence Deployment object so that we can determine how the deployment is currently configured and make changes
#We're going to set the 
$qry = "Select * from CCM_TaskSequence where ADV_AdvertisementID = '$($TSDistObject.ADV_AdvertisementID)' and PKG_Name = '$TaskSequenceName'"
$TSPolicyObj = Get-CimInstance -Query $qry -Namespace $CCMPolicyNamespace

#Set the deployment to "Always Rerun" and 'Required'
Try {
    $TSPolicyObj.ADV_RepeatRunBehavior = "RerunAlways"
    $TSPolicyObj.ADV_MandatoryAssignments = $true
    $TSPolicyObj | Set-CimInstance
} Catch {
    Throw "Unable to set values on CCM_TaskSequence object. $($_.Exception.Message)"
}

#Get the scheduling client object https://docs.microsoft.com/en-us/sccm/develop/reference/core/clients/client-classes/scheduling-client-wmi-classes
#The ScheduleID property is needed by the TriggerSchedule method that will kick off the Task Sequence
$qry = "Select * from CCM_Scheduler_History where ScheduleID like '%$($TSDistObject.PKG_PackageID)%'"
$ScheduleObj = Get-CimInstance -Query $qry -Namespace $CCMSchedulerNamespace
[STRING]$ScheduleID = $ScheduleObj.ScheduleID

if ([STRING]::IsNullOrEmpty($ScheduleID)) {
    Throw "Unable to find ScheduleID for Task Sequence $($TSDistObject.PKG_Name)"
}

#Trigger the deployment using the TriggerSchedule method of the SMS_Client class
#https://docs.microsoft.com/en-us/sccm/develop/reference/core/clients/client-classes/triggerschedule-method-in-class-sms_client
if ($IUnderstandThatThisDeviceWillBeReimaged -eq "YES") {
    Try {
        Invoke-CimMethod -Namespace "root\ccm" -Class "SMS_Client" -MethodName "TriggerSchedule" -Arguments @{sScheduleID = $ScheduleID}
        Return "Task Sequence Execution Triggered"
    } Catch {
        Throw "Failed to execute Task Sequence $($_.exception.message)"
    }
} else {
    Throw "Image deployment was not confirmed."
}