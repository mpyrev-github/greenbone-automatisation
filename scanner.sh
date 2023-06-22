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

LOG_FILE="/tmp/scanner.log"
FILE_PATH="/tmp"
GREENBONE_PATH="/opt/greenbone"

#Print input to console and log file
log_print () {
	output=$(echo -e "$(date -u)\t| ")
	output+=$(echo -e $1 | tee /dev/tty)
	echo "$output" >> $LOG_FILE
}

#Trap ctrl-c and call ctrl_c() and delete process in greenbone
trap ctrl_c SIGINT

function ctrl_c() {
    if ! [[ $task_id == "" ]]; then
		gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<stop_task task_id=\"$task_id\"/>" &>> $LOG_FILE
		gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<delete_task task_id=\"$task_id\"/>" &>> $LOG_FILE
	fi
	if ! [[ $thosts_id == "" ]]; then
		gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<delete_target target_id=\"$thosts_id\"/>" &>> $LOG_FILE
	fi
	log_print "Task stopped and deleted. Target deleted too"
	exit 1
}

#Check privilege of user
if [[ $EUID == 0 ]]; then
	log_print "Invalid command: user must be non-root"
	exit 1
fi

#Use nmap scanner for check available host and make .xml file with them
nmap_scan () {
	if [[ $1 =~ ^(([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(0?[0-9]|[1-2][0-9]|3[0-2]))?$ ]]; then
		if [[ -n $2 ]]; then 
			if [[ $2 =~ ^(([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then
				nmap -sn $1 --exclude $2 -oX - > $FILE_PATH/nmap_hosts.xml
			else
				log_print "Invalid command: parameter exclude not valid"
			fi
		else
			nmap -sn $1 -oX - > $FILE_PATH/nmap_hosts.xml
		fi
		thosts="$(grep -Po '<address addr="\K[^"]+' /tmp/nmap_hosts.xml | awk '{printf "%s%s", (NR==1? "" : ","), $NF} END{ print "" }')"
		if [[ $thosts == "" ]]; then
			log_print "No hosts in net. Exiting..."
			exit 0
		fi
	else
		log_print "Invalid command: parameter net not valid"
		exit 1
	fi
}

#Update databases of greenbone (NVT,SCAP,CERT,GVMD_DATA)
update () {
	pull_err="$(docker-compose -f $GREENBONE_PATH/docker-compose.yml -p greenbone-community-edition pull notus-data vulnerability-tests scap-data dfn-cert-data cert-bund-data report-formats data-objects 2>&1 | grep "error")"
	up_err="$(docker-compose -f $GREENBONE_PATH/docker-compose.yml -p greenbone-community-edition up -d notus-data vulnerability-tests scap-data dfn-cert-data cert-bund-data report-formats data-objects 2>&1 | grep "error")"
	if ! [[ $pull_err == "" && $up_err == "" ]]; then
		log_print "Update error"
		pull_err >> $LOG_FILE
		up_err >> $LOG_FILE
		exit 1
	fi
}

while getopts ":de:hs:uv:" opt; do
	case $opt in
		d)
			n=2

			while true; do
				rm_task_id="$(gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<get_tasks/>" | xmllint --xpath '/*/task/@id' - | cut -d'"' -f$n)"
				if [[ $rm_task_id =~ ^.{8}-.{4}-.{4}-.{4}-.{12}$ ]]; then
					gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<stop_task task_id=\"$rm_task_id\"/>" &>> $LOG_FILE
					gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<delete_task task_id=\"$rm_task_id\"/>" &>> $LOG_FILE
					log_print "Task $rm_task_id stopped and removed"
				else
					log_print "All tasks stopped and removed"
					n=2
					break
				fi
				n=$((n + 2))
			done

			while true; do
				rm_target_id="$(gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<get_targets/>" | xmllint --xpath '/*/target/@id' - | cut -d'"' -f$n)"
				if [[ $rm_target_id =~ ^.{8}-.{4}-.{4}-.{4}-.{12}$ ]]; then
					gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<delete_target target_id=\"$rm_target_id\"/>" &>> $LOG_FILE 
					log_print "Target $rm_target_id removed"
				else
					log_print "All targets removed"
					break
				fi
				n=$((n + 2))
			done
			exit 0
			;;
		e)
			exclude_ip=${OPTARG}
			;;
		h)
			echo "Use argument -d to delete all data in greenbone"
			echo "Use argument -e {ip} to exclude some ip for scan available hosts by nmap. Use it whith argument -s or -v"
			echo "Use argument -s {net} to scan available hosts by nmap. Result will be save in $FILE_PATH/nmap_hosts.xml"
			echo "Use argument -u to update vulnerability database for openVAS"
			echo "Use argument -v {net} to scan hosts vulnerability by openVAS. Reports will be save in $FILE_PATH/"
			exit 0
			;;
		s)
			status="nmap"
			net=${OPTARG}
			;;
		u)
			update
			log_print "Update completed"
			exit 0
			;;	
		v)
			status="openVAS"
			net=${OPTARG}
			;;
		\?)
			log_print "Invalid command: no parameter included with argument $OPTARG"
			exit 1
			;;
	esac
done

#Scan hosts and make xml-file with them
if [[ $status == "nmap" ]]; then
	nmap_scan $net $exclude_ip
	log_print "Scanned hosts: $thosts"
	echo "Information written to file $FILE_PATH/nmap_hosts.xml"
	exit 0
fi

#Scan vulnerabilities of available hosts (from nmap)
if [[ $status == "openVAS" ]]; then
	nmap_scan $net $exclude_ip
	echo -e "$(date -u) \t| Target hosts: $thosts" &>> $LOG_FILE
	#Put target hosts into greenbone
	thosts_id="$(gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<create_target><name>Target created at $(date +%s)</name><hosts>"$thosts"</hosts><port_list id=\"33d0cd82-57c6-11e1-8ed1-406186ea4fc5\"/></create_target>" | awk -F\" '{print $6}')"
	echo -e "$(date -u) \t| Target hosts id: $thosts_id" &>> $LOG_FILE
	#Make task for scan with target hosts
	task_id="$(gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<create_task><name>Task created at $(date +%s)</name><target id=\"$thosts_id\"/><config id=\"daba56c8-73ec-11df-a475-002264764cea\"/><scanner id=\"08b69003-5fc2-4037-a479-93b440211c73\"/></create_task>" | awk -F\" '{print $6}')"
	echo -e "$(date -u) \t| Task id: $task_id" &>> $LOG_FILE
	#Start task for scan
	report_id="$(gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<start_task task_id=\"$task_id\"/>" | xmllint --xpath '/*/report_id/text()' - )"
	echo -e "$(date -u) \t| Report id: $report_id" &>> $LOG_FILE
	progress="$(gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<get_tasks task_id=\"$task_id\"/>" | xmllint --xpath '//get_tasks_response/task/progress/text()' - )"
	#Check status of scan
	while [ $progress != "-1" ]; do
		echo -ne "Progress: $progress% \r"
		progress="$(gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<get_tasks task_id=\"$task_id\"/>" | xmllint --xpath '//get_tasks_response/task/progress/text()' - )" 2>> $LOG_FILE
		sleep 1
	done
	echo "Progress: 100%"
	#Get report from scan
	gvm-cli --gmp-username admin --gmp-password admin socket --socketpath /tmp/gvm/gvmd/gvmd.sock --xml "<get_reports report_id=\"$report_id\" format_id=\"a994b278-1f62-11e1-96ac-406186ea4fc5\" details=\"1\" filter=\"apply_overrides=0 levels=hml rows=100 min_qod=70 first=1 sort-reverse=severity notes=1 overrides=1\"/>" | xmllint --xpath '//get_reports_response/report' - > $FILE_PATH/report_$(date +%s).xml
	log_print "Scan completed. Report available in $FILE_PATH folder"
	exit 0
fi

if [[ -n $exclude_ip ]]; then
	log_print "Invalid command: missing argument -s or -v. Use -h for help."
	exit 1
fi

#Print if no agrument use
log_print "Invalid command: missing argument -s, -u or -v. Use -h for help."
exit 1
