#!/bin/bash
echo Installing packages ...
sudo apt-get update
sudo apt-get install samba samba-common-bin

echo Making Samba data directory ...
sudo mkdir -m 1777 /data
echo Done.
echo

echo Please add the following by
echo sudo vi /etc/samba/smb.conf 
echo
echo    [data]
echo        comment = Data share
echo        path = /data
echo        browseable = yes
echo        read only = no
echo

echo Please add user for samba
echo     smbpasswd -a root
echo     smbpasswd -a pi

echo Please restart services 
echo     cd  /etc/init.d ; sudo samba restart
echo

