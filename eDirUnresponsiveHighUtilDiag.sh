#!/bin/bash
#################################################################
# Novell Inc.
# 1800 South Novell Place
# Provo, UT 84606-6194
# CoPyRiGhT=(c) Copyright 2008, Novell, Inc. All rights reserved
# Script Name: eDirUnresponsiveHighUtilDiag.sh
# Description: Gathers a gcore, supportconfig, and simultaneous
# 			   gstack and top reports to diagnose unresponsive
#              or high utilization eDirectory servers. Includes
#              the option to automatically upload to ftp server.
# 
# Version: 1.0.0
# Creation Date: July 17 2018
# Created by: John Walker  - Novell Technical Services
# Created by: Randy Steele - Novell Technical Services - gstack/top    
# TODO: 
#       - add support for rhel
#       - make gcore optional
#       - change supportconfig -o <platform> to detect platform 
#            and use correct option. Options are as follows:
#            OES: no -o flag
#            SLES: -o OES
#            RHEL: instead of supportconfig, bundle up the following:
#                  - cat /etc/*release
#                  - rpm -qa
#                  - entire directory /.../eDirectory/log
#                  - nds.conf
#                  - ll of DIB directory       
#
# Stretch Goals:
#       - implement ndsd healthcheck script from DSfWDude.com                                        
#################################################################

echo "               ___  _       __  __ __ ____  _____ "
echo "          ___ / _ \(_)___  / / / // // / / / / _ \\"
echo "         / -_) // / / __/ / /_/ // _  / /_/ / // /"
echo "         \\__/____/_/_/    \\____//_//_/\\____/____/ "
echo " "
echo -e "\e[3m===eDirectory Unresponsive and High-Utilization Diagnostics===\e[0m"
echo " "

### VARIABLES ###
SR=""
FTP=""
SUPPORT_EMAIL=""
### END VARIABLES ###

### FUNCTIONS ###
log (){
	echo -e "$@"
	echo -e "$@" >>$GSTACKLOGS
}

logscreen (){
	echo -e "$@"
}

logdate (){
	echo `/bin/date` >>$GSTACKLOGS
}

createDirs(){
        if [ ! -d /tmp/sr$SR ]
        then
                /bin/mkdir -p /tmp/sr$SR && echo "Created /tmp/sr${SR} directory for output files"
        else    echo "Directory already created for output files"
        fi

        if [ ! -d /tmp/sr$SR/core ]
        then
                /bin/mkdir -p /tmp/sr$SR/core && echo "Created /tmp/sr${SR}/core directory for output files"
        else    echo "Directory already created for core files"
        fi

        if [ ! -d /tmp/sr$SR/supportconfig ]
        then
                /bin/mkdir -p /tmp/sr$SR/supportconfig && echo "Created /tmp/sr${SR}/supportconfig directory for output files"
        else    echo "Directory already created for supportconfig files"
        fi

        if [ ! -d /tmp/sr$SR/gstacktop ]
        then
                /bin/mkdir -p /tmp/sr$SR/gstacktop && echo "Created /tmp/sr${SR}/gstacktop directory for output files"
        else    echo "Directory already created for gstacktop files"
        fi
}

### END FUNCTIONS ###

### PARSE CLI FLAGS ###
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -sr|--servicerequest)
    SR="$2"
    shift # past argument
    shift # past value
    ;;
    -ftp|--ftp)
    FTP="$2"
    shift # past argument
    shift # past value
    ;;
    -email|--email)
    EMAIL="$2"
    shift # past argument
    shift # past value
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [ -z "$SR" ]
then
	echo "Please include your SR # as a command line argument and try again. e.g. -sr 101023234545"
	exit
fi

echo SERVICE REQUEST  = "${SR}"
echo FTP              = "${FTP}"
echo SUPPORT EMAIL 	  = "${EMAIL}"
GSTACKLOGS=/tmp/sr$SR/gstacktop/gstackoutput.log
PATHTOCONF=/etc/opt/novell/eDirectory/conf/nds.conf
VARDIR=`/bin/cat $PATHTOCONF |grep -i "vardir" |awk -F = '{print $2}'`
NDSD_PID=`/bin/cat $VARDIR/ndsd.pid`
### END PARSE CLI FLAGS ###

if [ -z "$NDSD_PID" ]
then
	echo "\$NDSD_PID is empty - Aborting execution. Make sure ndsd is running and try again."
	exit
fi

### GSTACK/TOP ###
echo " "
createDirs

echo " "
echo '***Taking simultaneous gstack/top reports.***'
echo " "
sleep 2
	
while (true)
do	
	GSTACKCOUNTER=0
	while [ $GSTACKCOUNTER -lt 5 ]
	do
		GSTACKCOUNTER=`expr $GSTACKCOUNTER + 1`
		GSTACKLOGS=/tmp/sr$SR/gstacktop/gstack$GSTACKCOUNTER.log
		logdate
		log "[*] Grabbing a gstack and writing to $GSTACKLOGS for the ndsd process PID# $NDSD_PID " 
		/bin/date >>$GSTACKLOGS
		log "***Start writing Top stats for ndsd PID $NDSD_PID***"
		/usr/bin/top -b -n1 -p $NDSD_PID >>$GSTACKLOGS
		log "" >>$GSTACKLOGS
		log "-----------------top -H per thread %CPU of ndsd Process----------------" >>$GSTACKLOGS
		/usr/bin/top -b -n1 -H -p $(pidof ndsd) |grep ndsd >>$GSTACKLOGS
		log "[*] Finished writing Top stats for ndsd PID $NDSD_PID successfully! "
		echo "" >>$GSTACKLOGS
		log "***Start of gstack data writing***"
		echo "--------------- Start of gstack thread data --------------" >>$GSTACKLOGS
		/usr/bin/gstack $NDSD_PID >>$GSTACKLOGS
		echo "---------------- Finished gstack thread data ---------------" >>$GSTACKLOGS
		log "[*] Finished writing $GSTACKLOGS log successfully! "
		log "[*] Sleeping for 10 seconds! "
		sleep 10
	done
	echo "" >>$GSTACKLOGS # NEW LINE 
	log "--------------------------------------------------------------------" 
	echo "" >>$GSTACKLOGS

	log "[*]------ Finished gathering all gstack/top requirements --------- "
	logscreen ""
	break
done
### END GSTACK/TOP ###

### GCORE ###
echo " "
echo "***Running gcore against ndsd process.***"
echo " "
sleep 2
gcore -o /tmp/sr$SR/core/core $NDSD_PID

echo " "
echo "***Running novell-getcore against generated core dump.***"
echo " "
sleep 2
cd /tmp/sr$SR/core/
novell-getcore -b /tmp/sr$SR/core/core.$NDSD_PID /opt/novell/eDirectory/sbin/ndsd

echo " "
echo "***Removing /tmp/sr$SR/core/core.${NDSD_PID}***"
echo " "
sleep 2
rm /tmp/sr$SR/core/core.$NDSD_PID
### END GCORE ###

### SUPPORTCONFIG ###
# todo: check if it is an oes server or not
echo " "
echo "***Generating a supportconfig.***"
echo " "
sleep 2
supportconfig -o OES -R /tmp/sr$SR/supportconfig
### SUPPORTCONFIG ###

echo " "
echo "***Compressing the files.***"
echo " "
sleep 2
tar -zcvf /tmp/sr$SR.tar.gz /tmp/sr$SR
rm -rf /tmp/sr$SR/

echo " "
echo "***The data is located at /tmp/sr$SR.tar.gz.***"
echo " "
sleep 2

if [ $FTP='yes' ];
then
	echo '***Uploading to ftp.novell.com/incoming...***'
	echo " "
	sleep 2
	curl -T /tmp/sr$SR.tar.gz ftp://ftp.novell.com/incoming/sr$SR.tar.gz

	if [ -z "$EMAIL" ]
	then
		echo " "
		echo "No email address specified. Please notify your support engineer that the file upload is complete."
		echo " "
	else
		echo " "
		echo "Notifying ${EMAIL} that the upload has completed."
		echo " "
		sleep 2
		mail -s "SR # ${SR} unresponsive/high-util diagnostic upload complete" $EMAIL <<< "File is located at ftp.novell.com/incoming/sr${SR}.tar.gz."
	fi
else
	echo "Please provide this file to your support engineer."
fi

echo "***Script complete. Please manually restart the ndsd service now.***"

exit
