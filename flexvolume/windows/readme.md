# Microsoft Flexvolume Kubernetes Plugins
Here are implementations of flexvolume in kubernetes for iSCSI and SMB. Also helps serve as a scaffolding for building future volume plugins in powershell on windows.

For more info on Flexvolume see
 * https://github.com/kubernetes/community/blob/master/contributors/devel/flexvolume.md
 * https://docs.openshift.org/latest/install_config/persistent_storage/persistent_storage_flex_volume.html#flex-volume-drivers-without-master-initiated-attach-detach


**Code is currently alpha, names may change, all tests have not been performed**

 ## Plugins
* SMB
    * This plugin allows you to use SMB shares. 
    * **Currently there is no storage fencing**
        * The application must hold locks on the files they use
    * readOnly in flexVolume is ignored 
        * to get readOnly behavior, specify volumeMounts when consuming volume
            * readOnly: true

* iSCSI
    * Plugin allows you to consume iSCSI disks.
    * Provides fencing through the use of SCSI Persistent Reservations

## Folder structure
* microsoft.com~iscsi.cmd
    * All powershell files needed for iscsi plugin
    * When deploying must add iscsiHelper.exe
* microsoft.com~smb.cmd
    * All files for smb plugin
* sample_yamls
    * some yamls that demonstrate howto use the plugins
* utils/scriptrunner
    * Serves as a basis for building plugins
    * These files are symlinked into plugin directories
* utils/iscsiHelper
    * Contains a c++ commandline application that provides some storage features used by iscsi.cmd
* vs_build
    * Setup a container with Visual Studio 2017 & SDK to build iscsiHelper.exe
        * This is optional, and just provided for ease of use.
        * **Beware the produced image file is quite large 25+GB.**



## Deployment guide
The default plugin folder location is C:\usr\libexec\kubernetes\kubelet-plugins\volume\exec\
* SMB
    * Copy microsoft.com~smb.cmd into the plugin folder
* ISCI
    * Copy microsoft.com~iscsi.cmd into the plugin folder
    * Copy the binary produced by iscsiHelper into microsoft.com~iscsi.cmd on the same nodes.
    * Install the approrpiate Visual Studio C++ redistributuable on all nodes
        * https://aka.ms/vs/15/release/vc_redist.x64.exe\
    * Optionally create a pr.txt file in the current working directory that corresponds to that node's SCSI PR to use
        * If none is created a random one will be generated

See https://github.com/andyzhangx/Demo/tree/master/windows/flexvolume for more info.

To get logs for the plugin run `Get-EventLog -LogName Application -Source Kube* -Newest 50  | %{$_.message}`

## Build instructions
The only thing that needs to be built is iscsiHelper. To build it you need Visual Studio 2017 with the SDK, or use provided vs_build container.  



