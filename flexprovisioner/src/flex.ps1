$global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$logSource = "KubeFlex"

. $PSScriptRoot\flexvolume.ps1
. $PSScriptRoot\iscsi.ps1
. $PSScriptRoot\smb.ps1

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
        return delete_smb $options        
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