$global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$logSource = "YourPluginNameLogSourceName"

. $PSScriptRoot\flexvolume.ps1
<#
.SYNOPSIS
    Called when flexvolume plugin is passed init
#>
function init()
{
}

<#
.SYNOPSIS
Called when flexvolume plugin is passed mount

.PARAMETER path
The string location where you are supposed to create a symlink to the newly mounted folder

.PARAMETER options
The options passed in from flexvolume converted into an object using convertfrom-json
#>
function mount_command([string]$path, $options)
{  
    #$newlyMountedFolder = MountSomeFolder
    #MakeSymLink $path $newlyMountedFolder
}

<#
.SYNOPSIS
Called when flexvolume plugin is passed unmount

.PARAMETER path
The string location where symlink to the mounted folder exists to remove
#>
function unmount_command([string]$path)
{    
}

# will run flexvolume logic
RunFlexVolume