#checks for dependencies
(Get-Command Log -CommandType Function ) | out-null

Function RegetDisk($disk)
{
    get-disk -Number $disk.Number
}

Function GetVolumesForDisk($disk)
{
    return @($disk | get-partition | get-volume)
}

Function InitalizeDiskIfNecessary($disk)
{
    if($disk.PartitionStyle -eq 'RAW')
    {
        Log "Initializing disk number $($disk.number)"
        Initialize-Disk -Number $disk.Number | Out-Null
    }
}
function SetDiskOffline($disk, $offline)
{
    if($disk.IsOffline -ne $offline)
    {
        Log "Changin state of disk number $($disk.number) to offline $offline"
        $disk | Set-Disk -IsOffline $offline | Out-Null
    }
}
function SetDiskReadOnly($disk, $readOnly)
{
    if($disk.IsReadOnly -ne $readOnly)
    {
        Log "Changin state of disk number $($disk.number) to readonly $readOnly"
        $disk | Set-Disk -IsReadOnly $readOnly | Out-Null
    }
}

Function EnsureDiskIsReadWriteOnline($disk)
{
    SetDiskOffline $disk $false
    SetDiskReadOnly $disk $false
}