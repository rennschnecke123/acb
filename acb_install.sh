#!/bin/bash
packages="duplicity python3-paramiko python-paramiko python-gobject-2 yad zenity tor torsocks"
acbDIR="$HOME/.acb"
acbFILEorg="acb.sh"
acbFILE="acb"
acbBINDIR="/usr/bin"
acbLOGODIR="/usr/share/acb"
LOGO="acb.png"
installTry=0

######################
### functions ########
######################
function copy_files {
echo "cp required files etc..."
cp -f $acbFILEorg $acbBINDIR/$acbFILE
chmod 755 $acbBINDIR/$acbFILE
mkdir -p $acbLOGODIR
cp -f $LOGO $acbLOGODIR
mkdir -p $acbDIR
chmod 777 $acbDIR
}


function install_packages {
echo "installation of required packages"
if [ "$(dpkg-query -W -f='${Status}' yad 2>/dev/null | grep -c 'ok installed')" -eq 0 ] && [ $installTry -eq 0 ]
then
  installTry=1
  add-apt-repository -y ppa:webupd8team/y-ppa-manager
  apt-get update
  apt-get -y install yad
fi

if [ $installTYPE = "g" ]
then
	install_acbX
else
	for package in $packages
	do
		if [ "$(dpkg-query -W -f='${Status}' $package 2>/dev/null | grep -c 'ok installed')" -eq 0 ]
		then
			#echo $package
			apt-get -y install $package >/dev/null 2>&1
		fi
	done
fi
echo "all required packges are already installed"
}

function check_installation {
if [ -f "$acbBINDIR/$acbFILE" ]
then
	if [ "$installTYPE" = "g" ]
	then
    install_acbX_check_yad
		yad --center --title="check privious acb installation" \
		--text="<b>Install backup software \n acb</b> \n\n <b>attention: acb is already installed </b> \n we quit here." \
		--button=exit:0 \
		--button="overwrite it" \
		--image="$LOGO" \
		--fontname="Serif bold italic 20"
		if [ "$?" -eq 0 ]
		then
			exit 0
		fi
	else
		echo "package acb is allready installed." ## anpassen für yad oder nicht
	fi
else
		install_packages
fi
}

function install_acbX_check_yad {
## check yad
if [ "$(dpkg-query -W -f='${Status}' yad 2>/dev/null | grep -c 'ok installed')" -eq 0 ]
then
   apt-get -y install yad
   if [ $? -ne 0 ]
   then
     echo "installation of yad failed, switch to console installation"
		 installTYPE="c"
   else
     #install_acbX
     return 0
   fi
fi
}
function install_acbX {

# yad running? > get config - otherwise...
if [ "$(dpkg-query -W -f='${Status}' yad 2>/dev/null | grep -c 'ok installed')" -eq 0 ]
then
  return 0
fi

## show installation menu
yad --center --title="acb Installer" \
--text="Installation of acb: \n\n<b>anonymous crypted backup</b> " \
--button:gtk-yes \
--button:gtk-no \
--image="$LOGO"
start=$?
#echo "wie gehts weiter? $start"
if [ $start = 1 ]
then
#	echo "mit abbruch $start"
	exit 0
else
	### install packages
	yad --center --title="acb installation need to install" \
	--text="$packages" \
	--image="$LOGO" \
	startinstall=$?
	if [ "$startinstall" = "0" ]
	then
		echo "okay, ich breche die intallation ab"
	else
		for package in $packages
		do
			if [ "$(dpkg-query -W -f='${Status}' $package 2>/dev/null | grep -c 'ok installed')" -eq 0 ];
			then
				#echo $package
				apt-get -y install $package >/dev/null 2>&1
			fi

		done
	fi
fi
yad --center --title="acb installation is complete." \
	--text="\n\n<b>have fun with acb</b>      " \
	--image="$LOGO" \
	--button=gtk-quit:0

#copy_files
#install_logrotate
#exit 0
}

function install_acbC {
echo "installation of acb"
#read -p "if you want to start, type (y/N)"
#if [[ $REPLY =~ ^[Yy]$ ]]
if [ 1 ]
then
	echo "we need to install required packages"
  install_packages
else
	echo "okay, bye-bye!"
  exit 0
fi
}

function install_logrotate {
# 4 future use
echo "/var/log/acb.log {
  weekly
  rotate 4
  missingok
  notifempty
  compress
  create 777 root root
}" > /etc/logrotate.d/acb
touch /var/log/acb.log
chmod 777 /var/log/acb.log
}


#######################
#### end functions ####
#######################

echo "Installation of acb start."
if [ "$USER" != "root" ]
then
	echo "you must be root to install required packages"
  echo "try:"
  echo "sudo ./acb_install.sh"
  echo
  read -p "Press any key..."
	exit 1 
fi
echo "Which type of installation do you want?"
echo "(g)raphical or (c)onsole? or e(x)it"
read installTYPE
echo "you choose $installTYPE"

#installTYPE="g"


case $installTYPE in
g)
  echo "okay, we try graphical installation"
  check_installation
	install_acbX
  install_logrotate
;;
c)
  echo "you choose console installation"
  check_installation
  install_acbC
  install_logrotate
;;
*)
exit 0
esac

#install_packages
copy_files

#read -p "Press any key..."


