# Flexvolume Helpers
Contains some helper files to create a kubernetes flexvolume plugin on windows in powershell
* scriptrunner.cmd
    * You should copy this into your project and rename it yourpluginname.cmd
    * When run it will call yourpluginname.ps1
* scriptrunner_prod.cmd
    * You should copy this into your project and rename it yourpluginname_prod.cmd
    * This is the same as scriptrunner.cmd without `-ExecutionPolicy Bypass`.
        * When releasing the files are signed and this is not needed
* flexvolume.ps1
    * this contains some utilities to run flexvolume logic
    * copy into plugin folder

You will need to add your own yourpluginname.ps1. In the file you will need to implement the basic scaffolding for your plugin in that file. 
* For a simple example see ..\microsoft.com~smb\smb.ps1 .
* For an empty scaffold see .\emptyplugin.ps1

