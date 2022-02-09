#Enables/Starts the Windows Update service

Try {
    Set-Service -Name "wuauserv" -StartMode Automatic
} Catch {
    Throw $_.Exception.Message
}

Try {
    Start-Service -Name "wuauserv" -Force

} catch {
    Throw $_.Exception.Message
}


$serv = Get-Service -Name "wuauserv"
if ($serv.StartType -ne "Automatic") {
    Throw "$($serv.StartType)"
}