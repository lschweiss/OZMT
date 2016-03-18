#! /bin/bash


#Usage:  ./SetLeds.sh FirstBay# LastBay# LEDCODE EnclosureDevPathList
#Ex: ./setLEDs.sh 1 4 F /dev/es/ses3   (Turns ON fault LED for bays 1-4)
#Ex: ./setLEDs.sh 0 0 i /dev/sg[2-4]   (Turns off the Identify LED in bay 0in /dev/sg2 /dev/sg3 /dev/sg4)
#
#Use Upper-Case letters to turn LED on, lower-case off
#A/a Enable/disable visual array rebuild abort indicator
#B/b Enable/disable visual array failed indicator
#C/c Enable/disable visual array critical indicator
#F/f Enable/disable visual fault indicator
#H/h Enable/disable visual spare indicator
#I/i Enable/disable visual Idntify indicator
#K/k Enable/disable visual consistency check indicator
#P/p Enable/disable visual predictive failure indicator
#R/r Enable/disable visual rebuild indicator
#S/s Enable/disable visual remove indicator
#V/v Enable/disable visual request reserved indicator

modes='A B C F H I K P R S V'

for mode in $modes; do
    echo "Setting mode: $mode"
    ./setLEDs.sh 0 13 $mode $1 1>/dev/null
    echo "press enter..."
    read nothing
    ./setLEDs.sh 0 13 $(echo $mode | awk '{print tolower($0)}') $1 1>/dev/null
done
