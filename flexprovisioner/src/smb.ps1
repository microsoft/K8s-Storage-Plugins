function NewFsrmQuota($path, [uint64]$size, $ComputerName)
{
#$empty = New-FsrmQuota -Path $fsrmPath -Size $requestSize -CimSession $ComputerName -ErrorAction Stop 2>&1   
# 
# using wmi instead due to cmdlets not being installable on server_core
# also reduces dependencies
$empty = New-CimInstance -ClassName "MSFT_FSRMQuota" -Namespace "Root/Microsoft/Windows/FSRM" -ComputerName $computername  -Property @{"Path" = $path; "Size" = $size} -erroraction stop  2>&1
}

function SetFsrmQuota($path, [uint64]$size, $ComputerName)
{
#$empty = Set-FsrmQuota -Path $fsrmPath -Size $requestSize -CimSession $serverName -ErrorAction Stop 2>&1
 
# using wmi instead due to cmdlets not being installable on desktop
# using post filtering because of WQL escaping rules
$cimInstance = Get-CimInstance  -ClassName "MSFT_FSRMQuota" -Namespace "Root/Microsoft/Windows/FSRM" -ComputerName $computername -erroraction stop  2>&1 | ?{$_.Path -eq $path} | GetFirst -message "Failed to get instance of MSFT_FSRMQuota"
$cimInstance | Set-CimInstance -ComputerName $computerName -Property @{"Size" = $size} -erroraction stop  2>&1
}

function supports_smb($options)
{
    return [bool] $options.parameters.smbLocalPath
}

# Takes in \\servername\share\path or smb://servername/share/path or //servername/share/path
# and returns \\servername\share\path
function MigrateLinuxCifsPathToWindows([string]$smbPath)
{
    if($smbPath.StartsWith('smb://','CurrentCultureIgnoreCase'))
    {
        $smbPath = '//' + $smbPath.SubString('smb://'.Length)
    }
    if($smbPath.StartsWith('//'))
    {
        $smbPath = $smbPath.replace('/', '\')
    }
    return $smbPath
}

function GetServerNameOrParseSharename([string] $serverName, [string]$shareName)
{
    if($serverName)
    {
        return $serverName
    }
    # returns from format take '\\<server>\'
    return $shareName.split('\')[2]
}

function provision_smb($options)
{
    $name = $options.name
    $remotePath = MigrateLinuxCifsPathToWindows -smbPath $options.parameters.smbShareName
    $localPath = $options.parameters.smbLocalPath
    $serverName = GetServerNameOrParseSharename -serverName $options.parameters.smbServerName -shareName $remotePath
    $secret = $options.parameters.smbSecret
    
    $path = $remotePath + '\' + $name
    $localPath = $localPath + '\' + $name
    $requestSize = ConvertKubeSize $options.volumeClaim.spec.resources.requests.storage

    DebugLog "Remote path $remotePath"
    DebugLog "Local path $localPath"

    
    DebugLog "Requestsize $requestSize"
    EnsureRemotePathExists $localPath -ComputerName $serverName
        
    if($options.parameters.smbNoQuota -ne "true")
    {
        $fsrmPath = $localPath
        DebugLog "applying fsrmquota to path $fsrmPath on $serverName"
        try {
            # if we throw assume that the fsrm already created the quota and verify by doing a set
            $empty = NewFsrmQuota -Path $fsrmPath -Size $requestSize -ComputerName $serverName
        }
        catch {
            $empty = SetFsrmQuota -Path $fsrmPath -Size $requestSize -ComputerName $serverName
        }
        DebugLog "applied fsrmquota"
        DebugLog $empty
    }
    DebugLog "made directory"
                        
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
                        "localPath" = $localPath;
                        "serverName"= $serverName; } } } }
                        
    return $ret
}

function delete_smb($options)
{
    $serverName = $options.volume.spec.flexVolume.options.serverName
    DeleteRemotePath $options.volume.spec.flexVolume.options.localPath -ComputerName $serverName    
}