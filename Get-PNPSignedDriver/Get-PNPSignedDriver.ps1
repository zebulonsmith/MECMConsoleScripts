param (
    # Search by description
    [Parameter(mandatory=$false)]
    [string]
    $Description = "%",

    # Search by DeviceID
    [Parameter(mandatory=$false)]
    [string]
    $DeviceID = "%",

    # Search by DevicClass
    [Parameter(mandatory=$false)]
    [string]
    $DeviceClass = "%",

    # Search by DevicName
    [Parameter(mandatory=$false)]
    [string]
    $DeviceName = "%",
    
    # Search by driver version 
    [Parameter(mandatory=$false)]
    [string]
    $DriverVersion = "%",

    # Search by driver provider 
    [Parameter(mandatory=$false)]
    [string]
    $DriverProviderName = "%",

    # Search by HardwareID 
    [Parameter(mandatory=$false)]
    [string]
    $HardwareID = "%",

    # Search by INF name
    [Parameter(mandatory=$false)]
    [string]
    $InfName = "%",

    # Set to '1' to return the query that was executed along with the output
    [Parameter(mandatory=$false)]
    [ValidateRange(0,1)]
    [int]
    $EnableDebug = 0
)

$WMIQuery = @"
SELECT * from Win32_PNPSignedDriver

WHERE 
    Description like '$Description' 
    AND DeviceID like '$DeviceID'
    AND DeviceClass like '$DeviceClass'
    AND DeviceName like '$DeviceName'
    AND DriverVersion like '$DriverVersion'
    AND DriverProviderName like '$DriverProviderName'
    AND HardwareID like '$HardwareID'
    AND InfName like '$InfName'
"@


try {
    $PNPResult = Get-WmiObject -Query $WMIQuery | Select-object -property   "Caption", `
                                                                            "ClassGuid", `
                                                                            "CompatID", `
                                                                            "CreationClassName", `
                                                                            "Description", `
                                                                            "DeviceClass", `
                                                                            "DeviceID", `
                                                                            "DeviceName", `
                                                                            "DevLoader", `
                                                                            "DriverDate", `
                                                                            "DriverName", `
                                                                            "DriverProviderName", `
                                                                            "DriverVersion", `
                                                                            "FriendlyName", `
                                                                            "HardWareID", `
                                                                            "InfName", `
                                                                            "InstallDate", `
                                                                            "IsSigned", `
                                                                            "Location", `
                                                                            "Manufacturer", `
                                                                            "Name", `
                                                                            "PDO", `
                                                                            "Signer", `
                                                                            "Started", `
                                                                            "StartMode", `
                                                                            "Status", `
                                                                            "SystemCreationClassName", `
                                                                            "SystemName"

}
catch {
    Return "Failed to query WMI for: `n$WMIQuery`n$($_.exception.message)"
}


if ($EnableDebug -eq 1) {
    $ReturnObj =  [PSCustomObject]@{
        Result = $PNPResult
        Query = $WMIQuery
    }
    
    Return $ReturnObj
} else {
    Return $PNPResult
}