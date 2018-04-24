#get the code we want to build
go get github.com/kubernetes-incubator/external-storage
cd C:\gopath\src\github.com\kubernetes-incubator\external-storage

#use KnicKnic fork instead
git remote add fork https://github.com/KnicKnic/external-storage.git -f
git reset --hard fork/script_interface

#add glide & all dependencies
go get -u github.com/Masterminds/glide
glide install --strip-vendor --strip-vcs

#do the actual building
cd C:\gopath\src\github.com\kubernetes-incubator\external-storage\flex\cmd\flex-provisioner
go build -o c:\bin\flex-provisioner.exe
