@echo off
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

setlocal enabledelayedexpansion

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Get the drive, path, and file name of this file, minus the .CMD extension
set scriptname=%~dpn0

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: using environment variables to avoid escaping pains
set flexvolume_command=%1
set flexvolume_folder=%2

:: Not trying to parse the json as it ended up being hard
:: script just gets the executed command line off the parent process (this script)
:: set flexvolume_json=%3
:: set flexvolume_all=%*

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: launch powershell
PowerShell.exe -NoLogo -Sta -NoProfile -Command "%scriptname%.ps1"
goto :eof
