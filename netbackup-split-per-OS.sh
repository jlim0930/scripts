#!/bin/sh

# This script will seperate the big tarballs for NBU into individual clients for each OS.
# Please make sure that there is enough space on the drive to perform the seperation.
# Copy this script and the 2 tarballs into a directory and run the script.

# set directories
TMP=nbutmp
BASEDIR=$(dirname $0)

# take input
read -p "Version: " VERSION
echo ""
echo "[DEBUG] Version $VERSION entered."

CLIENT1="NetBackup_${VERSION}_CLIENTS1.tar.gz"
CLIENT2="NetBackup_${VERSION}_CLIENTS2.tar.gz"
LOC1="NetBackup_${VERSION}_CLIENTS1/NBClients/anb/Clients/usr/openv/netbackup/client"
LOC2="NetBackup_${VERSION}_CLIENTS2/NBClients/anb/Clients/usr/openv/netbackup/client"

if [ ! -f $BASEDIR/$CLIENT1 ]; then
  echo "[DEBUG] File ${CLIENT1} does not exist.  Please copy over and start over again."
  exit
else
  echo "[DEBUG] File ${CLIENT1} found."
fi

if [ ! -f $BASEDIR/$CLIENT2 ]; then
  echo "[DEBUG] File ${CLIENT2} does not exist.  Please copy over and start over again."
  exit
else
  echo "[DEBUG] File ${CLIENT2} found."
fi

echo "[DEBUG] Please make sure that you have enough space to perform the seperation.  This process will require 3x the size of both tarballs to seperate."


if [ -d ${BASEDIR}/${TMP} ]; then
  echo "[DEBUG] Removing old temp directory."
  rm -rf ${BASEDIR}/${TMP}
fi

echo "[DEBUG] Creating temp directory."
mkdir ${BASEDIR}/${TMP}

if tar -zxf ${CLIENT1} ; then
  echo "[DEBUG] File ${CLIENT1} untarred removing source."
  rm ${CLIENT1}
  mv ${BASEDIR}/${LOC1}/* ${BASEDIR}/${TMP}/
else
  echo "[DEBUG] Problem untaring ${CLIENT1}... exiting"
  exit
fi

if tar -zxf ${CLIENT2} ; then
  echo "[DEBUG] File ${CLIENT2} untarred removing source."
  rm ${CLIENT2}
  mv ${BASEDIR}/${LOC2}/* ${BASEDIR}/${TMP}/
else
  echo "[DEBUG] Problem untaring ${CLIENT2}... exiting"
  exit
fi


echo "[DEBUG] Creating tarball for HP-UX-IA64"
mv ${BASEDIR}/${TMP}/HP-UX-IA64/ ${BASEDIR}/${LOC1}/
tar -h -cf NetBackup_${VERSION}_specific.HP-UX-IA64.tar NetBackup_${VERSION}_CLIENTS1/
gzip NetBackup_${VERSION}_specific.HP-UX-IA64.tar
rm -rf ${BASEDIR}/${LOC1}/HP-UX-IA64

echo "[DEBUG] Creating tarball for INTEL"
mv ${BASEDIR}/${TMP}/INTEL/ ${BASEDIR}/${LOC1}/
tar -h -cf NetBackup_${VERSION}_specific.INTEL-FreeBSD6.0.tar NetBackup_${VERSION}_CLIENTS1/
gzip NetBackup_${VERSION}_specific.INTEL-FreeBSD6.0.tar
rm -rf ${BASEDIR}/${LOC1}/INTEL

echo "[DEBUG] Creating tarball for MACINTOSH"
mv ${BASEDIR}/${TMP}/MACINTOSH/ ${BASEDIR}/${LOC1}/
tar -h -cf NetBackup_${VERSION}_specific.MACINTOSH-MacOSX10.6.tar NetBackup_${VERSION}_CLIENTS1/
gzip NetBackup_${VERSION}_specific.MACINTOSH-MacOSX10.6.tar
rm -rf ${BASEDIR}/${LOC1}/MACINTOSH

echo "[DEBUG] Creating tarball for RS6000"
mv ${BASEDIR}/${TMP}/RS6000/ ${BASEDIR}/${LOC1}/
tar -h -cf NetBackup_${VERSION}_specific.RS6000-AIX6.tar NetBackup_${VERSION}_CLIENTS1/
gzip NetBackup_${VERSION}_specific.RS6000-AIX6.tar
rm -rf ${BASEDIR}/${LOC1}/RS6000

mv ${BASEDIR}/${TMP}/Solaris/ ${LOC1}/
for dir in `ls -1 ${LOC1}/Solaris/`
do
  echo "[DEBUG] Creating tarball for Solaris.${dir}"
  tar -h -cf NetBackup_${VERSION}_specific.Solaris.${dir}.tar NetBackup_${VERSION}_CLIENTS1/Doc/ NetBackup_${VERSION}_CLIENTS1/LICENSE NetBackup_${VERSION}_CLIENTS1/NBClients/anb/Clients/usr/openv/netbackup/client/Solaris/${dir}/ NetBackup_${VERSION}_CLIENTS1/NBClients/catalog/  NetBackup_${VERSION}_CLIENTS1/VSM_README  NetBackup_${VERSION}_CLIENTS1/install
  gzip NetBackup_${VERSION}_specific.Solaris.${dir}.tar
done

mv ${BASEDIR}/${TMP}/Linux/ ${LOC2}/
for dir in `ls -1 ${LOC2}/Linux/`
do
  echo "[DEBUG] Creating tarball for LINUX.${dir}"
  tar -h -cf NetBackup_${VERSION}_specific.Linux.${dir}.tar NetBackup_${VERSION}_CLIENTS2/Doc/  NetBackup_${VERSION}_CLIENTS2/LICENSE  NetBackup_${VERSION}_CLIENTS2/NBClients/anb/Clients/usr/openv/netbackup/client/Linux/${dir}/ NetBackup_${VERSION}_CLIENTS2/NBClients/catalog/  NetBackup_${VERSION}_CLIENTS2/VSM_README  NetBackup_${VERSION}_CLIENTS2/install
  gzip NetBackup_${VERSION}_specific.Linux.${dir}.tar
done

echo "[ INFO ] Cleanup..."
rm -rf ${BASEDIR}/${TMP}
rm -rf ${BASEDIR}/NetBackup_${VERSION}_CLIENTS1
rm -rf ${BASEDIR}/NetBackup_${VERSION}_CLIENTS2


echo "[DEBUG] DONE!"
ls -la
