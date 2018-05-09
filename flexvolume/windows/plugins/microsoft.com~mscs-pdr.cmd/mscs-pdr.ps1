$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$logSource = "KubeMscsPdr"

. $PSScriptRoot\flexvolume.ps1
function init()
{
}

function mount_command([string]$path, $options)
{  
    $groupName = $options.groupName
    $destNode = $env:COMPUTERNAME
    $defaultWaitTime = 60
    move-clustergroup -Name $groupName -Node $destNode -Wait $defaultWaitTime 2>&1 | Out-Null
    Start-ClusterGroup -Name $groupName -Wait $defaultWaitTime 2>&1 | Out-Null

    $group = get-clustergroup $groupName
    if($group.state -ne "Online")
    {
        throw "Failed to online Cluster Group $groupName"
    }
    
    $pdr = $group | Get-ClusterResource
    $diskGuid = ($pdr | Get-ClusterParameter -name "DiskIdGuid").Value
    $disk = Get-Disk | ?{$_.guid -eq $diskGuid} | GetFirst -message "Failed to find disk matching Guid $diskGuid"
    $volume = $disk | get-partition | get-volume | GetFirst -message "Failed to find first volume in disk $diskGuid"
    $volumePath = $volume.Path
  
    MakeSymLink $path $volumePath
}

function unmount_command([string]$path)
{    
    Log "removing symlink for path $path"

    #if there is no disk to disconnect then we don't care
    try
    {
        DeleteSymLink $path
    }
    catch
    {
        Log "Did not do all steps of unmount, but will report success anyways"
    }
}

RunFlexVolume