$global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

$logSource = "KubeISCSI"
$FriendlyDiskName = "KubernetesISCSI"
$exeName = "iscsiHelper.exe"
$iscsiHelper = "$PSScriptRoot\$exeName"
$prFile = 'pr.txt'
#$logId =  Get-Random -Minimum 1

$prFmt = 2
$prRO = 1
$prWriteSmallestNumber = 10

. $PSScriptRoot\flexvolume.ps1
. $PSScriptRoot\disk_utils.ps1
. $PSScriptRoot\scsi_pr_utils.ps1


Filter EnsureOneNonException
{
    Param([ScriptBlock] $processor = {},
        [string] $message)
    Begin
    {
        $exceptions = @();
        $foundItem = $false;
    }
    Process
    {
        try
        {
            invoke-command -scriptblock $processor -argumentlist $_ -ErrorAction stop
            $foundItem = $true
        }
        catch
        {            
            $exceptions += $_
        }
    }
    End
    {
        if(-not $foundItem)
        {
            if($message)
            {
                throw $message
            }
            if($exceptions.Length -ne 0)
            {
                throw $exceptions[0]
            }
        }
    }
}

#connects if necessary
Function GetPortal(
    $targetPortal,
    $port,
    $authType,
    $discoveryChapUsername,
    $discoveryChapSecret
)
{    
    Log "Connecting to iscsi portal $targetPortal"
    $newPortal = 'param($targetPortal) New-IscsiTargetPortal -TargetPortalAddress $targetPortal'
    if($port)
    {
        Log "using port $port"
        $newPortal = $newPortal + " -TargetPortalPortNumber $port"
    }
    if($discoveryChapSecret)
    {
        Log "using discovery secrets"
        $newPortal = $newPortal + " -AuthenticationType $authType -ChapUsername $discoveryChapUsername -ChapSecret $discoveryChapSecret"
    }
    DebugLog "full command to portal is: $newportal"
    
    DoCommand $newPortal $true @($targetPortal)
}

Function ConnectTarget(
    $target,
    $portal,
    $iqn,
    $authType,
    $isMultiPathEnabled,
    $sessionChapUserName,
    $sessionChapSecret,
    $eatExceptions

)
{    
    #deal with racing connection attempts by just blindly connecting and ignoring errors
    #if there is an error & not connected 
    #try again and let that error bubble up
    $connectTarget = 'param($target) $target | Connect-IscsiTarget -reporttopnp $true' 
    $connectTarget +=" -TargetPortalAddress $($portal.TargetPortalAddress) -TargetPortalPortNumber $($portal.TargetPortalPortNumber)"
    if($sessionChapSecret)
    {
        Log "connecting with session secret"
        $connectTarget = $connectTarget + " -AuthenticationType $authType -ChapUsername $sessionChapUsername -ChapSecret $sessionChapSecret"
    }
    if($multiPathEnabled)
    {
        Log "connecting with multipath enabled"
        $connectTarget = $connectTarget + ' -IsMultipathEnabled $true'
    }
    if($eatExceptions)
    {
        $connectTarget = $connectTarget + ' -ErrorAction ignore'
    }
    DebugLog "full command to target is: $connectTarget"

    DoCommand -command $connectTarget -throw $true -objectList @($target) | Out-Null
}
Function GetTargetForPortals(
    $portals,
    $iqn
)
{
    # -IscsiTargetPortal parameter seems to be broken
    #$portals | EnsureOneNonException -processor { param($portal) (Get-IscsiTarget -IscsiTargetPortal $portal | ? {$_.NodeAddress -eq $iqn})} -message "did not find target $iqn" | select -first 1
    Get-IscsiTarget | ? {$_.NodeAddress -eq $iqn} | GetFirst -message "did not find target $iqn"
}
Function GetTargetConnections(
    $target,
    $portals,
    $iqn,
    $authType,
    $isMultiPathEnabled,
    $sessionChapUserName,
    $sessionChapSecret
)
{
    if(-not $target.IsConnected)
    {            
        Log "need to connect to target $iqn"
        #deal with racing connection attempts by just blindly connecting and ignoring errors
        #if we did not connect, try to connect again surfacing the first error
        foreach($portal in $portals)
        {
            #blindly connect
            ConnectTarget $target $portal $iqn $authType $isMultiPathEnabled $sessionChapUsername $sessionChapSecret $true
        }

        $target = GetTargetForPortals $portals $iqn
        if(-not $target.IsConnected)
        {
            Log "failed to connect to target the first time, will retry and throw error"
            $portals | EnsureOneNonException -processor { param($portal) ConnectTarget $target $portal $iqn $authType $isMultiPathEnabled $sessionChapUsername $sessionChapSecret $false } | Out-Null
        }
    }
    else
    {
        Log "target already connected to target  $iqn"
    }
    
    $target | Get-IscsiConnection
}

#valid authTypes are "NONE", "ONEWAYCHAP", "MUTALCHAP"
Function ConnectIscsi(  
    $targetAndPorts, 
    $iqn,
    $authType = "NONE",
    $port = $null,
    $sessionChapUsername = $null,
    $sessionChapSecret = $null,
    $discoveryChapUsername = $null,
    $discoveryChapSecret = $null,
    [bool] $multiPathEnabled = $false
)
{   
    $portals = $targetAndPorts | EnsureOneNonException -processor { param($target, $port) GetPortal $target $port $authType $discoveryChapUsername $discoveryChapSecret }
    
    $target = GetTargetForPortals $portals $iqn
    $connection = GetTargetConnections $target $portals $iqn $authType $isMultiPathEnabled $sessionChapUserName $sessionChapSecret | GetFirst "target does not seem to be connected to $iqn after attempts previously succeeded"
    
    Log "connected to target"
    return $connection
}

Function CreateVolumeIfNecessary($disk, $fsType)
{
    Update-Disk -number $disk.number
    EnsureDiskIsReadWriteOnline $disk
    InitalizeDiskIfNecessary $disk
    #fetch newest info
    $disk = RegetDisk $disk
    
    
    $volumes = GetVolumesForDisk $disk
    if(($volumes | ? {$_.FileSystemType -eq $fsType} | Measure-Object).count -eq 0)
    {
        Log "There are no volumes of type $fsType so creating a volume of type $fsType on disk $($disk.number)"
        if($volumes.length -ne 0)
        {
            Log "there are however currently existing volumes on the disk!"
        }
        New-Volume -Disk $disk -FileSystem $fsType -FriendlyName $FriendlyDiskName | Out-Null
    }
}

Function CountCharInString($str, $char)
{
    ($str.ToCharArray() | ? {$_ -eq $char} | Measure-Object).count
}

Function GetPr()
{
    [uint32]$pr = Get-Content -Path $prFile
    if(-not (($pr -gt 0) -and ($pr -le [uint32]::MaxValue)))
    {
        throw "pr is an invalid number ($pr)"
    }
    $pr
}

Function EnsurePrWriteFileExists()
{
    if(-not (test-path $prFile))
    {
        [uint32]$prNumber = Get-Random -Minimum $prWriteSmallestNumber -Maximum ([uint32]::MaxValue)
        Log "creating pr number ($prNumber) in file $prFile in $($PWD.path)"
        Out-File -Encoding ascii -NoClobber -NoNewline -InputObject $prNumber -FilePath $prFile
    }
}

function init()
{
    Log "init iscsi in folder $($PWD.path)"
    EnsurePrWriteFileExists

    #enable iscsi communcation & service
    Get-NetFirewallServiceFilter -Service msiscsi | Get-NetFirewallRule | Enable-NetFirewallRule | Out-Null
    Set-Service -Name msiscsi -StartupType Automatic | out-null
    Start-service msiscsi | out-null
}

Function GetTargetPort([string]$target)
{
    $port = $null
    #ipv6 without port at end
    $targetColonCount = (CountCharInString $target ':')
    $isFullQualifiedIPv6 = $targetColonCount -eq 7
    if(-not $isFullQualifiedIPv6)
    {
        if($targetColonCount -ne 0)
        {
            $port = $target -split ':' | select -last 1
            $target = $target.Substring(0, $target.LastIndexOf(':'))
        }
    }
    return $target, $port
}

Function GetDisks()
{
    $command = "$iscsiHelper IscsiSessions"
    
    $scriptBlock = [scriptblock]::Create($command)
    $disks = invoke-command  -ScriptBlock $scriptBlock | select -Skip 1
    $errorCode = $LASTEXITCODE 
    if($errorCode -ne 0)
    {
        throw "Error Getting iscsi sessions $errorCode"
    }
    $sessions = @()
    foreach($disk in $disks)
    {
        $diskId, $lun, $iqn = $disk.Split(",", 3)
        $sessions += @{"Id" = $diskId; "Lun" = $lun; "iqn" = $iqn}
    }
    return , $sessions
}
Function GetDiskNumberFromIqn($iqn, [string]$lun)
{
    $allDisks = GetDisks
    $disk = $allDisks | ? {($_.iqn -eq $iqn) -and ($_.Lun -eq $lun)}| GetFirst "did not enumerate disk for iqn $iqn lun $lun"
    $disk.Id
}

Function GetPhysicalDiskById($diskId)
{    
    $physicalDisk = (Get-PhysicalDisk | ? {$_.DeviceId -eq $diskId})| GetFirst "did find physical disk $diskId for iqn $iqn lun $lun"
    return $physicalDisk
}

Function GetDiskNumberFromIscsi($iscsiConnection, $lun)
{
    $session = $iscsiConnection | Get-IscsiSession
    return GetDiskNumberFromIqn $session.TargetNodeAddress $lun
}

Function GetPhysicalDisk($iscsiConnection, $lun)
{   
    $diskId = GetDiskNumberFromIscsi $iscsiConnection $lun
    return GetPhysicalDiskById $diskId
}

Function GetDiskByNumber($diskNumber)
{
    (get-disk -number $diskNumber)| GetFirst "did find disk for disk number $diskNumber"
}

Function GetDiskForPhysicalDisk($physicalDisk)
{
    GetDiskByNumber $physicalDisk.DeviceId
}
Function MakeDiskIdUnwrittable($diskId)
{
    $output = DoCommandValidateErrorCode "$iscsiHelper setAttributes -disk $diskId -readonly 1 -offline 1"
}

function mount_command($path, $options)
{
    $prWrite = GetPr    
    $sessionChapUsername = $null
    $sessionChapSecret = $null
    $discoveryChapUsername = $null
    $discoveryChapSecret = $null

    if($options.chapAuthDiscovery -eq "true")
    {
        $discoveryChapUsername = Base64Decode $options.'kubernetes.io/secret/discovery.sendtargets.auth.username'
        $discoveryChapSecret = Base64Decode $options.'kubernetes.io/secret/discovery.sendtargets.auth.password'
    }
    if($options.chapAuthSession -eq "true")
    {
        $sessionChapUsername = Base64Decode $options.'kubernetes.io/secret/node.session.auth.username'
        $sessionChapSecret = Base64Decode $options.'kubernetes.io/secret/node.session.auth.password'
    }

    $portals = @()
    $portals += $options.targetPortal
    if($options.portals)
    {
        $options.portals -split "," | % {$portals += $($_.trim())}
    }

    $isReadWrite = $options.'kubernetes.io/readwrite' -ne 'ro'
    mount_command_with_options `
        -path $path `
        -prWrite $prWrite `
        -portals $portals `
        -iqn $options.iqn `
        -lun $options.lun `
        -isReadWrite $isReadWrite `
        -fsType $options.'kubernetes.io/fsType' `
        -authType $options.authType `
        -sessionChapUsername $sessionChapUsername `
        -sessionChapSecret $sessionChapSecret `
        -discoveryChapUsername $discoveryChapUsername `
        -discoveryChapSecret $discoveryChapSecret
}

function mount_command_with_options(
    $path,
    $prWrite,
    [string[]]$portals,
    $iqn,
    $lun,
    $isReadWrite,
    $fsType,    
    $authType,
    $sessionChapUsername,
    $sessionChapSecret,
    $discoveryChapUsername,
    $discoveryChapSecret)
{
    Log "attempting to mount $iqn $lun to $path"
    $isMultiPath = ($portals.Length -gt 1)

    #run through all the nodes to setup 
    $targetAndPorts = @()
    foreach($portal in $portals)
    {
        $target, $port = GetTargetPort $portal
        $targetAndPorts += ,($target, $port)
    }
    $connection = ConnectIscsi -targetAndPorts $targetAndPorts -iqn  $iqn -authType $authType -multiPathEnabled $isMultiPath  -sessionChapUsername $sessionChapUsername -sessionChapSecret $sessionChapSecret -discoveryChapUsername $discoveryChapUsername -discoveryChapSecret $discoveryChapSecret

    $diskNumber = GetDiskNumberFromIscsi $connection $lun
    if($isReadWrite)
    {
        $reservation = GetReservations -diskNumber $diskNumber
        if($reservation -eq $null)
        {
            MakeDiskIdUnwrittable $diskNumber
            RegisterDisk $diskNumber $prFmt   
            ReserveDiskRegistrantsExclusive -diskNumber $diskNumber -reservationNumber $prFmt
            
            $disk = GetDiskByNumber $diskNumber
            CreateVolumeIfNecessary $disk $fsType
            RegisterDisk $diskNumber $prWrite
        }
        elseif(($reservation.key -eq $prFmt))
        {
            MakeDiskIdUnwrittable $diskNumber
            RegisterDisk $diskNumber $prFmt
            #attempt to preempt incase someone else has it. We may have it in which case prempt will fail and we
            #will just go on
            try
            {
                PreemptDiskExclusive -diskNumber $diskNumber -reservationNumber $prFmt -serviceKey $($reservation.key)
            }
            catch
            {
                Log "Prempting format key failed, we must already had it. Creating the volume if necessary"
            }
            $disk = GetDiskByNumber $diskNumber
            CreateVolumeIfNecessary $disk $fsType
            RegisterDisk $diskNumber $prWrite
        }
        else
        {
            $reservation = GetReservations -diskNumber $diskNumber
            RegisterDisk $diskNumber $prWrite
            if($reservation.key -ne $prWrite)
            {
                MakeDiskIdUnwrittable $diskNumber
            }
            try
            {
                PreemptDiskExclusive -diskNumber $diskNumber -reservationNumber $prWrite -serviceKey $reservation.key
            }
            catch
            {
                if($reservation.key -eq $prWrite)
                {
                    Log "Prempting key $($reservation.key) failed, we must already had it."
                }
                else
                {
                    Log "Failed to preempt key $($reservation.key) on disk $diskNumber"
                    throw $_
                }
            }
        }
    }
    else
    {
        $reservation = GetReservations -diskNumber $diskNumber
        if($reservation -ne $null)
        {
            if(($reservation.key -eq $prWrite) -or ($reservation.key -eq $prFmt))
            {
                MakeDiskIdUnwrittable $diskNumber
                try
                {
                    #attempt to release the key
                    ReleaseDisk $diskNumber $reservation.key -scope $reservation.scope -type $reservation.type                    
                }
                catch
                {    
                    Log "Releasing disk $diskNumber failed, this operation is only a best effort incase we owned the disk"                
                }
            }
        }
        RegisterDisk $diskNumber $prRO
        $reservation = GetReservations -diskNumber $diskNumber

        if(($reservation -eq $null) -or ($reservation.key -ne $prRO))
        {
            MakeDiskIdUnwrittable $diskNumber
        }
        try
        {            
            if($reservation -eq $null)
            {
                ReserveDiskRegistrantsExclusive -diskNumber $diskNumber -reservationNumber $prRO
            }
            else
            {
                PreemptDiskRegistrantsExclusive -diskNumber $diskNumber -reservationNumber $prRO -serviceKey $reservation.key
            }
        }
        catch {}
        
        $reservation = GetReservations -diskNumber $diskNumber
        if(($reservation.key -ne $prRO) -or ($reservation.scope -ne 0) -or ($reservation.type -ne $exclusiveRegistrantsReservationType))
        {
            throw "Error creating Read only reservation for disk $diskNumber"
        }

        #attempt to remove all registrations that don't belong
        $registrations = GetRegistrations -diskNumber $diskNumber
        foreach($registration in $registrations)
        {
            try
            {
                if($registration -ne $prRO)
                {
                    PreemptDiskRegistrantsExclusive -diskNumber $diskNumber -reservationNumber $prRO -serviceKey $registration
                }
            }
            catch {}
        }
    }
    
    $disk = GetDiskByNumber $diskNumber
    if($isReadWrite)
    {
        SetDiskOffline $disk $false
        SetDiskReadOnly $disk $false
    }
    else
    {
        SetDiskOffline $disk $false
        SetDiskReadOnly $disk $true
    }

    $volumes = GetVolumesForDisk $disk
    $volume = ($volumes | ? {$_.FileSystemType -eq $fsType})| GetFirst "Could not find volume of type $fsType in volume $volume"

    $remotePath = $volume.path

    MakeSymLink $path $remotePath
}

function unmount_command($path)
{
    Log "unmount $path"
    if(test-path $path)
    {
        #need to remove the link
        #first we should clean up the disk
        #so lets find it
        $item = get-item $path
        if($item.LinkType -ne "SymbolicLink")
        {
            throw "path $path was not a symbolic link, $item"
        }

        # for some reason powershell seems to eat the \\?\
        # start for symlinks
        $volumePath = $item.Target[0]
        if(-not $volumePath.StartsWith("\\?\"))
        {
            $volumePath = "\\?\" + $volumePath
        }

        #doing a filter as this won't have issues if no results exist
        Get-Volume |? {$_.path -eq $volumePath} | % {
            $volume = $_
            $volume | Write-VolumeCache | out-null
            $disk = $volume | Get-Partition | Get-Disk
            SetDiskReadOnly $disk $true
            SetDiskOffline $disk $true
        }

        DeleteSymLink $path
    }
    else
    {   
        Log "path $path already was unmounted "
    }
}


RunFlexVolume