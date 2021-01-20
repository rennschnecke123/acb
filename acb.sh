#!/bin/bash

################################################
## R.Rusch, M.Blomberg
####################
#
# anonymous crypted backup everywhere "ACBE" (tm)
#
# Usage:
# acb -b -> make backup from actual path
# acb -r -> make restore from actual path to
#            subfolder acRestore/
################################################
#
# This will store your crypted backups on a
# anonymous tor node
#
# Your data can't be read by anyone else
# but you!!!
# 
# backup space could be a server via sftp or ssh
# also a local path (stick, second harddisc...)
###############################################
# Howto:
#
# to backup data go to the path you want to be
# saved:
# cd /myHome/myData/mySubpath
# now simply start acb:
# acb (option) <return>
# give/choose key if asked for (and remember it!)
################################################


# defaults
sftpHOST="duplicity.duckdns.org"
sftpPATH="/upload"
sftpUSER=duplicity
sftpPASSWORD=duplicity
stealthMode=0
useTOR=0
useGPG=1
fullBackups=2
fullBackupAfter=1M
writeCron=1
passphrase=`cat /sys/class/net/*/address | sed 's/\s*\://g' | head -n1 | md5sum | cut -d' ' -f1`;
uniqueID=`cat /sys/class/net/*/address | md5sum | sed 's/\s*\-//g' | head -n1`;

# known_hosts vorhanden?
if [ ! -f "~/.ssh/known_hosts" ]
then
	mkdir -p ~/.ssh
	touch ~/.ssh/known_hosts
fi


# keybase found?
if [ -d "/keybase/team/acbackup/" ]
then
    sftpPATH="//keybase/team/acbackup/data"
    sftpHOST="localhost"
fi

EXECUTABLEDIR=~/bin
acbDIR="$HOME/.acb"
acbFILE="acb.sh"
CONFIG="$acbDIR/acb.ini"
LOGO="acb.png"
gui=1
duplicity=`which duplicity`
env=`which env`
strictHostkeyChecking='--ssh-options="-oStrictHostKeyChecking=no"'
if [ "$USER" == "root" ]
then
	logfile="/var/log/acb.log"
else
	logfile="/tmp/acb-$USER.log"
fi


####
## DON'T CHANGE ANYTHING BELOW - if you don't know what you're doing! ;-)
####


#################
### functions ###
#################
function printconfig {
cat << configEOF
    ID: $md5all
    using TOR: $useTOR
    enrypted data: $useGPG
    stealth mode: $stealthMode
    user@host: $sftpUSER@$sftpHOST
    path on host: $sftpPATH
configEOF
}

function get_config {

# yad running? > get config - otherwise...
if [ "$(dpkg-query -W -f='${Status}' yad 2>>$logfile | grep -c 'ok installed')" -eq 0 ] || [ "`wmctrl  -m 2>>$logfile`" = "" ]
then
  return 0
fi

#echo "gui for read params for configfile"
#newPW=$(mkpasswd /dev/random);
newPW=`cat /sys/class/net/*/address | sed 's/\s*\://g' | head -n1 | md5sum | cut -d' ' -f1`;
ycbCONFIG="$(yad --form --title="config for acb" --item-separator="," \
        --field="backup host (sftp/ssh or 'localhost')" "$sftpHOST" \
        --field="path" "$sftpPATH" \
        --field="username" "$sftpUSER" \
        --field="password" "$sftpPASSWORD" \
        --field="stealth mode:CB" "0,1" \
        --field="use Tor:CB" '0,1'  \
        --field="use GPG:CB" '1,0' \
        --field="full backups:NUM" '2..10' \
        --field="full backup after:CB" '1W,2W,3W,1M,3M' \
        --field="choose password for crypting" "$newPW" \
        --field="schedule $HOME:CB" '1,0' )"

## output yad: qnu7m4h5blagq4fi.onion|duplicity|duplicity|1|1|0|1,000000|3W|
#echo $ycbCONFIG
IFS='|' read -a array <<< "$ycbCONFIG"
        sftpHOST=${array[0]}
        sftpPATH=${array[1]}
        sftpUSER=${array[2]}
        sftpPASSWORD=${array[3]}
        stealthMode=${array[4]}
        useTOR=${array[5]}
        useGPG=${array[6]}
        fullBackups=${array[7]}
        fullBackupAfter=${array[8]}
        passphrase=${array[9]}
        writeCron=${array[10]}
}

function write_config {
mkdir -p $acbDIR
cat << EndOfConfig >> $CONFIG
sftpHOST=$sftpHOST
sftpPATH=$sftpPATH
sftpUSER=$sftpUSER
sftpPASSWORD=$sftpPASSWORD
stealthMode=$stealthMode
useTOR=$useTOR
useGPG=$useGPG
fullBackups=$fullBackups
fullBackupAfter=$fullBackupAfter
passphrase=$passphrase
writeCron=$writeCron
uniqueID=$uniqueID
EndOfConfig

}



function write_crontab {
	if [ "$USER" == "root" ]
	then
		crontab -l | { cat | grep -v \#acb; echo "# scheduling for backup via #acb"; echo "@reboot /usr/bin/acb -u >/dev/null 2>&1 #acb"; echo "0 0 * * * mkdir -p /acb_iso_files; for device in \$(lsblk | grep disk | cut -d' ' -f1); do dd if=/dev/\$device of=/acb_iso_files/\$device.iso bs=512 count=1; done >>$logfile 2>&1 #acb"; echo "0 */3 * * * cd /; flock /tmp/acb.flock env USER=$USER /usr/bin/acb -b >>$logfile 2>&1 #acb"; } | crontab -
	else
		crontab -l | { cat | grep -v \#acb; echo "# scheduling for backup via #acb"; echo "@reboot /usr/bin/acb -u >/dev/null 2>&1 #acb"; echo "0 */3 * * * cd ~/; flock /tmp/acb.flock env USER=$USER /usr/bin/acb -b >>$logfile 2>&1 #acb"; } | crontab -
	fi
}

function delete_crontab {
crontab -l | { cat | grep -v \#acb; } | crontab -
}

function duplicity_status {
    echo "-------------------------------------------------------"
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity collection-status $strictHostkeyChecking -v4 $connectString/$sftpPATH/"$md5all"/ 2>>$logfile 
    echo "-------------------------------------------------------"

}
##############################
#### end functions ###########
##############################

### check config
#################
if [ -e $CONFIG ]
then
  while IFS='=' read -r  var value
    do
        if [ "$var" = "sftpHOST" ] ; then sftpHOST=$value; fi
        if [ "$var" = "sftpPATH" ] ; then sftpPATH=$value; fi
        if [ "$var" = "sftpUSER" ] ; then sftpUSER=$value; fi
        if [ "$var" = "sftpPASSWORD" ] ; then sftpPASSWORD=$value; fi
        if [ "$var" = "stealthMode" ] ; then stealthMode=$value; fi
        if [ "$var" = "useTOR" ] ; then useTOR=$value; fi
        if [ "$var" = "useGPG" ] ; then useGPG=$value; fi
        if [ "$var" = "fullBackups" ] ; then fullBackups=$value; fi
        if [ "$var" = "fullBackupAfter" ] ; then fullBackupAfter=$value; fi
        if [ "$var" = "passphrase" ] ; then passphrase=$value; fi
        if [ "$var" = "writeCron" ] ; then writeCron=$value; fi
	if [ "$var" = "uniqueID" ] ; then uniqueID=$value; fi
    done < $CONFIG
    if [ "$sftpHOST" = "" ]
    then
      rm $CONFIG >/dev/null
    fi
    echo
else
    # yad running? > get config
    if [ "$(dpkg-query -W -f='${Status}' yad 2>>$logfile | grep -c 'ok installed')" -gt 0 ]
    then
      get_config
    fi
    if [ "$sftpHOST" != "" ]
    then
      write_config
      echo "#############################################"
      echo "your configuration $CONFIG:"
      echo
      cat $CONFIG 
      echo "#############################################"
      echo
      if [ "$writeCron" = "1" ]
      then
        write_crontab
      else
        delete_crontab
      fi
    else
      rm $CONFIG >/dev/null 2>>$logfile
    fi
fi

if [ "$useTOR" == "0" ]
then
  torsocks=''
else
  torsocks='torsocks'
fi


# get hostkey if unknown
if [ $(grep $sftpHOST ~/.ssh/known_hosts | wc -l) -lt 1 ] && [ "$sftpHOST" != "localhost" ]
then
	$(echo $torsocks) ssh-keyscan $sftpHOST 2>>$logfile >>~/.ssh/known_hosts || die "Can't fetch hostkey"
fi


if [ "$sftpHOST" != "localhost" ]
then
  connectString="sftp://$sftpUSER:$sftpPASSWORD@$sftpHOST:22"
else
  connectString="file://"
  torsocks=""
  useTOR=0
fi




if [ "$useGPG" == "0" ]
then
  encrypt='--no-encryption'
else
  enrypt=''
fi
if [ "$passphrase" == '' ]
then
  usePASSPHRASE=''
else
  usePASSPHRASE="$env PASSPHRASE=$passphrase"
fi
path=`pwd`;
md5path=`echo "$path" | md5sum | sed 's/\s*\-//g'`;
md5mac=$uniqueID
if [ "$stealthMode" == "1" ] || [ "$1" == "-x" ] || [ "$1" == "-y" ]
then
  if [ "$1" == "-x" ] || [ "$1" == "-y" ]
  then
    md5all=`echo "$md5path$md5mac"$(date +%s) | md5sum | sed 's/\s*\-//g'`;
  else
    md5all=`echo "$md5path$md5mac" | md5sum | sed 's/\s*\-//g'`;
  fi
else
  md5all=$md5mac$path
fi
md5allCache=`echo "$md5path$md5mac" | md5sum | sed 's/\s*\-//g'`;

case "$1" in
-b)
  printconfig
  echo "BACKUP from $path/:"
  #duplicity_status
  rm -rf "$path"/acRestore/ 2>>$logfile
   echo "----------------------------------"
  if [ $fullBackups -gt 0 ]
  then
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity remove-all-but-n-full $fullBackups $strictHostkeyChecking -v4 --force $connectString/$sftpPATH/"$md5all"/ 2>>$logfile 
  fi
  if [ "$path" = "/" ]
  then
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity $strictHostkeyChecking --exclude-other-filesystems --exclude "**/.cache/**" --exclude "/proc/**" --exclude "/sys/**" --exclude "/dev/**" --exclude "/run/**" -v4 $(echo $encrypt) --full-if-older-than $fullBackupAfter "$path" $connectString/$sftpPATH/"$md5all"/ 2>>$logfile  && $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity cleanup $strictHostkeyChecking -v4 $(echo $encrypt) --force $connectString/$sftpPATH/"$md5all"/  2>>$logfile 
  else
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity $strictHostkeyChecking --exclude-other-filesystems --exclude "**/.cache/**" -v4 $(echo $encrypt) --full-if-older-than $fullBackupAfter "$path" $connectString/$sftpPATH/"$md5all"/ 2>>$logfile  && $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity cleanup $strictHostkeyChecking -v4 $(echo $encrypt) --force $connectString/$sftpPATH/"$md5all"/ 2>>$logfile 
  fi
   echo "----------------------------------"
;;

-toIPFS)
  printconfig
  echo "BACKUP from $path/:"
  #duplicity_status
  # set vars
  connectString="file:///"
  torsocks=""
  useTOR=0
  enrypt=''
  usePASSPHRASE="$env PASSPHRASE=$passphrase"
  sftpPATH="acBackup"
  
  FREE=$(df . | tail -1 | awk '{print $4}')
  NEEDED=$(du -x . | tail -1 | awk '{print $1}')
  if [ "$FREE" -lt "$NEEDED" ];
  then
	echo "not enough space on disk!"
	exit 0
  fi


  which=$(which backup2ipfs)
  if [ "$which" == "" ];
  then
              echo "backup2ipfs not found!"
              exit 0
  fi

  rm -rf "$path"/acRestore/ 2>>$logfile
  mkdir -p "$path"/acBackup/ 2>>$logfile
   echo "----------------------------------"
  if [ $fullBackups -gt 0 ]
  then
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity remove-all-but-n-full $fullBackups $strictHostkeyChecking -v4 --force $connectString/$path/acBackup/"$md5all"/ 2>>$logfile
  fi
  if [ "$path" = "/" ]
  then
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity $strictHostkeyChecking --exclude-other-filesystems --exclude "**/acBackup/**" --exclude "**/.cache/**" --exclude "/proc/**" --exclude "/sys/**" --exclude "/dev/**" --exclude "/run/**" -v4 $(echo $encrypt) --full-if-older-than $fullBackupAfter "$path" $connectString/$path/acBackup/"$md5all"/ 2>>$logfile  && $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity cleanup $strictHostkeyChecking -v4 $(echo $encrypt) --force $connectString/$path/acBackup/"$md5all"/  2>>$logfile
  else
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity $strictHostkeyChecking --exclude-other-filesystems --exclude "**/acBackup/**" --exclude "**/.cache/**" -v4 $(echo $encrypt) --full-if-older-than $fullBackupAfter "$path" $connectString/$path/acBackup/"$md5all"/ 2>>$logfile  && $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity cleanup $strictHostkeyChecking -v4 $(echo $encrypt) --force $connectString/$path/acBackup/"$md5all"/ 2>>$logfile
  fi
   echo "----------------------------------"


   backup2ipfs copy
   echo "###############################" >> ipfs-urls.txt 2>/dev/null
   echo "# created with acb - https://github.com/rennschnecke123/acb" >> ipfs-urls.txt 2>/dev/null
   echo "# be sure you have the valid acb.ini file!!!" >> ipfs-urls.txt 2>/dev/null
   echo "###############################" >> ipfs-urls.txt 2>/dev/null

;;

-bLocal)
  printconfig
  echo "BACKUP from $path/:"
  #duplicity_status
  # set vars
  connectString="file:///"
  torsocks=""
  useTOR=0
  enrypt=''
  usePASSPHRASE="$env PASSPHRASE=$passphrase"
  sftpPATH="acBackup"

  FREE=$(df . | tail -1 | awk '{print $4}')
  NEEDED=$(du -x . | tail -1 | awk '{print $1}')
  if [ "$FREE" -lt "$NEEDED" ];
  then
        echo "not enough space on disk!"
        exit 0
  fi


  which=$(which backup2ipfs)
  if [ "$which" == "" ];
  then
              echo "backup2ipfs not found!"
              exit 0
  fi

  rm -rf "$path"/acRestore/ 2>>$logfile
  mkdir -p "$path"/acBackup/ 2>>$logfile
   echo "----------------------------------"
  if [ $fullBackups -gt 0 ]
  then
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity remove-all-but-n-full $fullBackups $strictHostkeyChecking -v4 --force $connectString/$path/acBackup/"$md5all"/ 2>>$logfile
  fi
  if [ "$path" = "/" ]
  then
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity $strictHostkeyChecking --exclude-other-filesystems --exclude "**/acBackup/**" --exclude "**/.cache/**" --exclude "/proc/**" --exclude "/sys/**" --exclude "/dev/**" --exclude "/run/**" -v4 $(echo $encrypt) --full-if-older-than $fullBackupAfter "$path" $connectString/$path/acBackup/"$md5all"/ 2>>$logfile  && $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity cleanup $strictHostkeyChecking -v4 $(echo $encrypt) --force $connectString/$path/acBackup/"$md5all"/  2>>$logfile
  else
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity $strictHostkeyChecking --exclude-other-filesystems --exclude "**/acBackup/**" --exclude "**/.cache/**" -v4 $(echo $encrypt) --full-if-older-than $fullBackupAfter "$path" $connectString/$path/acBackup/"$md5all"/ 2>>$logfile  && $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity cleanup $strictHostkeyChecking -v4 $(echo $encrypt) --force $connectString/$path/acBackup/"$md5all"/ 2>>$logfile
  fi
   echo "----------------------------------"
;;

-bb)
  printconfig
  echo "BACKUP from $path/ without partition limit:"
  #duplicity_status
  rm -rf "$path"/acRestore/ 2>>$logfile
   echo "----------------------------------"
  if [ $fullBackups -gt 0 ]
  then
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity remove-all-but-n-full $fullBackups $strictHostkeyChecking -v4 --force $connectString/$sftpPATH/"$md5all"/ 2>>$logfile
  fi
  if [ "$path" = "/" ]
  then
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity $strictHostkeyChecking --exclude "**/.cache/**" --exclude "/proc/**" --exclude "/sys/**" --exclude "/dev/**" --exclude "/run/**" -v4 $(echo $encrypt) --full-if-older-than $fullBackupAfter "$path" $connectString/$sftpPATH/"$md5all"/ 2>>$logfile  && $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity cleanup $strictHostkeyChecking -v4 $(echo $encrypt) --force $connectString/$sftpPATH/"$md5all"/  2>>$logfile
  else
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity $strictHostkeyChecking --exclude "**/.cache/**" -v4 $(echo $encrypt) --full-if-older-than $fullBackupAfter "$path" $connectString/$sftpPATH/"$md5all"/ 2>>$logfile  && $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity cleanup $strictHostkeyChecking -v4 $(echo $encrypt) --force $connectString/$sftpPATH/"$md5all"/ 2>>$logfile
  fi
   echo "----------------------------------"
;;


-ipfs)
    printconfig
    echo "ID: $md5all"
    ipfsurl="$2"
    pattern="$3"
    if [ "$ipfsurl" = "" ]
    then
	    echo "No ipfs url"
	    exit
    fi

    echo "RESTORE from $ipfsurl to $path/acRestore:"
    #duplicity_status
    rm -rf "$path"/acRestore/ 2>>$logfile
    if [ "$pattern" = "" ]
    then
      $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity restore $strictHostkeyChecking -v4 $(echo $encrypt) "$ipfsurl" "$path"/acRestore/ 2>>$logfile
    else
      mkdir -p "$path"/acRestore/"$pattern"/ 2>>$logfile
      $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity restore $strictHostkeyChecking -v4 $(echo $encrypt) --file-to-restore "$pattern" "$ipfsurl" "$path"/acRestore/"$pattern"/ 2>>$logfile
    fi
;;



-r)
    printconfig
    echo "ID: $md5all"
    pattern="$2"
    echo "RESTORE to $path/acRestore:"
    #duplicity_status
    rm -rf "$path"/acRestore/ 2>>$logfile
    if [ "$pattern" = "" ]
    then
      $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity restore $strictHostkeyChecking -v4 $(echo $encrypt) $connectString/$sftpPATH/"$md5all"/ "$path"/acRestore/ 2>>$logfile 
    else
      mkdir -p "$path"/acRestore/"$pattern"/ 2>>$logfile
      $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity restore $strictHostkeyChecking -v4 $(echo $encrypt) --file-to-restore "$pattern" $connectString/$sftpPATH/"$md5all"/ "$path"/acRestore/"$pattern"/ 2>>$logfile 
    fi    
;;

-fromIPFS)
    printconfig
    echo "ID: $md5all"
    pattern="$2"
    echo "RESTORE to $path/acRestore:"
    #duplicity_status
    # set vars
    connectString="file:///"
    torsocks=""
    useTOR=0
    enrypt=''
    usePASSPHRASE="$env PASSPHRASE=$passphrase"
    sftpPATH="acBackup"

    which=$(which backup2ipfs)
    if [ "$which" == "" ];
    then
		echo "backup2ipfs not found!"
		exit 0
    fi
    backup2ipfs rebuild

    FREE=$(df . | tail -1 | awk '{print $4}')
    NEEDED=$(du -x . | tail -1 | awk '{print $1}')
    if [ "$FREE" -lt "$NEEDED" ];
    then
          echo "not enough space on disk!"
          exit 0
    fi

    rm -rf "$path"/acRestore/ 2>>$logfile
    if [ "$pattern" = "" ]
    then
      $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity restore $strictHostkeyChecking -v4 $(echo $encrypt) $connectString/$path/acBackup/"$md5all"/ "$path"/acRestore/ 2>>$logfile
    else
      mkdir -p "$path"/acRestore/"$pattern"/ 2>>$logfile
      $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity restore $strictHostkeyChecking -v4 $(echo $encrypt) --file-to-restore "$pattern" $connectString/$path/acBackup/"$md5all"/ "$path"/acRestore/"$pattern"/ 2>>$logfile
    fi
;;

-rLocal)
    printconfig
    echo "ID: $md5all"
    pattern="$2"
    echo "RESTORE to $path/acRestore:"
    #duplicity_status
    # set vars
    connectString="file:///"
    torsocks=""
    useTOR=0
    enrypt=''
    usePASSPHRASE="$env PASSPHRASE=$passphrase"
    sftpPATH="acBackup"

    which=$(which backup2ipfs)
    if [ "$which" == "" ];
    then
                echo "backup2ipfs not found!"
                exit 0
    fi

    FREE=$(df . | tail -1 | awk '{print $4}')
    NEEDED=$(du -x . | tail -1 | awk '{print $1}')
    if [ "$FREE" -lt "$NEEDED" ];
    then
          echo "not enough space on disk!"
          exit 0
    fi

    rm -rf "$path"/acRestore/ 2>>$logfile
    if [ "$pattern" = "" ]
    then
      $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity restore $strictHostkeyChecking -v4 $(echo $encrypt) $connectString/$path/acBackup/"$md5all"/ "$path"/acRestore/ 2>>$logfile
    else
      mkdir -p "$path"/acRestore/"$pattern"/ 2>>$logfile
      $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity restore $strictHostkeyChecking -v4 $(echo $encrypt) --file-to-restore "$pattern" $connectString/$path/acBackup/"$md5all"/ "$path"/acRestore/"$pattern"/ 2>>$logfile
    fi
;;

-t)
    printconfig
    echo "ID: $md5all"
    backupTime="$2"
    backupTime=$(date +%s -d "$backupTime")
    pattern="$3"
    echo "RESTORE to $path/acRestore at $backupTime:"
     echo "----------------------------------"
    if [ "$backupTime" != "0" ]
    then
      timeString="--time $backupTime"
    else
      timeString=""
    fi
    rm -rf "$path"/acRestore 2>>$logfile
    mkdir "$path"/acRestore 2>>$logfile
    #duplicity_status
    if [ "$pattern" = "" ]
    then
      $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity restore $strictHostkeyChecking -v4 $(echo $encrypt) $timeString $connectString/$sftpPATH/"$md5all"/ "$path"/acRestore/ 2>>$logfile 
    else
      mkdir -p "$path"/acRestore/"$pattern"/ 2>>$logfile
      $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity restore $strictHostkeyChecking -v4 $(echo $encrypt) --file-to-restore "$pattern" $timeString $connectString/$sftpPATH/"$md5all"/ "$path"/acRestore/"$pattern"/ 2>>$logfile 
    fi
     echo "----------------------------------"
;;

-c)
    printconfig
    echo "CLEANUP backup from $path/:"
    #duplicity_status
     echo "----------------------------------"
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity cleanup $strictHostkeyChecking -v4 $(echo $encrypt) --force $connectString/$sftpPATH/"$md5all"/ 2>>$logfile 
     echo "----------------------------------"
;;


-lb)
    printconfig
    echo "LIST backups from $path/:"
     echo "----------------------------------"
    duplicity_status
     echo "----------------------------------"
;;


-u)
    printconfig
    echo "delete local locks"
    find $HOME/.cache/duplicity/ -type f -delete 2>>$logfile
;;

-i)
    md5all=$2
    printconfig
    echo "RESTORE to $path/acRestore:"
    #duplicity_status
    rm -rf "$path"/acRestore/ 2>>$logfile
     echo "----------------------------------"
    $(echo $torsocks) $duplicity restore $strictHostkeyChecking -v4 $(echo $encrypt) $connectString/"$md5all"/ "$path"/acRestore/ 2>>$logfile 
     echo "----------------------------------"
;;

-s)
    pattern=$2
    printconfig
    echo "SEARCH for $pattern in $path/:"
    #duplicity_status
     echo "----------------------------------"
    collectionstatus=$($(echo $torsocks) $(echo $usePASSPHRASE) $duplicity collection-status $strictHostkeyChecking $connectString/$sftpPATH/"$md5all"/ 2>>$logfile | grep -e Full -e Incremental -e Vollständig -e Schrittweise | sed "s/^\s*\w*//g" | sed "s/\w*\s*$//g" | sed "s/^\s*//g" | sed "s/\s*$//g")
    IFS=$'\n'
    statusAll=''
    find $acbDIR/.cache/ -type f -mtime +14 -delete >/dev/null 2>&1
    for backupTime in $collectionstatus
    do
      backupTime=$(date +%s -d "$backupTime")
      if [ -e $acbDIR/.cache/$sftpHOST-$md5allCache-$backupTime.log.gz ]
      then
	status=$(zcat $acbDIR/.cache/$sftpHOST-$md5allCache-$backupTime.log.gz)
	#touch $acbDIR/.cache/$sftpHOST-$md5allCache-$backupTime.log.gz >/dev/null 2>&1
      else
        status=$($(echo $torsocks) $duplicity list-current-files $strictHostkeyChecking -v4 $(echo $encrypt) --time "$backupTime" $connectString/$sftpPATH/"$md5all"/ 2>>$logfile) 
        if [ ! -e $acbDIR/.cache/ ]
        then
	  mkdir -p $acbDIR/.cache/
	fi
	if [ "$status" != "" ] && [ ! -e $acbDIR/.cache/$sftpHOST-$md5allCache-$backupTime.log.gz ]
	then
	  echo -e "$status" | gzip -c > $acbDIR/.cache/$sftpHOST-$md5allCache-$backupTime.log.gz &
	fi
      fi
      echo -n "."
      status=$(echo -e "$status" | sed "s/^/$backupTime\t/g")
      if [ "$pattern" = "" ]
      then
	statusAll=$(echo -e "$statusAll\n$status")
      else
	statusAll=$(echo -e "$statusAll\n$status" | grep -i "$pattern")
      fi
    done
    if [ "$statusAll" != "" ]
    then
	    statusAll=$(echo -e "$statusAll\n$status" | sort -k 2 | uniq -f 1 | sort)
      echo
      if [ "$pattern" = "" ]
      then
	echo -e "$statusAll"
      else
	echo -e "$statusAll" | grep -i "$pattern"
      fi
    fi
     echo "----------------------------------"
;;

-lf)
    pattern=$2
    printconfig
    echo "SEARCH for $pattern in $path/:"
    #duplicity_status
    IFS=$'\n'
    statusAll=''
     echo "----------------------------------"
    status=$($(echo $torsocks) $duplicity list-current-files $strictHostkeyChecking -v4 $(echo $encrypt) $connectString/$sftpPATH/"$md5all"/ 2>>$logfile)
     echo "----------------------------------"
    if [ ! -e $acbDIR/.cache/ ]
    then
      mkdir -p $acbDIR/.cache/
    fi
    # todo caching for files
    #if [ "$status" != "" ]
    #then
    #  echo -e "$status" | gzip -c > $acbDIR/.cache/$sftpHOST-$md5allCache-$backupTime.log.gz
    #fi
      
      echo -n "."
      status=$(echo -e "$status" | sed "s/^/$backupTime\t/g")
      if [ "$pattern" = "" ]
      then
	statusAll=$(echo -e "$statusAll\n$status" | sort -k 2 | uniq -f 1 | sort)
      else
	statusAll=$(echo -e "$statusAll\n$status" | grep -i "$pattern" | sort -k 2 | uniq -f 1 | sort)
      fi
    
    if [ "$statusAll" != "" ]
    then
      echo
      if [ "$pattern" = "" ]
      then
	echo -e "$statusAll"
      else
	echo -e "$statusAll" | grep -i "$pattern"
      fi
      echo "----------------------------------"
    fi
;;

-v)
    printconfig
    echo "VERIFY backup from $path/:"
    #duplicity_status
     echo "----------------------------------"
    $(echo $torsocks) $(echo $usePASSPHRASE) $duplicity --compare-data --exclude "**/.cache/**" verify $strictHostkeyChecking $(echo $encrypt) $connectString/$sftpPATH/"$md5all"/ "$path"/ 2>>$logfile 
     echo "----------------------------------"
;;

-x)
    useGPG=1
    stealthMode=1
    printconfig
    echo "encryted temp backup"
    rm -rf "$path"/acRestore/ 2>>$logfile
     echo "----------------------------------"
    $(echo $torsocks) $duplicity $strictHostkeyChecking --exclude-other-filesystems --exclude "**/.cache/**" -v4 "$path" $connectString/$sftpPATH/"$md5all"/ 2>>$logfile 
     echo "----------------------------------"
    echo
    echo "#########################################################################"
    echo "# import with:"
    echo "# acb -i \"$sftpPATH/$md5all\""
    echo "#"
    echo "# or without acb:"
    echo "# "$(echo $torsocks) duplicity restore $strictHostkeyChecking -v4 $connectString/$sftpPATH/"$md5all"/ "${PWD##*/}"/
    echo "#"
    echo "#########################################################################"
;;

-y)
    useGPG=0
    stealthMode=1
    printconfig
    echo "unencryted temp backup"
    rm -rf "$path"/acRestore/ 2>>$logfile
     echo "----------------------------------"
    $(echo $torsocks) $duplicity $strictHostkeyChecking --exclude-other-filesystems --exclude "**/.cache/**" --no-encryption -v4 "$path" $connectString/$sftpPATH/"$md5all"/ 2>>$logfile 
     echo "----------------------------------"
    echo
    echo "#########################################################################"
    echo "# import with:"
    echo "# acb -i \"$sftpPATH/$md5all\""
    echo "#"
    echo "# or without acb:"
    echo "# "$(echo $torsocks) duplicity restore $strictHostkeyChecking -v4 --no-encryption $connectString/$sftpPATH/"$md5all"/ "${PWD##*/}"/
    echo "#"
    echo "#########################################################################"
;;

-xx)
    useGPG=1
    stealthMode=1
    printconfig
    echo "encryted temp backup"
    rm -rf "$path"/acRestore/ 2>>$logfile
     echo "----------------------------------"
    $(echo $torsocks) $duplicity $strictHostkeyChecking --exclude "**/.cache/**" -v4 "$path" $connectString/$sftpPATH/"$md5all"/ 2>>$logfile
     echo "----------------------------------"
    echo
    echo "#########################################################################"
    echo "# import with:"
    echo "# acb -i \"$sftpPATH/$md5all\""
    echo "#"
    echo "# or without acb:"
    echo "# "$(echo $torsocks) duplicity restore $strictHostkeyChecking -v4 $connectString/$sftpPATH/"$md5all"/ "${PWD##*/}"/
    echo "#"
    echo "#########################################################################"
;;

-yy)
    useGPG=0
    stealthMode=1
    printconfig
    echo "unencryted temp backup"
    rm -rf "$path"/acRestore/ 2>>$logfile
     echo "----------------------------------"
    $(echo $torsocks) $duplicity $strictHostkeyChecking --exclude "**/.cache/**" --no-encryption -v4 "$path" $connectString/$sftpPATH/"$md5all"/ 2>>$logfile
     echo "----------------------------------"
    echo
    echo "#########################################################################"
    echo "# import with:"
    echo "# acb -i \"$sftpPATH/$md5all\""
    echo "#"
    echo "# or without acb:"
    echo "# "$(echo $torsocks) duplicity restore $strictHostkeyChecking -v4 --no-encryption $connectString/$sftpPATH/"$md5all"/ "${PWD##*/}"/
    echo "#"
    echo "#########################################################################"
;;



*)
cat << otherEOF
    syntax:

    acb [-r] [-rLocal] [-b] [-blocal] [-bb] [-lb] [-lf] [-s] [-t] [-i] [-v] [-x] [-xx] [-y] [-yy] [-c] [-u] [-toIPFS] [-fromIPFS]
    (only one param at a time!)

    -r: restore (<path>)
    -rLocal: like -r on subfolder "acBackup"
    -b: backup
    -bLocal: like -b on subfolder "acBackup"
    -bb: backup without partition limit
    -lb: list backups
    -lf: list files
    -s <PATTERN>: search for string (path/file)
    -t <timestamp> (<path>): restore version at given time with optional path
    -i <ID>: restore known id
    -v: verify backup
    -x: encrypted temp backup
    -xx: encrypted tempp backup without partition limit
    -y: unencrypted temp backup
    -yy: unencrypted temp backup without partition limit
    -c: cleanup backup
    -u: delete local locks
    -toIPFS: store (encrypted!) backup in ipfs *)
    -fromIPFS: get data from ipfs *)

    configuration file: ~/.acb/acb.ini

    *) backup2ipfs needs to be installed:
       https://github.com/rennschnecke123/backup2ipfs

otherEOF
    exit
;;
esac
