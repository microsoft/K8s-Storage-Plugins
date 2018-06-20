$global:ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$logSource = "KubeSMB"

. $PSScriptRoot\flexvolume.ps1

function ConstructCredential([string]$username, $passPlain)
{
    $securePassword = ConvertTo-SecureString -String $passPlain -AsPlainText -Force
    return New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $securePassword 
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

function init()
{
}

function mount_command([string]$path, $options)
{  
    $passPlain = Base64Decode $($options.'kubernetes.io/secret/password')
    $User = Base64Decode $($options.'kubernetes.io/secret/username')
    $remoteP = $options.source
    $remoteP = MigrateLinuxCifsPathToWindows -smbPath $remoteP

    DebugLog  $passPlain
    DebugLog  $User

    Log  $remoteP 
   
    $Credential = ConstructCredential -username $User -passPlain $passPlain
  
    Log  "smbGlobal"
    $s = New-SmbGlobalMapping  -RemotePath $remoteP -Credential $Credential 2>&1
    Log  $s
  
    MakeSymLink $path $remoteP
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