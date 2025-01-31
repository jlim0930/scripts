# execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# fix for ssl
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# install scoop
# irm get.scoop.sh | iex
iex "& {$(irm get.scoop.sh)} -RunAsAdmin"

scoop install sudo

scoop install 7zip git
scoop bucket add extras

scoop install putty firefox mobaxterm 7zip powertoys sysinternals
