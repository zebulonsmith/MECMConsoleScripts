<#
    Read this!
    https://docs.microsoft.com/en-us/windows/client-management/mdm/using-powershell-scripting-with-the-wmi-bridge-provider

    First, find the Policy CSP object to be modified in the CSP reference documentation
    https://docs.microsoft.com/en-us/windows/client-management/mdm/policy-configuration-service-provider

    Next, find its reference in the WMI Bridge Provider documentation
    https://docs.microsoft.com/en-us/windows/win32/dmwmibridgeprov/mdm-bridge-wmi-provider-portal

    There's no great way to search for a setting in docs.microsoft.com, but the Windows Configuration Designer has a search function.
    It can be used as a starting point to find the relevant CSP.

    The method used to change configurations varies based on the CSP.
    Most do not have a CIM instance present until is is created but some, such as MDM_SharedPC are already present.
    Refer to the CSP Reference for info.

    Remember to run the script as the system account, it won't work otherwise.

    This example will configure the following:
    SharedPC
        -Enable Guest Accounts
        -Delete user profiles immediately after logoff
        -Require a password to resume from sleep
        -Does not enable full Shared PC mode, which comes with some additional configurations when set to True

    WindowsLogon
        -Disable first time login animation
        -Hide fast user switching

    Authentication
        -Enable fast first signin (Preview feature)

    Local Security Options
        -Don't show the last username at login
#>


$MDMNamespace = "root\cimv2\mdm\dmmap"

#region SharedPC settings
$sharedPC = Get-CimInstance -Namespace $MDMNamespace -ClassName "MDM_SharedPC"

#Enable the Account manager (must be applied first before the other configs)
$sharedPC.EnableAccountManager = $true

#Disable Shared PC Mode (must be applied second)
#In this example, we want to clean up user profiles and enable guests, but do not want the other settings that Shared PC mode enables.
$sharedPC.EnableSharedPCMode = $false

#Enable Domain Joined PCs and Guest Mode
$sharedPC.AccountModel = 2

#Delete profiles immediately on logoff
$sharedPC.DeletionPolicy = 0

#Require a password after the device wakes up
$sharedPC.SignInOnResume = $true

#Save changes
$sharedPC | Set-CimInstance

#endregion





#Configure Logon
#https://docs.microsoft.com/en-us/windows/win32/dmwmibridgeprov/mdm-policy-config01-windowslogon02
#https://docs.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowslogon
#Disable first login animation
#Disable Lock Screen Notifications
#HideFastUserSwitching
$WindowsLogonClassName = "MDM_Policy_Config01_WindowsLogon02"
$WindowsLogonproperties = @{
    ParentID = "./Vendor/MSFT/Policy/Config"; #This will almost always be the same. Refer to the CSP reference
    InstanceID = "WindowsLogon"; #The InstanceID is USUALLY the name of the CSP and can be found on the CSP reference page
    EnableFirstLogonAnimation = 0;
    #DisableLockScreenAppNotifications = "1"; This setting kind of just doesn't work. Can't set it with WCD or here. Maybe a bug?
    HideFastUserSwitching = 1;
}

New-CimInstance -Namespace $MDMNamespace -ClassName $WindowsLogonClassName -Property $WindowsLogonproperties

#Configure Authentication
#https://docs.microsoft.com/en-us/windows/win32/dmwmibridgeprov/mdm-policy-config01-authentication02
#https://docs.microsoft.com/en-us/windows/client-management/mdm/policy-csp-authentication
#NOTE: THIS IS IN PREVIEW (And has been for a while). In theory, it makes login faster on a device joined to AAD
$AuthenticationClassName = "mdm_policy_config01_authentication02"
$Authenticationproperties = @{
    ParentID = "./Vendor/MSFT/Policy/Config";
    InstanceID = "Authentication";
    EnableFastFirstSignin = 1;
}

New-CimInstance -Namespace $MDMNamespace -ClassName $AuthenticationClassName -Property $Authenticationproperties

#Configure Security Options
#Don't show the last user logged in
#https://docs.microsoft.com/en-us/windows/win32/dmwmibridgeprov/mdm-policy-config01-localpoliciessecurityoptions02
#https://docs.microsoft.com/en-us/windows/client-management/mdm/policy-csp-localpoliciessecurityoptions#localpoliciessecurityoptions-interactivelogon-donotdisplaylastsignedin

$SecurityOptionsClassName = "MDM_Policy_Config01_LocalPoliciesSecurityOptions02"

$SecurityOptionsProperties = @{
    ParentID = "./Vendor/MSFT/Policy/Config";
    InstanceID = "LocalPoliciesSecurityOptions";
    InteractiveLogon_DoNotDisplayLastSignedIn = 1;
}

New-CimInstance -Namespace $MDMNamespace -ClassName $SecurityOptionsClassName -Property $SecurityOptionsProperties
