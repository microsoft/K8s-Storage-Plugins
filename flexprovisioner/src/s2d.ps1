function CreateShare(
    [string] $name,
    [uint64] $requestSize,
    [string] $clustername,
    $cimsession,
    [string] $shareServer,
    [ValidateSet("CSVFS_ReFS","CSVFS_NTFS")] 
    [string] $fsType,
    [string] $storagePoolFriendlyName,
    [string[]] $storageTierFriendlyNames,
    [string[]] $storageTierRatios,
    [string[]] $fullAccessUsers
)
{
    $storageTierFriendlyNames = $storageTierFriendlyNames -split ","
    if(-not $storageTierRatios){
        $storageTierRatios = "1"
    }
    else {
        $storageTierRatios = $storageTierRatios -split ","        
    }
    $storageTierSizes = $storageTierRatios | %{[uint64] (([double]$_) * $requestSize) }

    try{
        #get-volume -FileSystemLabel $name -CimSession $session -ErrorAction Stop
        $v = Get-VirtualDisk -FriendlyName $name -CimSession $session -ErrorAction Stop
        #ensure that there is a volume on the partition
        $empty = $v |  get-disk | %{( $_ | Get-Partition )[1]} | Get-Volume | GetFirst -message "volume wasn't created"
    }catch{
        $v = New-Volume -FriendlyName $name -CimSession $session -FileSystem $fsType -StoragePoolFriendlyName $storagePoolFriendlyName -StorageTierFriendlyNames $storageTierFriendlyNames -StorageTierSizes $storageTierSizes -ErrorAction SilentlyContinue     2>&1 
    }

    $shares = Get-SmbShare -CimSession $cimSession -ScopeName $shareServer -ErrorAction Stop 2>&1
    $share = $shares | ?{$_.Name -eq $name}
    if(-not $share)
    {
        $v = Get-VirtualDisk -FriendlyName $name -CimSession $session -ErrorAction Stop | GetFirst -message "couldnt find volume named $name"
        #get partition that holds CSV
        #$csvpath = ($v | get-disk | Get-ClusterSharedVolume -cluster $clustername).SharedVolumeInfo[0].FriendlyVolumeName
        $partition = ($v | get-disk | get-partition )[1]
        $csvPath = $partition.AccessPaths | ?{$_.contains("ClusterStorage")}
        $share = New-SmbShare -Name $name -Path $csvpath -ScopeName $shareServer -CimSession $session -FullAccess $fullAccessUsers -ErrorAction Stop 2>&1
    }
}

function RemoveShare([string]$shareServer, [string]$name, $cimSession)
{
    $shares = Get-SmbShare -CimSession $cimSession -ScopeName $shareServer -ErrorAction Stop 2>&1
    $share = $shares | ?{$_.Name -eq $name}
    if($share)
    {
        Remove-SmbShare -CimSession $cimSession -ScopeName $shareServer -Name $name -Force -ErrorAction Stop 2>&1
    }

    Get-VirtualDisk -CimSession $cimSession -FriendlyName $name | Remove-VirtualDisk -Confirm:$false
}

function supports_s2d($options)
{
    return [bool] $options.parameters.s2dStoragePoolFriendlyName
}

function provision_s2d($options)
{
    $serverName = $options.parameters.s2dServerName 
    $shareServer = $options.parameters.s2dShareServer
    $secret = $options.parameters.smbSecret
    $name = $options.name
    $requestSize = ConvertKubeSize $options.volumeClaim.spec.resources.requests.storage
    $storagePoolFriendlyName = $options.parameters.s2dStoragePoolFriendlyName
    $fsType = $options.parameters.s2dFsType
    $storageTierFriendlyNames = $options.parameters.s2dStorageTierFriendlyNames
    $storageTierRatios = $options.parameters.s2dStorageTierRatios -split ","
    $fullAccessUsers = $options.parameters.s2dFullAccessUsers -split ","

    $path = '\\' + $shareServer + '\' + $name

    if(-not $serverName)
    {
        $serverName = $shareServer
    }
    $session = New-CimSession -ComputerName $servername 
    CreateShare -name $name `
                -requestSize $requestSize `
                -clustername $serverName `
                -CimSession $session `
                -shareServer $shareServer `
                -fsType $fsType `
                -storagePoolFriendlyName $storagePoolFriendlyName `
                -storageTierFriendlyNames $storageTierFriendlyNames `
                -storageTierRatios $storageTierRatios `
                -fullAccessUsers $fullAccessUsers
                        
    $ret = @{"metadata" = @{
                "labels" =@{
                    "proto" = "smb" } }; 
            "spec"= @{
                "flexVolume" = @{
                    "driver" = "microsoft.com/smb.cmd"; 
                    "secretRef" = @{
                        "name" = $secret };
                    "options" = @{
                        "source" = $path;
                        "s2dServerName" = $serverName;
                        "s2dShareServer"= $shareServer; } } } }
                        
    return $ret
}

function delete_s2d($options)
{
    RemoveShare `
        -shareServer $options.volume.spec.flexVolume.options.s2dShareServer `
        -name $options.volume.metadata.name `
        -cimSession $(New-CimSession $options.volume.spec.flexVolume.options.s2dServerName)
}