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
			#Isolate network traffic from project on docker, but accept local connections 
			if [[ $ip =~ ^(([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then
				intf=$(ip -o link show | awk -F: '{print $2}' | cut -d ' ' -f2 | grep enp | head -n 1)

				iptables -F INPUT
				iptables -F OUTPUT
				iptables -I OUTPUT 1 -p tcp --dport https -d $ip -j ACCEPT
				iptables -I INPUT 1 -p tcp --sport https -s $ip -j ACCEPT
				iptables -I OUTPUT 2 -p tcp --dport 8080 -d 127.0.0.1 -j ACCEPT
				iptables -I INPUT 2 -p tcp --sport 8080 -s 127.0.0.1 -j ACCEPT
				iptables -I OUTPUT 3 -p tcp --dport 5433 -d 127.0.0.1 -j ACCEPT
				iptables -I INPUT 3 -p tcp --sport 5433 -s 127.0.0.1 -j ACCEPT
				iptables -I OUTPUT 4 -p tcp -d 127.0.0.1 -j ACCEPT
				iptables -I INPUT 4 -p tcp -s 127.0.0.1 -j ACCEPT
				iptables -I OUTPUT 5 -j REJECT
				iptables -I INPUT 5 -j REJECT
				iptables -I DOCKER-ISOLATION-STAGE-1 2 -i $intf -j DROP
				
				log_print "Rules set"
				exit 0
			else
				log_print "Invalid command: parameter ip not valid"
				exit 1
			fi
			;;
		d)
			#Remove isotation network traffic
			iptables -F INPUT
			iptables -F DOCKER-ISOLATION-STAGE-1
			iptables -F OUTPUT
			
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
