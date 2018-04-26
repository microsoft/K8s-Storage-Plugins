# Flex provisioner scripts
**Status is alpha, variable names may change and tests are not exhaustive**

Here are some scripts sample scripts that will work with external flex provisioner (located at https://github.com/kubernetes-incubator/external-storage/tree/master/flex ). Currently I am utilizing the forked branch https://github.com/KnicKnic/external-storage/tree/script_interface/flex . This provisioner currently will provision SMB and iSCSI volumes against a windows server.

For more info on Flexvolume see [SMB & iSCSI windows FlexVolume plugins](../flexvolume/windows)

## Deploying
* Build flex-provisioner.exe
     * See [build](build)
* copy src/* & flex-provisioner.exe into some folder
* Run under domain account that has access to storage
    * sample usage
        * c:\provisioner\flex-provisioner.exe -logtostderr -provisioner microsoft.com/windows-server-storage-provisioner -execCommand c:\provisioner\flex.cmd -master http://master:8080
    * flex-provisioner.exe --help for more info
    * If using a container see gmsa setup https://blogs.msdn.microsoft.com/containerstuff/2017/01/30/create-a-container-with-active-directory-support/
    * Currently cannot create container using gmsa in kubernetes, see https://github.com/kubernetes/kubernetes/issues/62038

 ## StorageClass Parameters
 *Note when params use \"quotes\"
 ### SMB Parameters
Name | Meaning | Example | Mandatory 
--- | --- | --- | ---
smbShareName | Remote share path | \\\\FsHost1\Share1 | - [x]
smbLocalPath | Server's folder to create volumes in | c:\shared_folder | - [x]
smbServerName | Name provisioner uses to talk to server | FsHost1 | - [x]
smbSecret | Secret name volume plugin will use to mount | smb-secret | - [x]
smbSecret | Secret name volume plugin will use to mount | smb-secret | - [x]
smbNoQuota | Don't use FSRM to set quotas. | "false" | - [ ] *\*default false*

### iSCSI Parameters

Name | Meaning | Example | Mandatory
--- | --- | --- | ---
iscsiLocalPath | Server's folder to create volumes in | c:\shared_folder | - [x]
iscsiServerName | Name provisioner uses to talk to server | IscsiHost1 | - [x]
iscsiAuthType | Volume's iSCSI AuthType | ONEWAYCHAP | - [x]
iscsiSecret | Secret name volume plugin will use to mount<BR>*\*Secrets will still need to be given to provisioner* | iscsi-secret | - [x]
iscsiFsType | File system volume plugin will format | NTFS | - [x]
iscsiChapAuthDiscovery | should use chap auth for discovery | "false" | - [x]
iscsiChapAuthSession | should use chap auth for session | "true" | - [x]
iscsiTargetPortal | ISCSI target portal | IscsiHost1 | - [x]
iscsiPortals | Other possible portal paths | "1.1.1.1,1.1.1.2:954" | - [ ]
iscsiUseFixed | "true" to created fixed size disks | "false" | - [ ] *\*default false*

You can configure one storage class to provision for iSCSI and/or SMB. 

### Support notes
* SMB
    * ReadWriteOnce
        * **Becareful no fencing is provided, however locks will work**
        * So if an app grabs their own locks you will be fine
    * ReadWriteMany
        * If multiple instances of App can use same data it should already be guarding with locks
    * Notes
        * No protection exists against stale container of accessing path
        * Quotas
            * Uses File Server Resource Manager (FSRM)
                * FSRM will need to be installed on File Server
                    * All nodes if clustering is used
                    * add-windowsfeature FS-Resource-Manager
                * **FSRM is incompatible with REFS**
                * **FSRM is incompatible with Scale-Out File Server (SOFS)**
            * Can be disabled with smbNoQuota
        * You may want to consider setting up the file server with persistent handles, see https://blogs.technet.microsoft.com/filecab/2016/03/25/smb-transparent-failover-making-file-shares-continuously-available-2/

* iSCSI
    * ReadWriteOnce
        * Guards exist against old nodes accessing data
    * ReadWriteMany
        * NOT SUPPORTED!
    * Limits
        * A target is created per Volume (and an associated LU)
            * see limits https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-R2-and-2012/dn659435(v=ws.11)
                * 256 - Windows Server 2012R2
        * Current code uses vhdx file which means Windows 2012R2 & above only supported
        * ReFS is not supported as a file system
    * All nodes on storage server should have iscsi installed
        * add-windowsfeature FS-iSCSITarget-Server

### Environment variables
If it is a secret first look at the environment variable and load it, otherwise we append _FILE and try to read that file.

Environment Name | Meaning | Is a secret
--- | --- | ----
ISCSI_CHAP_USERNAME | Chap username for iSCSI | - [x]
ISCSI_CHAP_PASSWORD | Chap password for iSCSI | - [x]
ISCSI_REVERSE_CHAP_USERNAME | Reverse chap username for iSCSI | - [x]
ISCSI_REVERSE_CHAP_PASSWORD | Reverse chap password for iSCSI | - [x]

