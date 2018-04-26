$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$logSource = "KubeFlex"

. $PSScriptRoot\flexvolume.ps1
. $PSScriptRoot\iscsi.ps1
. $PSScriptRoot\smb.ps1
. $PSScriptRoot\s2d.ps1

Function RemotelyInvoke([string]$ComputerName, [ScriptBlock]$ScriptBlock, $ArgumentList = @())
{
    return Invoke-Command -ComputerName $ComputerName -ScriptBlock $ScriptBlock -ArgumentList $argumentlist -erroraction Stop        
}

function DeleteRemotePath([string]$pathToDelete, [string]$ComputerName)
{
    DebugLog "deleting $path"
    RemotelyInvoke -ComputerName $ComputerName -ScriptBlock {
        param($path)
        if(test-path $path){
            $empty = rmdir $path -Force -Recurse -ErrorAction Stop 2>&1 
        }
        else {
            $parentPath = Join-Path $path ".."
            $empty = Resolve-Path $parentPath -ErrorAction Stop
        }
    } -ArgumentList $pathToDelete -ErrorAction Stop
    DebugLog "Deleted path"
}
function EnsureRemotePathExists([string]$path, [string]$ComputerName)
{
    DebugLog "Ensuring $path exists on server $ComputerName"
    RemotelyInvoke -ComputerName $ComputerName -ScriptBlock {
        param($path)
        if(-not $(test-path $path)){
            $empty = mkdir $path -ErrorAction Stop 2>&1
        }
    } -ArgumentList $path -ErrorAction Stop
    DebugLog "Path $path exists on server $ComputerName"
}

function ConvertKubeSize([string]$number)
{
    $sizes = @(
        @("k", [math]::pow(10,3)),
        @("M", [math]::pow(10,6)),
        @("G", [math]::pow(10,9)),
        @("T", [math]::pow(10,12)),
        @("P", [math]::pow(10,15)),
        @("E", [math]::pow(10,16)),
        @("Ki", [math]::pow(2,10)),
        @("Mi", [math]::pow(2,20)),
        @("Gi", [math]::pow(2,30)),
        @("Ti", [math]::pow(2,40)),
        @("Pi", [math]::pow(2,50)),
        @("Ei", [math]::pow(2,60)))

    $multiplier = 1
    foreach($size in $sizes)
    {
        if($number.EndsWith($size[0],"CurrentCultureIgnoreCase"))
        {
            $multiplier = $size[1]
            $number = $number.substring(0,$number.length - $size[0].length)
            break
        }
    }
    [decimal]$dNumber = $number
    [uint64]$uNumber = ([decimal]$multiplier) * $dNumber

    $uNumber
}
function init()
{
}

function delete_command($options)
{      
    DebugLog  "Delete $options"
    if($options.volume.spec.flexVolume.driver -eq "microsoft.com/iscsi.cmd")
    {
        return delete_iscsi $options
    }
    else 
    {
        if($options.volume.spec.flexVolume.options.s2dShareServer)
        {
            return delete_s2d $options        
        }
        else
        {
            return delete_smb $options           
        }
    }
}

function provision_command($options)
{  
    DebugLog  "Provision $options"

    $noReadWriteMany = -not $options.volumeClaim.spec.accessModes.Contains("ReadWriteMany")
    if($noReadWriteMany -and $(supports_iscsi $options))
    {
        return provision_iscsi $options
    }
    elseif (supports_s2d $options)
    {
        return provision_s2d $options        
    }
    elseif (supports_smb $options)
    {
        return provision_smb $options        
    }
    else
    {
        if(-not $noReadWriteMany)
        {
            throw "Could not find an appropriate provisioner, cannot create ReadWriteMany for iSCSI and SMB is not supported "
        }
        else
        {
            throw "Could not find an appropriate provisioner, please set parameters for iSCSI or SMB "   
        }
    }
}

RunFlexVolume
DebugLog "ran flexvolume"