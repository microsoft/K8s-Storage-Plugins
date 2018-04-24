$debug_mode = $true
$exitCode = 0
$logName = "Application"
$logId = 1

if($logSource -eq $null)
{
    throw "Define logSource before including this script"
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

function LoadSecrets([String[]] $secrets)
{
    $retSecrets = @{}
    # so we go over the list of secrets
    # First we look for the secret environment variable if that exists use it
    # If not look for _FILE and if that exists
    #   See if _FILE exists that is pointed to by that name, if it does load it, otherwise add nothing

    foreach($secret in $secrets)
    {
        if([System.Environment]::GetEnvironmentVariable($secret) -ne $null)
        {
            $retSecrets[$secret] = [System.Environment]::GetEnvironmentVariable($secret)
        }
        else 
        {
            $fileEnv = $secret + "_FILE"
            if([System.Environment]::GetEnvironmentVariable($fileEnv) -ne $null)
            {
                if(test-path $fileEnv)
                {
                    $retSecrets[$secret] = Get-Content -Path $fileEnv -Encoding Ascii
                }
            }            
        }
    }
    return $retSecrets
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
    DebugLog "cmdline: $cmdline"
    $firstDotCmdRemoved = $cmdline.substring($cmdline.IndexOf(".cmd") + 4)
    $all = $firstDotCmdRemoved.Trim('" ')
    DebugLog "all: $all"
    if($all.Length -gt $command.Length)
    {
        $escapedJson = $all.Substring($command.Length).Trim()
        $json = $escapedJson.Replace('\\"','\"').Replace('\"', '"')    
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
        elseif($command -eq "provision")
        {
            $options = $json  | convertfrom-json
            DebugLog $options
            
            $volume = provision_command -options $options
            DebugLog "returned $volume"
            
            $output = @{"status" = "Success"; "volume" = $volume} | ConvertTo-Json -Depth 10
            DebugLog "serialized  $output"
            LogAndPrint $output
        }
        elseif($command -eq "delete")
        {
            $options = $json  | convertfrom-json
            DebugLog $options
            
            delete_command -options $options
            $output = @{"status" = "Success"; } | ConvertTo-Json -Depth 10
            LogAndPrint $output
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
    DebugLog "exiting"
    exit $exitCode
}