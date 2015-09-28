#!/bin/bash

#################################################################
# 
# Copyright DataON Storage 03/30/2013 ver 1.5
#
#################################################################

HOST=`hostname` 
OS=`uname -s`
OS_VERSION=`uname -v`
OS_RELEASE=`uname -r`
OS_ALL=`uname -a`

CURRENT_TIME=`date +%Y%m%d-%H%M%S`
TARGET_LOCATION="/tmp"
TARGET_DIR=$HOST-$CURRENT_TIME
TAR_FILE=$TARGET_LOCATION/$TARGET_DIR.tar
GZIP_FILE=$TAR_FILE.gz

output() {
	echo "==========================================================="
	echo "$@"
	echo "==========================================================="
	eval "$@"
	echo ""

}

debug() {
	echo $HOST
	echo $OS
	echo $OS_VERSION
	echo $OS_RELEASE
	echo $OS_ALL

}

system_info() {
	echo "Collecting System Info ...."
	
	output "uname -a" > $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "cat /etc/release" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "uptime" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "prtdiag" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "echo \"::memstat\" | mdb -k" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "echo \"::arc\" | mdb -k" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "prtconf -D" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "ps auxww" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "ptree" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "prstat -s rss -c 2 2" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "df -k" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "svcs" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "swap -sh" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "echo \"::interrupts\" | mdb -k" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "cfgadm -al" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1
	output "echo $PATH" >> $TARGET_LOCATION/$TARGET_DIR/sysinfo.txt 2>&1

	cp /etc/system $TARGET_LOCATION/$TARGET_DIR
	cp /kernel/drv/scsi_vhci.conf $TARGET_LOCATION/$TARGET_DIR

#	CPU Info	#
	output "psrinfo -pv" > $TARGET_LOCATION/$TARGET_DIR/psrinfo.txt 2>&1
	output "psrinfo -v" >> $TARGET_LOCATION/$TARGET_DIR/psrinfo.txt 2>&1
	
	output "lspci" > $TARGET_LOCATION/$TARGET_DIR/lspci.txt 2>&1
	output "prtconf -pv" > $TARGET_LOCATION/$TARGET_DIR/prtconf-pv.txt 2>&1
	output "prtconf -Dv" > $TARGET_LOCATION/$TARGET_DIR/prtconf-Dv.txt 2>&1
	output "cfgadm -alv" > $TARGET_LOCATION/$TARGET_DIR/cfgadm.txt 2>&1
	output "kstat" > $TARGET_LOCATION/$TARGET_DIR/kstat.txt 2>&1
	output "sasinfo hba -v" > $TARGET_LOCATION/$TARGET_DIR/sasinfo.txt 2>&1
	output "echo \"::mptsas -t\" |mdb -k" > $TARGET_LOCATION/$TARGET_DIR/mptsasinfo.txt 2>&1
	output "cat ~/.bash_history" > $TARGET_LOCATION/$TARGET_DIR/history.txt 2>&1


	if [ -f "/usr/bin/dpkg" ]; then
		output "dpkg -l" > $TARGET_LOCATION/$TARGET_DIR/dpkg.txt 2>&1
		cp /etc/apt/sources.list $TARGET_LOCATION/$TARGET_DIR
		output "echo \"Nexenta Version\"" > $TARGET_LOCATION/$TARGET_DIR/nexenta.txt 2>&1
		dpkg -l | grep "Nexenta Management" >> $TARGET_LOCATION/$TARGET_DIR/nexenta.txt 2>&1
		output "cat /var/lib/nza/nlm.key" >> $TARGET_LOCATION/$TARGET_DIR/nexenta.txt 2>&1
		output "echo \"Nexenta Plugin\"" >> $TARGET_LOCATION/$TARGET_DIR/nexenta.txt 2>&1
		dpkg -l | grep "nxplugin" >> $TARGET_LOCATION/$TARGET_DIR/nexenta.txt 2>&1
	fi


}

network_info() {
	echo "Collecting Network Info ...."

	output "ifconfig -a" > $TARGET_LOCATION/$TARGET_DIR/network_info.txt 2>&1
	output "dladm show-link" >> $TARGET_LOCATION/$TARGET_DIR/network_info.txt 2>&1
	output "dladm show-aggr -L" >> $TARGET_LOCATION/$TARGET_DIR/network_info.txt 2>&1
	output "netstat -rn" >> $TARGET_LOCATION/$TARGET_DIR/network_info.txt 2>&1
	output "netstat -s" >> $TARGET_LOCATION/$TARGET_DIR/network_info.txt 2>&1
	output "netstat -f inet" >> $TARGET_LOCATION/$TARGET_DIR/network_info.txt 2>&1
	output "ntpq -np" >> $TARGET_LOCATION/$TARGET_DIR/network_info.txt 2>&1
	cp /etc/nsswitch.conf $TARGET_LOCATION/$TARGET_DIR
}

zfs_info() {
	echo "Collecting ZFS Info ...."

	output "zpool list" > $TARGET_LOCATION/$TARGET_DIR/zfs_info.txt 2>&1
	output "zpool status" >> $TARGET_LOCATION/$TARGET_DIR/zfs_info.txt 2>&1
	output "zfs list" >> $TARGET_LOCATION/$TARGET_DIR/zfs_info.txt 2>&1
	output "zfs list -t snapshot" >> $TARGET_LOCATION/$TARGET_DIR/zfs_info.txt 2>&1
	output "zpool iostat -v 1 5" >> $TARGET_LOCATION/$TARGET_DIR/zfs_info.txt 2>&1
	output "iostat -xen" >> $TARGET_LOCATION/$TARGET_DIR/zfs_info.txt 2>&1
	output "iostat -En" >> $TARGET_LOCATION/$TARGET_DIR/zfs_info.txt 2>&1
	output "echo \"::zfs_params\" |mdb -k" >> $TARGET_LOCATION/$TARGET_DIR/zfs_info.txt 2>&1

	output "zdb" > $TARGET_LOCATION/$TARGET_DIR/zdb_info.txt 2>&1
	
	output "hddisco" > $TARGET_LOCATION/$TARGET_DIR/hddisco.txt 2>&1
	output "mpathadm list lu" > $TARGET_LOCATION/$TARGET_DIR/mpathadm.txt 2>&1
}

getlogs()
{	
	# serial number 
	output "sg_inq -p 0x80 /dev/rdsk/$1" > $TARGET_LOCATION/$TARGET_DIR/disk/$1.log 2>&1	
	
	# device log	
	output "sg_logs -a /dev/rdsk/$1" >> $TARGET_LOCATION/$TARGET_DIR/disk/$1.log 2>&1
	output "sg_logs -aH /dev/rdsk/$1" > $TARGET_LOCATION/$TARGET_DIR/disk/raw/$1.log 2>&1

	# report
	echo $1 >> $TARGET_LOCATION/$TARGET_DIR/disk/summary.log
	cat $TARGET_LOCATION/$TARGET_DIR/disk/$1.log | grep -e "Errors corrected with possible delays" -e "Total uncorrected errors" -e "Non-medium error count =" -e "Current temperature =" -e "negotiated logical link rate: phy enabled" -e "Phy reset problem =" >> $TARGET_LOCATION/$TARGET_DIR/disk/summary.log
	echo $1 Media Error Scan = `cat $TARGET_LOCATION/$TARGET_DIR/disk/$1.log | grep -e "Medium scan parameter" | wc -l` >> $TARGET_LOCATION/$TARGET_DIR/disk/summary.log

	
}

disk_info() {
	echo "Collecting Disk Info ...."

	mkdir -p $TARGET_LOCATION/$TARGET_DIR/disk
	mkdir -p $TARGET_LOCATION/$TARGET_DIR/disk/raw

	disks=`format </dev/null | grep c*[0-9]t. | nawk '{print $2}'`

	i=0
	for disk in $disks
	do
		let i=i+1
		echo -e $i"\t"$disk `getlogs $disk` ... 
	done
}

share_info() {
	cp /etc/krb5/krb5.conf $TARGET_LOCATION/$TARGET_DIR

}

message_log() {
	echo "Collecting Message Info ...."

	output "dmesg" > $TARGET_LOCATION/$TARGET_DIR/dmesg.txt 2>&1
	mkdir -p $TARGET_LOCATION/$TARGET_DIR/var_log
	#cp -rL /var/log/* $TARGET_LOCATION/$TARGET_DIR/var_log
	cp -rL /var/adm/message* $TARGET_LOCATION/$TARGET_DIR/var_log
}

fm_log() {
	echo "Collecting fmdump Info ...."
	output "fmdump -e" > $TARGET_LOCATION/$TARGET_DIR/fmdump_e.txt 2>&1
	output "fmdump -et 24h" > $TARGET_LOCATION/$TARGET_DIR/fmdump_et_24h.txt 2>&1
	output "fmdump -eV" > $TARGET_LOCATION/$TARGET_DIR/fmdump_eV.txt 2>&1
	output "fmdump -eVt 24h" > $TARGET_LOCATION/$TARGET_DIR/fmdump_eVt_24h.txt 2>&1
	output "fmadm faulty" > $TARGET_LOCATION/$TARGET_DIR/fmadm_faulty.txt 2>&1
}

rsf_log() {
	mkdir -p $TARGET_LOCATION/$TARGET_DIR/RSF-1
	cp -rL /opt/HAC/RSF-1/etc $TARGET_LOCATION/$TARGET_DIR/RSF-1/
	if [ -d "/opt/HAC/RSF-1/log" ]; then
		echo "Collecting HA Info ...."
		cp -rL /opt/HAC/RSF-1/log $TARGET_LOCATION/$TARGET_DIR/RSF-1/	
	fi
}

ses_log() {

	if [ -d "/dev/es" ]; then
		echo "Collecting SES Info...."
		mkdir -p $TARGET_LOCATION/$TARGET_DIR/ses
		#if [ -f "/usr/lib/fm/fmd/fmtopo" ]; then 
			#output "/usr/lib/fm/fmd/fmtopo" > $TARGET_LOCATION/$TARGET_DIR/ses/fmtopo.txt 2>&1
		#fi	
		if [ -d "/usr/local/dataonstorman/logs" ]; then 
       			cp -r /usr/local/dataonstorman/logs $TARGET_LOCATION/$TARGET_DIR/ses
		fi	
		if [ -d "/usr/local/dataonstorman/license" ]; then 
       			cp -r /usr/local/dataonstorman/license $TARGET_LOCATION/$TARGET_DIR/ses
		fi	
		for EACH in `ls /dev/es`
		do
       			output "sg_ses -p 0x0 /dev/es/$EACH" > $TARGET_LOCATION/$TARGET_DIR/ses/$EACH.txt 2>&1	
       			output "sg_ses -p 0x1 /dev/es/$EACH" >> $TARGET_LOCATION/$TARGET_DIR/ses/$EACH.txt 2>&1	
       			output "sg_ses -p 0x2 /dev/es/$EACH" >> $TARGET_LOCATION/$TARGET_DIR/ses/$EACH.txt 2>&1	
       			output "sg_ses -p 0x4 /dev/es/$EACH" >> $TARGET_LOCATION/$TARGET_DIR/ses/$EACH.txt 2>&1	
       			output "sg_ses -p 0x5 /dev/es/$EACH" >> $TARGET_LOCATION/$TARGET_DIR/ses/$EACH.txt 2>&1	
       			output "sg_ses -p 0x7 /dev/es/$EACH" >> $TARGET_LOCATION/$TARGET_DIR/ses/$EACH.txt 2>&1	
       			output "sg_ses -p 0xa /dev/es/$EACH" >> $TARGET_LOCATION/$TARGET_DIR/ses/$EACH.txt 2>&1	
       			output "sg_ses -p 0xf -H /dev/es/$EACH" >> $TARGET_LOCATION/$TARGET_DIR/ses/$EACH.txt 2>&1	
       			output "sg_ses -p 0x80 /dev/es/$EACH" >> $TARGET_LOCATION/$TARGET_DIR/ses/$EACH.txt 2>&1	
		done
	fi


}

check_sg3() {

	pkg=$(dpkg -s sg3-utils 2>null|grep " installed")
	if [ "$pkg" == "" ]; then
        	echo "sg3-utils is not install. Setting up sg3-utils"
		apt-get --force-yes --yes install sg3-utils >/dev/null 2>&1 
	fi
}

# create temp directory /tmp/dataon
if [ -d "$TARGET_LOCATION/$TARGET_DIR" ]; then
	rm -r $TARGET_LOCATION/$TARGET_DIR
fi
mkdir $TARGET_LOCATION/$TARGET_DIR

system_info 
network_info
message_log
fm_log
zfs_info
share_info
if [ -d "/opt/HAC/RSF-1" ]; then
	rsf_log
fi
check_sg3
disk_info
ses_log

echo "Collecting System Info Done!"

tar -cf $TAR_FILE $TARGET_LOCATION/$TARGET_DIR 2>/dev/null
gzip -f $TAR_FILE

echo "Please send $GZIP_FILE to your vendor"
