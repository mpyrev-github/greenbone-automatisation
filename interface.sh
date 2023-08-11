#!/bin/bash

# -*- coding: utf-8 -*-
# Copyright (C) 2023 Sole proprietor Pyrev Mikhail Sergeevich
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

LOG_FILE="/tmp/interface.log"

#Print input to console and log file
log_print () {
	output=$(echo -e "$(date -u)\t| ")
	output+=$(echo -e $1 | tee /dev/tty)
	echo "$output" >> $LOG_FILE
}

#Error print function
error_exit()
{
    log_print "Error: $1"
    exit 1
}

#Try to find main interface
intf=$(ip -o link show | awk -F: '{print $2}' | cut -d ' ' -f2 | grep enp | head -n 1)
if [ -z "$intf" ]; then
	intf=$(ip -o link show | awk -F: '{print $2}' | cut -d ' ' -f2 | grep ens | head -n 1)
fi
if [ -z "$intf" ]; then
	echo "Invalid interface: script support enp* and ens* interfaces"
	exit 1
fi

#Change IP-address to settled in argument and turn off promiscuous mode
set_ip_addr () {
	ip link set dev $intf promisc off >> $LOG_FILE 2>&1 || error_exit "set $intf promisc off"
	nmcli -f GENERAL.STATE c s $intf | grep -q 'activ'
	if [ $? -eq 0 ];then 
		nmcli con down $intf >> $LOG_FILE 2>&1 || error_exit "$intf down"
	fi
	nmcli con mod $intf ipv4.method manual ipv4.addresses "$1" >> $LOG_FILE 2>&1 || error_exit "$intf set ipv4 address"
	nmcli con up $intf >> $LOG_FILE 2>&1 || error_exit "$intf down"
}

#Disable and down interface
clear_ip_addr () {
	nmcli -f GENERAL.STATE c s $intf | grep -q 'activ'
	if [ $? -eq 0 ];then 
		nmcli con down $intf >> $LOG_FILE 2>&1 || error_exit "$intf down"
	fi
	nmcli con mod $intf ipv4.method disabled ipv4.addresses "" >> $LOG_FILE 2>&1 || error_exit "$intf disable"
}

while getopts ":ha:dp" opt; do
	case $opt in
		h)
			echo "Use argument -a {ip} to make active interface and set ip-address"
			echo "Use argument -p to make passive (promisc) interface"
			echo "Use argument -d to delete ip from interface"
			exit 0
			;;
		a)
			ip=${OPTARG}
			if [[ $ip =~ ^(([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(0?[0-9]|[1-2][0-9]|3[0-2]))?$  ]]; then
				if [[ $ip =~ ^(([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then
					set_ip_addr $ip/24
					log_print "Interface is active. IP-address $ip/24 set"
					exit 0
				else
					set_ip_addr $ip
					log_print "Interface is active. IP-address $ip set"
					exit 0
				fi
			else
				log_print "Invalid command: parameter ip not valid"
				exit 1
			fi
			;;
		d)
			clear_ip_addr
			log_print "Interface is disabled. IP-address deleted"
			exit 0
			;;
		p)
			clear_ip_addr
			ip link set dev $intf promisc on >> $LOG_FILE 2>&1 || error_exit "set $intf promisc on"
			log_print "Interface is passive (promisc)"
			exit 0
			;;			
		\?)
			log_print "Invalid command: no parameter included with argument $OPTARG"
			exit 1
			;;
	esac
done

log_print "Invalid command: missing argument -a, -d. Use -h for help."
exit 1
