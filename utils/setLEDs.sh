#!/bin/bash
#
# Written by Daniel Lethe - Daniel@santools.com
#
if [ $# -eq 0 ] ; then
 echo "Usage:  ./SetLeds.sh FirstBay# LastBay# LEDCODE EnclosureDevPathList"
 echo 'Ex: ./setLEDs.sh 1 4 F /dev/es/ses3   (Turns ON fault LED for bays 1-4)'
 echo 'Ex: ./setLEDs.sh 0 0 i /dev/sg[2-4]   (Turns off the Identify LED in bay 0in /dev/sg2 /dev/sg3 /dev/sg4)'
 echo
 echo "Use Upper-Case letters to turn LED on, lower-case off"
 echo "A/a Enable/disable visual array rebuild abort indicator"
 echo "B/b Enable/disable visual array failed indicator"
 echo "C/c Enable/disable visual array critical indicator"
 echo "F/f Enable/disable visual fault indicator"
 echo "H/h Enable/disable visual spare indicator"
 echo "I/i Enable/disable visual Idntify indicator"
 echo "K/k Enable/disable visual consistency check indicator"
 echo "P/p Enable/disable visual predictive failure indicator"
 echo "R/r Enable/disable visual rebuild indicator"
 echo "S/s Enable/disable visual remove indicator"
 echo "V/v Enable/disable visual request reserved indicator"
 exit 1
fi
startbay=$1
endbay=$2
led=$3
shift; shift; shift
SESPATH=$*
CMDLINE=""

thisbay=$startbay
while [ $thisbay -le $endbay ] ; do
 CMDLINE="$CMDLINE -EPL$led$thisbay"
 (( thisbay = $thisbay + 1 ))
done

/etc/smartmon-ux $CMDLINE $SESPATH

