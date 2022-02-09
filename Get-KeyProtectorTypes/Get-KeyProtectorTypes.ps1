Try {
    Import-module Bitlocker -DisableNameChecking
} Catch {
    Throw "Failed to import BitLocker Module $($_.Exception.Message)"
}

Try {
    $Volumes = @(Get-BitLockerVolume)
} Catch {
    Throw "Failed to get BitLocker Volumes $($_.Exception.Message)"
}

if ($Volumes.count -eq 0) {    
    Throw "No Encrypted Volumes Found."
}


$KeyProtectors = @()
Foreach ($Volume in $Volumes) {

    Try {
        $volumeKeyprotectors = @($Volume.KeyProtector)
    } Catch {
        Throw "Unable to locate KeyProtector $($_.Exception.Message)"
    }

    if ($volumeKeyprotectors.count -eq 0) {
        $KeyProtectors += [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME;
            Volume = $Volume.MountPoint;
            KeyProtectorType = "None";
            VolumeStatus = $volume.VolumeStatus;
            EncryptionPercentage = $volume.EncryptionPercentage;
            ProtectionStatus = $volume.ProtectionStatus;

        } 
    }

    Foreach ($thisProtector in $volumeKeyprotectors) {        
        
        $KeyProtectors += [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME;
            Volume = $Volume.MountPoint;
            KeyProtectorType = $thisProtector.KeyProtectorType;
            VolumeStatus = $volume.VolumeStatus;
            EncryptionPercentage = $volume.EncryptionPercentage;
            ProtectionStatus = $volume.ProtectionStatus;
        }
        
    }
}

Return $KeyProtectors