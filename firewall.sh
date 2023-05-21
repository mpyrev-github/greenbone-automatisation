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

#!/bin/bash

LOG_FILE="/tmp/firewall.log"

#Print input to console and log file
log_print () {
	output=$(echo -e "$(date -u)\t| ")
	output+=$(echo -e $1 | tee /dev/tty)
	echo "$output" >> $LOG_FILE
}

while getopts ":ha:d" opt; do
	case $opt in
		h)
			echo "Use argument -a {ip} to make iptables rules. Connection to IP will be accept by https. All output connections will be deny"
			echo "Use argument -d to delete created iptables rules"
			exit 0
			;;
		a)
			ip=${OPTARG}
			#Isolate output network traffic from project on docker 
			if [[ $ip =~ ^(([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then
				iptables -A OUTPUT -p tcp --dport https -d $ip -j ACCEPT
				iptables -A OUTPUT -j REJECT
				service iptables save >> $LOG_FILE
				systemctl restart iptables
				systemctl restart docker
				log_print "Rules set"
				exit 0
			else
				log_print "Invalid command: parameter ip not valid"
				exit 1
			fi
			;;
		d)
			#Remove isotation output network traffic
			iptables -F OUTPUT
			service iptables save >> $LOG_FILE
			systemctl restart iptables
			systemctl restart docker
			log_print "Rules deleted"
			exit 0
			;;	
		\?)
			log_print "Invalid command: no parameter included with argument $OPTARG"
			exit 1
			;;
	esac
done

#Print if no agrument use
log_print "Invalid command: missing argument -a, -d. Use -h for help."
exit 1
