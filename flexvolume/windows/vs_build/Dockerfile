# escape=`

# Use the latest Windows Server Core image.
ARG FROM_IMAGE=microsoft/windowsservercore:latest
FROM ${FROM_IMAGE}

# Copy our supporting files.
COPY Support C:\TEMP\

# Download collect.exe in case of an install failure.
ADD https://aka.ms/vscollect.exe C:\TEMP\collect.exe

# Determine the specific URLs for the bootstapper, channel, and manifest.
ARG MAJOR_VERSION=15
ARG BUILD_BRANCH=rel/d15.6
ARG BUILD_VERSION=27331.01
ARG INSTALLER_URL=https://vsdrop.corp.microsoft.com/file/v1/Products/DevDiv/VS/${BUILD_BRANCH}/${BUILD_VERSION};x86ret/enu/VisualStudio.${MAJOR_VERSION}.IntPreview.Bootstrappers.BuildTools/vs_buildtools.exe
ARG CHANNEL_URL=https://vsdrop.corp.microsoft.com/file/v1/Products/DevDiv/VS/${BUILD_BRANCH}/${BUILD_VERSION};x86ret/enu/VisualStudio.${MAJOR_VERSION}.IntPreview.Manifest/VisualStudio.${MAJOR_VERSION}.IntPreview.chman
ARG MANIFEST_URL=https://vsdrop.corp.microsoft.com/file/v1/Products/DevDiv/VS/${BUILD_BRANCH}/${BUILD_VERSION};x86ret/enu/Microsoft.VisualStudio.Channels.PreviewInstallerManifest/VisualStudioPreview.vsman

# Channel is needed for Willow install, but manifest may be needed for CLI install in some containers.
ADD ${CHANNEL_URL} C:\Layout\VisualStudioPreview.chman
ADD ${MANIFEST_URL} C:\Layout\VisualStudioPreview.vsman

# Download and install Build Tools excluding workloads and components with known issues.
ADD ${INSTALLER_URL} C:\TEMP\vs_buildtools.exe
RUN C:\TEMP\Install.cmd C:\TEMP\vs_buildtools.exe --quiet --wait --norestart --nocache `
    --installPath C:\BuildTools `
    --channelUri C:\Layout\VisualStudioPreview.chman `
    --installChannelUri C:\Layout\VisualStudioPreview.chman `
    --all `
    --remove Microsoft.VisualStudio.Component.Windows10SDK.10240 `
    --remove Microsoft.VisualStudio.Component.Windows10SDK.10586 `
    --remove Microsoft.VisualStudio.Component.Windows10SDK.14393 `
    --remove Microsoft.VisualStudio.Component.Windows81SDK

# Default to interactive developer command prompt if no other command specified.
CMD ["cmd", "/S", "/K", "C:\\BuildTools\\Common7\\Tools\\VsDevCmd.bat"]
