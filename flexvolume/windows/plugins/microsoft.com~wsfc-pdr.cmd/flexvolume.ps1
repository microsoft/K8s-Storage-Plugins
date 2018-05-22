$debug_mode = $false
$exitCode = 0
$logName = "Application"
$logId = 1

if($logSource -eq $null)
{
    throw "Define logSource before including this script"
}

#delete a symbolic link
Function DeleteSymLink($path)
{
    $item = get-item $path
    #should test that 
    if($item.linkType -eq "SymbolicLink")
    {
        $item.delete()
    }
}

#allow you to expect an item and throw a useful message
Filter GetFirst
{
    Param([string] $message)
    Begin
    {
        $foundItem = $false;
    }
    Process
    {
        if(-not $foundItem)
        {
            $foundItem = $true
            $_
        }
    }
    End
    {
        if(-not $foundItem)
        {
            throw $message
        }
    }
}

Function IsSymLinkToPath($symLink, $path)
{
    if($item.LinkType -eq $null)
    {
        return $false
    }
    $target = $item.target[0]
    if($path.SubString(0, 2) -eq "\\")
    {
        # for smb try
        # UNC\machinename instead of \\machinename
        if(("UNC" + $path.Substring(1)) -eq $target)
        {
            return $true
        }
        # for volumes try 
        # Voume instead of \\?\Volume
        if($path.SubString(0, 4) -eq "\\?\")
        {
            if($target -eq $path.Substring(4))
            {
                return $true
            }
        }
    }
    if($target -eq $path)
    {
        return $true
    }
    return $false
}

#create the symbolic link for kubernetes
Function MakeSymLink($symlink, $remotepath)
{
    Log  "mklink $symlink $remotePath"
    # flexvolume may have already created the folder at the location the symlink should be
    # I think this is for bind mount in linux
    # this does not work for windows, so lets delete the folder
    if($(test-path $symlink -PathType Container))
    {
        $item = get-item $symlink
        if($item.LinkType -eq $null)
        {
            Log "deleting folder $symlink"
            #if not empty this will throw
            $item.delete()
        }
    }
    if($(test-path $symlink -PathType Container))
    {
        $item = get-item $symlink
        if($item.LinkType -eq "SymbolicLink")
        {
            if(IsSymLinkToPath -symLink $item -path $remotePath)
            {
                Log "symlink already existed"
                return
            }
            else
            {
                Log "stale symlink already existed to old path $($item.target[0])"
                DeleteSymLink $symlink
            }
        }
        else
        {
            throw "Cannot make symlink $symlink to $remotepath due to folder already existing"
        }
    }
    elseif( $(test-path $symlink))
    {
        throw "Cannot make symlink $symlink to $remotepath due to file already existing"
    }
    else
    {
    }
    #create a symbolic link using powershell (doesn't work for volumes)
    #$link = new-item -ItemType SymbolicLink -Path $symlink -Value $remoteP

    #volume symbolic link workaround below
    cmd /c "mklink /D $symlink $remotepath" 2>&1  | Out-Null
    #ensure symlink was created
    $item = get-item $symlink
    #should test that 
    if($item.linkType -ne "SymbolicLink")
    {
        throw "$symlink was not created"
    }
    Log $item
}

function Log([string] $s)
{ 
    #if(($s -eq $null) -or $s.Trim() -eq "")
    #{
    #$s = <empty>
    #}
    # always prepending message as things are cleaner for empty lines
    Write-EventLog -LogName $logName -Source $logSource -EntryType Information -EventId $logId -Message "log: $s"
}

function DebugLog([string] $s)
{ 
    if($debug_mode)
    {
        Log $s
    }
}
function Print([string] $s) 
{
    write-host $s
}

function LogAndPrint([string] $s) 
{
    Print $s
    Log $s
}

function NormalizePath([string] $s)
{
    # v1.5  $('c:' + $s.replace('/','\'))
    $s.replace('/', '\')
}

function Base64Decode([string] $s)
{
    [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($s))
}


function DoCommand ( [Parameter(Mandatory = $true)] [string] $command, 
    [bool] $throw = $false,
    [object[]] $objectList = @() )
{
    $scriptBlock = [scriptblock]::Create($command)
    $b = Invoke-command  -ErrorVariable err -ScriptBlock $scriptBlock -OutVariable output -ArgumentList $objectList
    if($throw -And $err -ne $null)
    {
        throw $err[0]
    }
    return $output
}
function DoCommandValidateErrorCode([Parameter(Mandatory = $true)] [string] $command )
{
    $output = DoCommand $command
    $errorCode = $LASTEXITCODE 
    if($errorCode -ne 0)
    {
        $errorMessage = "Error $errorCode running command $command"
        Log $errorMessage
        throw $errorMessage
    }
    return $output
}

function GetParentPid($processId)
{
    gwmi win32_process -Filter "ProcessId='$processId'" | % { $_.parentprocessid}
}

function GetCommandLine($processId)
{
    gwmi win32_process -Filter "ProcessId='$processId'" | % { $_.commandline}
}


New-EventLog -LogName $logName -Source $logSource -ErrorAction Ignore

function RunFlexVolume()
{
    $command = $env:flexvolume_command
    $folder = $env:flexvolume_folder
    $json = $null
    $cmdline = GetCommandLine $(GetParentPid $pid)
    
    DebugLog "command: $command"
    DebugLog "folder: $folder"
    DebugLog "cmdline: $cmdline"
    if($folder -ne $null)
    {
        # No longer use flexvolume_all as it has problems with the sequence !@#
        # I am also doing this because of batch rules and ',' escaping rules
        #
        # Take the hammer approach and get the commandline of the parent process and parse
        # after the script file name
        $firstDotCmdRemoved = $cmdline.substring($cmdline.IndexOf(".cmd") + 4)
        $secondDotCmdRemoved = $firstDotCmdRemoved.substring($firstDotCmdRemoved.IndexOf(".cmd") + 4)

        $all = $secondDotCmdRemoved.Trim('" ')

        # remove the first 2 args by string length and removing white space inbetween
        # this was the "best" work around for getting the json args
        $escapedJson = $all.Substring($command.Length).Trim().SubString($folder.Length)
        $json = $escapedJson.Replace('\"', '"')
        
        DebugLog "json: $json"
    }

    Log "$command"
    try
    {
        if($command -eq $null)
        {
            exit 0
        }
        if($command -eq "init")
        {
            init
            $output = @{"status" = "Success"; "capabilities" = @{"attach" = $false}} | ConvertTo-Json -Compress
            LogAndPrint $output
        }
        elseif($command -eq "mount")
        {
            $normPath = NormalizePath $folder
            $makePath = $normPath + "\..\"
            Log "Make dir $makePath"
            if(-not $(test-path $makePath -PathType Container))
            {
                mkdir $makePath 2>&1 | Out-Null
            }

            $options = $json  | convertfrom-json
            DebugLog $options
            
            mount_command -path $normPath -options $options
            LogAndPrint '{"status": "Success"}'
        }
        elseif($command -eq "unmount")
        {
            $normPath = NormalizePath $folder
            Log "unmount $normpath"
            unmount_command -path $normPath
            LogAndPrint '{"status": "Success"}'
        }
        elseif($command -eq "test")
        {
            test
        }
        else 
        {
            $output = @{"status" = "Not supported"; "message" = "Unsupported command $command"} | ConvertTo-Json -Compress
            Print $output
            Log "Unsupported command $command"
            $exitCode = 0
        }
    }
    catch
    {
        $exception = $_
        [string] $stack = $exception.ScriptStackTrace
        $s = "Caught exception $exception with stack $stack"
        Log $s
        $output = @{"status" = "Failure"; "message" = "$s"} | ConvertTo-Json -Compress
        Print $output
        $exitCode = 1
    }

    Log  " "
    exit $exitCode
}