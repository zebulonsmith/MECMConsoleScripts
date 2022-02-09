#Read this!
#https://docs.microsoft.com/en-us/windows/client-management/mdm/using-powershell-scripting-with-the-wmi-bridge-provider

#First, find the Policy CSP object to be modified in the CSP documentation
#https://docs.microsoft.com/en-us/windows/client-management/mdm/policy-configuration-service-provider

#Next, find its reference in the WMI Bridge Provider documentation
#https://docs.microsoft.com/en-us/windows/win32/dmwmibridgeprov/mdm-bridge-wmi-provider-portal

Param (
    # Acknowledge that we're about to do a dumb
    [Parameter(Mandatory=$true)]
    [ValidateSet("YES")]
    [STRING]
    $ProfilesWillBeDeleted = "NO WAY"

)

$MDMNamespace = "root\cimv2\mdm\dmmap"

#region SharedPC settings
$sharedPC = Get-CimInstance -Namespace $MDMNamespace -ClassName "MDM_SharedPC"

#Enable the Account manager (must be applied first before the other configs)
$sharedPC.EnableAccountManager = $true

#Disable Shared PC Mode (must be applied second)
#$sharedPC.EnableSharedPCMode = $false

#Enable Domain Joined PCs and Guest Mode
$sharedPC.AccountModel = 2

#Delete profiles immediately on logoff
$sharedPC.DeletionPolicy = 0

#Require a password after the device wakes up
$sharedPC.SignInOnResume = $true

#Save changes
$sharedPC | Set-CimInstance

#endregion





#Logon options
$properties = @{
    ParentID = "./Vendor/MSFT/Policy/Config"; #This will always be the same
    InstanceID = "WindowsLogon"; #The InstanceID is the name of the CSP
}

#Create a new CIM Instance for the CSP to configure using the Policy_config class
$WindowsLogon = New-CimInstance -Namespace $MDMNamespace -ClassName "MDM_Policy_Config01_WindowsLogon02" -Property $properties

$WindowsLogon = New-CimInstance -Namespace $MDMNamespace -ClassName "MDM_Policy_Config01_WindowsLogon02" -Property $properties

#Change a property
$WindowsLogon.EnableFirstLogonAnimation = 0
$WindowsLogon.DisableLockScreenAppNotifications = 1
$WindowsLogon.HideFastUserSwitching = 1

$WindowsLogon | Set-CimInstance