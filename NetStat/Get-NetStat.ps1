
#Returns active TCP connections
$TCPConnections = Get-NetTCPConnection



Foreach ($con in $TCPConnections) {
    $proc = Get-Process -Id $con.OwningProcess

    $con | Add-Member -MemberType NoteProperty -Name Process_Name -Value $proc.Name
    $con | Add-Member -MemberType NoteProperty -Name Process_Description -Value $proc.Description
    $con | Add-Member -MemberType NoteProperty -Name Process_Path -Value $proc.Path
    $con | Add-Member -MemberType NoteProperty -Name Process_FullInfo -Value $proc
}

Return $TCPConnections