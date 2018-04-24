## Container with Visual Studio 2017 & SDK
* Can be used to build iscsiHelper
* **Beware the produced image file is quite large 25+GB, this container was not optimized for size.**
* **You do not need this if you have Visual Studio and the SDK installed.**

Steps - assume c:\code is where the root of the repository is mounted and run from cmd.exe

    #create image run from repository root
    docker build -t vs_build:1 vs_build

    #compile iscsiHelper ito output folder    
    docker run --rm -it -v %cd%\plugins:c:\code vs_build:1 cmd /C c:\code\vs_build\buildscript.cmd
  
  
  
  
Useful commands for msbuild

    #clean output
    MSBuild c:\code\iscsiHelper\iscsiHelper.sln /p:OutDir=c:\code\microsoft.com~iscsi\;Configuration=Release;Platform=x64 /t:Clean

    #build output
    MSBuild c:\code\iscsiHelper\iscsiHelper.sln /p:OutDir=c:\code\microsoft.com~iscsi\;Configuration=Release;Platform=x64
