#!/bin/bash
# Copyright (c) 2019 Johannes Waidner
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.
SUSPEND_AFTER_TIME_M=45
MOUNT_PATH="/dev/null"
DEVICE="not selected"
CONTROL_LOOP_S=30
ALTERNATE_GET_SATE_OF_DRIVE_METHOD=false
SPIN_TRIGGER_EVENT=true
SPIN_UP_EVENT_CMD=":"
SPIN_DOWN_EVENT_CMD=":"
display_help() {
	echo -e "Suspend Disk Script"
	echo -e "\twritten by Johannes Waidner May 2019"
	echo -e "\nUsage:"
	echo -e "Required parameters:"
	echo -e "-p [PATH]\tPath to which the device is mounted."
	echo -e "-d [PATH]\tHard disk which is to be controlled."
	echo -e "\nOptional parameters:"
	echo -e "-t [INT]\tTime in minutes after which the device is suspended. Current: "$SUSPEND_AFTER_TIME_M"m"
	echo -e "-o [INT]\tTime in seconds the control loop sleeps. Events cannot be missed. Current: "$CONTROL_LOOP_S"s"
	echo -e "\t\tHigher values reduce the cpu load, the number of outputs and the trigger commands."
	echo -e "-m\t\tAlternative method to query the status of the hard disk if it does not support smartctl."
	echo -e "\t\tNote that this method may wake up the hard disk."
	echo -e "-a [CMD]\tCommand which is executed once after the hard disk has been turned on."
	echo -e "\t\tIs influenced by the time of the control loop."
	echo -e "-s [CMD]\tCommand which is executed once after the hard disk has been turned off."
	echo -e "\t\tIs influenced by the time of the control loop."
	echo -e "\nTips:"
	echo -e "- try to keep the spin-up and spin-down cycles as low as possible"
	echo -e "- test both status methods and make sure that the chosen method does not wake the hard disk"
	echo -e "- use quotas for the triggered commands e.g. 'echo \"hi\"'." 
	echo -e "- you may have to increase watches use:  echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf"
	echo -e "- the smartd service may have to be changed or deactivated use: systemctl disable smartd"
	echo -e "- the gnome file tracker-store may wack up the drive"
}
while getopts ":t:p:d:o:ma:s:h" opt; do
	  case ${opt} in
	t )
		SUSPEND_AFTER_TIME_M=$OPTARG
		;;
	p )
		MOUNT_PATH=$OPTARG
		;;
	d )
		DEVICE=$OPTARG
		;;
	o )
		CONTROL_LOOP_S=$OPTARG
		;;
	m )
		ALTERNATE_GET_SATE_OF_DRIVE_METHOD=true
		;;
	a )
		SPIN_UP_EVENT_CMD=$OPTARG
		;;
	s )
		SPIN_DOWN_EVENT_CMD=$OPTARG
		;;
	h | \? )
		display_help
		exit 1
		;;
	: )
		echo "Invalid option: $OPTARG requires an argument" >&2
		display_help
		exit 1
		;;
	*  )
		echo "Unimplemented option: -$OPTARG" >&2
		display_help
		exit 1
		;;

	esac
done
shift $((OPTIND -1))

if [ "$EUID" -ne 0 ]; then
	echo "Please run this script as root."
	exit 1
fi

if [ $SUSPEND_AFTER_TIME_M -lt 1 ]; then
	echo "The suspend time was set under one minute."
	echo "Beware, too many parking operations are unhealthy for the hard drive."
	echo "Aborted."
	display_help
	echo 
	exit 1
fi
if [ $CONTROL_LOOP_S -lt 1 ]; then
	echo "The time of the control loop is too short."
	echo "At least 30 seconds are recommended in order to generate as little load as possible."
	echo "Aborted."
	echo 
	display_help
	exit 1
fi
if ! mount | grep "on $MOUNT_PATH" -w -q; then
	echo "The mount path: $MOUNT_PATH is not mounted."
	echo "Aborted."
	echo 
	display_help
	exit 1
fi 
if ! [[ $DEVICE == "/dev/"* ]] || [ ! -e $DEVICE ]; then
	echo "Can not find device: $DEVICE"
	echo "Aborted."
	echo 
	display_help
	exit 1
fi
if [[ $(which inotifywait) == "" ]]; then
	echo "inotifywait is not installed. Please install inotify-tools."
	echo "Aborted."
	echo 
	display_help
	exit 1
fi
if [[ $(which hdparm) == "" ]]; then
	echo "hdparm is not installed. Please install hdparm."
	echo "Aborted."
	echo 
	display_help
	exit 1
fi
if [[ $(which smartctl) == "" ]]; then
	echo "smartctl is not installed. Please install smartmontools."
	echo "Aborted."
	echo 
	display_help
	exit 1
fi

# Here you can choose one return of desire
GET_STATE_OF_DRIVE() {
	if ! $ALTERNATE_GET_SATE_OF_DRIVE_METHOD; then
		# maybe your device does not support smartctl
		smartctl -i -n standby $DEVICE | grep ACTIVE >/dev/null
	else
		# or this command wakes up your drive
		hdparm -C $DEVICE | grep active >/dev/null
	fi
}
#######################
trap "exit" INT TERM ERR
trap "kill 0" EXIT

name=${MOUNT_PATH##*/}
access_info_fifo="/dev/shm/$name"
suspend_time=$(($SUSPEND_AFTER_TIME_M * 60))
echo "set $DEVICE to sleep after "$suspend_time"s with no activity in mountpoint $MOUNT_PATH" >&2

START_MONITOR() {
	echo "" > $access_info_fifo
	inotifywait -m -r $MOUNT_PATH > $access_info_fifo &
	INOTIFY_PID=$!
}
STOP_MONITOR() {
	kill $INOTIFY_PID
}
START_MONITOR
sleep 10
echo "DATE, CURRENT_ACTIVE_STATE, DRIVE_ACTIVE_BUT_NO_FS_INTERACTION_S, CMD_TO_STANDBY_AFTER_S, COUNT_CMD_STANDBY" >&2
COUNT=0
while true
do
	sleep $CONTROL_LOOP_S
	if read line; then
		SECONDS=0
		echo "" > $access_info_fifo
	else
		if [ $SECONDS -ge $suspend_time ]; then
			if GET_STATE_OF_DRIVE; then
				echo $(date '+%Y-%m-%d %H:%M:%S') >&2
				sync
				hdparm -y $DEVICE >&2
				COUNT=$(($COUNT + 1))
				eval "$SPIN_DOWN_EVENT_CMD"
				SPIN_TRIGGER_EVENT=true
			fi
			SECONDS=0
		else
			if ! GET_STATE_OF_DRIVE; then
				SECONDS=0
			fi
		fi
	fi
	if GET_STATE_OF_DRIVE; then
		echo $(date '+%Y-%m-%d %H:%M:%S')",1,"$SECONDS","$suspend_time","$COUNT
		if $SPIN_TRIGGER_EVENT; then
			SPIN_TRIGGER_EVENT=false
			eval "$SPIN_UP_EVENT_CMD"
			STOP_MONITOR
			START_MONITOR
		fi
	else
		echo $(date '+%Y-%m-%d %H:%M:%S')",0,"$SECONDS","$suspend_time","$COUNT
	fi
done < $access_info_fifo 
