#note these strings are used other places!
$IscsiSecrets = @('ISCSI_CHAP_USERNAME',
                  'ISCSI_CHAP_PASSWORD',
                  'ISCSI_REVERSE_CHAP_USERNAME',
                  'ISCSI_REVERSE_CHAP_PASSWORD' )
function TargetExists($name, $server)
{
    $servers = Get-IscsiServerTarget -ComputerName $server -ErrorAction Stop 
    $matched = $servers | ?{$_.TargetName -eq $name}
    return ($matched | Measure-Object).Count -ne 0
}

function IscsiVirtualDiskExists($path, $server)
{
    $disks = Get-IscsiVirtualDisk -ComputerName $server -ErrorAction Stop 
    $matched = $disks | ?{$_.Path -eq $path}
    return ($matched | Measure-Object).Count -ne 0
}

function EnsureIscsiTargetExists(   $targetName,
                                    $computername,
                                    [string] $authType = 'NONE',
                                    [string] $chapUserName = '', 
                                    [string] $chapPassword = '', 
                                    [string] $rchapUserName = '', 
                                    [string] $rchapPassword = '')
{
    if(-not $(TargetExists $targetName $computername))
    {
        $target = New-IscsiServerTarget -TargetName $targetName -ComputerName $computername -InitiatorIds "iqn:*" -ErrorAction Stop
    }
    $target = Get-IscsiServerTarget -TargetName $targetName -ComputerName $computername -ErrorAction Stop

    if($authType -ne "NONE")
    {
        $chapParams = @{}
        $user = $chapUserName
        $pass = $chapPassword
        $password = ConvertTo-SecureString -String $pass  -AsPlainText -Force
        $chapParams.Chap = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $user, $password 
        if($authType -eq "MUTALCHAP")
        {
            $user = $rchapUserName
            $pass = $rchapPassword
            $password = ConvertTo-SecureString -String $pass  -AsPlainText -Force
            $chapParams.ReverseChap = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $user, $password 
            $chapParams.EnableReverseChap = $true
        }
        $empty = Set-IscsiServerTarget -TargetName $targetName -EnableChap $True @chapParams -ErrorAction Stop
    }
    return $target.TargetIqn.ToString()
}

function supports_iscsi($options)
{
    return [bool] $options.parameters.iscsiLocalPath
}
function provision_iscsi($options)
{   
    $name = $options.name

    #$options.parameters.type = "pd-ssd"
    $localPath = $options.parameters.iscsiLocalPath
    $server = $options.parameters.iscsiServerName
    $authType = $options.parameters.iscsiAuthType
    $portals = $options.parameters.iscsiPortals
    $targetPortal = $options.parameters.iscsiTargetPortal
    
    $path = join-path $localPath "$name.vhdx"
    $requestSize = $options.volumeClaim.spec.resources.requests.storage
    $requestSize = ConvertKubeSize $requestSize
    
    $isFixed = $options.parameters.iscsiUseFixed -eq "true"
    $useFixedParam = @{}
    if($isFixed){$useFixedParam.UseFixed = $true}

    if(-not $server)
    {
        $server = $targetPortal
    }

    DebugLog "Loading Secrets"
    $secrets = LoadSecrets($IscsiSecrets)

    DebugLog "Local path $path on server $server "

    $targetName = $name
    $iqn = EnsureIscsiTargetExists -targetName $targetName `
                                   -ComputerName $server `
                                   -authType $authType `
                                   -chapUserName $secrets:ISCSI_CHAP_USERNAME `
                                   -chapPassword $secrets:ISCSI_CHAP_PASSWORD `
                                   -rchapUserName $secrets:ISCSI_REVERSE_CHAP_USERNAME `
                                   -rchapPassword $secrets:ISCSI_REVERSE_CHAP_PASSWORD 
    
    if(-not $(IscsiVirtualDiskExists $path $server ))
    {
        $empty = New-IscsiVirtualDisk $path -size $requestSize -computername $server @useFixedParam -ErrorAction Stop 2>&1  
    }

    Add-IscsiVirtualDiskTargetMapping -TargetName $targetName $path -computername $server -ErrorAction Stop
    
    $lun = 0
    
    DebugLog $requestSize        
                        
    $ret = @{"metadata" = @{
        "labels" =@{
            "proto" = "iscsi" } }; 
        "spec"= @{
            "flexVolume" = @{
                "driver" = "microsoft.com/iscsi.cmd"; 
                "fsType" = $options.parameters.iscsiFsType;
                "secretRef" = @{
                    "name" = $options.parameters.iscsiSecret };
                "options" = @{
                    "chapAuthDiscovery" = $options.parameters.iscsiChapAuthDiscovery;
                    "chapAuthSession" = $options.parameters.iscsiChapAuthSession;
                    "targetPortal" = $targetPortal;
                    "iqn" = $iqn;
                    "lun" = "0";
                    "authType" = $authType;
                    "serverName" = $server;
                    "localPath" = $path;
                    "isFixed" = $isFixed } } } }
    if($portals)
    {
        $ret.spec.flexVolume.options.portals = $portals
    }
    return $ret
}
function delete_iscsi($options)
{   
    $path = $options.volume.spec.flexVolume.options.localPath
    $server = $options.volume.spec.flexVolume.options.serverName

    $name = $options.volume.metadata.name

    if($(TargetExists $name $server))
    {
        DebugLog "Removing iscsi target $name on server $server no longer exists"
        #the goal of this set is to disconnect all people using this target
        Set-IscsiServerTarget $name  -InitiatorIds "iqn:none" -ComputerName $server -ErrorAction Stop
        remove-IscsiServerTarget  $name -ComputerName $server -ErrorAction Stop
    }
    DebugLog "Ensured iscsi target $name on server $server no longer exists"
    
    if($(IscsiVirtualDiskExists $path $server))
    {
        DebugLog "deleting iscsiDisk $path on $server using local path $path"    
        $empty = remove-IscsiVirtualDisk $path -computername $server 
    }
    DebugLog "Ensured that iscsiDisk $path on $server using local path $path was deleted"
        
    DeleteRemotePath $path -ComputerName $server
}