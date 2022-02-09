<#
.DESCRIPTION
This script will remediate common errors experienced with KMS activations. 
It is able to clear a manually specified KMS, set a new KMS and force Windows to activate.
All parameters operate independently and can be used in any combination.

The ClearExistingKMS and ActivateLicense parameters accept a 1 or 0 as values because this script is intended to be used
with MEMCM and it does not work well with switches or boolean parameters.

.PARAMETER KMSMachine
Host name of a KMS that is to be used for activation. 

.PARAMETER ClearExistingKMS
Set to '1' to clear a manually specified KMS and allow the device to search DNS instead

.PARAMETER ActivateLicense
Set to '1' to force a manual KMS activation for Windows

.EXAMPLE
#Set a new KMS and activate
Invoke-KMSWindowsActivation -KMSMachine "SomeNewKMS.Hey.local" -ActivateLicense 1

.EXAMPLE
#Clear the existing KMS and activate from a server discoverd by DNS
Invoke-KMSWindowsActivation -ClearExistingKMS 1 -ActivateLicense 1
#>


Param 
(
  [Parameter(Mandatory=$false)]
  [String]$KMSMachine = "",

  [Parameter(Mandatory=$false)]
  [ValidateSet(0,1)]
  [int]$ClearExistingKMS = 0,

  [Parameter(Mandatory=$false)]
  [ValidateSet(0,1)]
  [int]$ActivateLicense = 0
)



#Clear Existing KMS
if ($ClearExistingKMS -eq 1) {
    Try {
        $SoftwareLicensingService = Get-wmiobject SoftwareLicensingService
        $SoftwareLicensingService.ClearKeyManagementServiceMachine() | Out-Null
    } Catch {
        Throw "Unable to clear KMS. $($_.Exception.Message)"
    }
}

#Set specified KMS
if ([string]::IsNullOrEmpty($KMSMachine) -eq $false) {
    $test = Test-NetConnection -ComputerName $KMSMachine -Port 1688
    if ($test.TcpTestSucceeded -eq $true) {
        Try {
            $SoftwareLicensingService = Get-wmiobject SoftwareLicensingService
            $SoftwareLicensingService.SetKeyManagementServiceMachine($KMSMachine) | Out-Null
        } Catch {
            Throw "Unable to update KMS host. $($_.Exception.Message)"
        }
    } else {
        Throw "Unable to reach KMS host $KMSMachine on port 1688"
    }
}


#Activate detected windows products if requested
if ($ActivateLicense -eq 1) {
    $products = @(Get-WmiObject -query "Select * from SoftwareLicensingProduct where name like '%Windows%' and LicenseStatus <> 0")

    if ($Products.count -le 0) {
        Return "No Products found to license"
    }

    #Keep track of status
    $Licensed = @()
    $Failed = @()

    #Try to license each product found that doesn't have a status of 0
    Foreach ($product in $products) {
        Try {
            $product.Activate() | out-null
            $Licensed += $product
        } Catch {
            $failed += $product
        }
    }

    $ReturnObj = [PSCustomObject]@{
        Licensed = $Licensed
        Failed = $Failed
    }

    return $ReturnObj
}