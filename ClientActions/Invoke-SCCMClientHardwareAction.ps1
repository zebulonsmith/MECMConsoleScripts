#Get the client version so that we know whether we need to turn the output into JSON
[Version]$CMClientVersion = (Get-WMIObject -Namespace root\ccm -Class SMS_Client).ClientVersion
if ($CMClientVersion -lt [Version]"5.00.8634.1010") {
    $NeedToConvertJSON = $true
} else {
    $NeedToConvertJSON = $false
}




$wmi = Invoke-WMIMethod -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule “{00000000-0000-0000-0000-000000000001}” -erroraction SilentlyContinue



if ($wmi) {
    $status = "SUCCESS"
} else {
    $status = "ERROR"
}

if ($NeedToConvertJSON) {   
    Return ($status | ConvertTo-Json) 
} else {
    Return $status
}