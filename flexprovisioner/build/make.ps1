$volume_spec = ([string]$pwd) +":c:\bin"
iex "docker run --rm -v $volume_spec golang:windowsservercore-ltsc2016 --isolation=hyperv powershell -file c:\bin\build_internal.ps1"   
