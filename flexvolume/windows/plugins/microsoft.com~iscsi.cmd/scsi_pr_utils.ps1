#checks for dependencies
(Get-Command DoCommandValidateErrorCode -CommandType Function ) | Out-Null
test-path $iscsiHelper | Out-Null


$exclusiveReservationType = 3
$exclusiveRegistrantsReservationType = 6

Function GetReservations($diskNumber)
{
    $command = "$iscsiHelper getReservations -disk $diskNumber"
    $output = DoCommandValidateErrorCode $command
    [uint32]$reservationCount = $output.Length -2

    $reservations = @()
    for($i =2; $i -lt $output.length; $i++)
    {
        $line = $output[$i]
        $key, $type, $scope, $address = $line.Split(',',4)

        $reservations+= @{'key'=$key; 'type'=$type;'scope'=$scope}
    }
    if($reservationCount -gt 1)
    {
        throw "Error more than 1 reservations for disk $diskNumber"
    }
    if($reservationCount -eq 1)
    {
        return $reservations[0]
    }
    return $null
}

Function GetRegistrations($diskNumber)
{
    $command = "$iscsiHelper getRegistrations -disk $diskNumber"
    $output = DoCommandValidateErrorCode $command
    $registrations = @()
    for($i =1; $i -lt $output.length; $i++)
    {
        $registrations+=$output[$i]
    }

    return ,$registrations
}

Function RegisterDisk($diskNumber, $registrationNumber)
{   
    DoCommandValidateErrorCode "$iscsiHelper register -disk $diskNumber -key $registrationNumber" | Out-Null
}

Function ReserveDiskCommon($diskNumber, $reservationNumber, $type)
{   
    DoCommandValidateErrorCode "$iscsiHelper reserve -disk $diskNumber -key $reservationNumber -scope 0 -type $type" | Out-Null
}
Function PreemptDiskCommon($diskNumber, $reservationNumber, $servicekey, $type)
{   
    DoCommandValidateErrorCode "$iscsiHelper preempt -disk $diskNumber -key $reservationNumber -servicekey $servicekey -scope 0 -type $type" | Out-Null
}
Function ReleaseDisk($diskNumber, $serviceKey, $type, $scope)
{   
    DoCommandValidateErrorCode "$iscsiHelper release -disk $diskNumber -key $serviceKey -scope $scope -type $type" | Out-Null
}

Function ReserveDiskExclusive($diskNumber, $reservationNumber)
{
    ReserveDiskCommon $diskNumber $reservationNumber $exclusiveReservationType 
}

Function ReserveDiskRegistrantsExclusive($diskNumber, $reservationNumber)
{
    ReserveDiskCommon $diskNumber $reservationNumber $exclusiveRegistrantsReservationType
}

Function PreemptDiskExclusive($diskNumber, $reservationNumber, $serviceKey)
{
    PreemptDiskCommon $diskNumber $reservationNumber $serviceKey $exclusiveReservationType
}
Function PreemptDiskRegistrantsExclusive($diskNumber, $reservationNumber, $serviceKey)
{
    PreemptDiskCommon $diskNumber $reservationNumber $serviceKey $exclusiveRegistrantsReservationType
}