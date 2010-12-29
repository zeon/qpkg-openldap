#!/bin/sh
#================================================================
# Copyright (C) 2010 QNAP Systems, Inc.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#----------------------------------------------------------------
#
# qinstall.sh
#
#	Abstract: 
#		A QPKG installation script for
#		OpenLDAP v2.4.23
#
#	HISTORY:
#		2008/03/26 -	Created	- KenChen
#		2010/11/05 -	Modified - AndyChuo (zeonism at gmail dot come) 
# 
#================================================================

##### Utils Defines #####
##################################
# add/remove entries according to your needs
##################################
#
CMD_CHMOD="/bin/chmod"
CMD_CHOWN="/bin/chown"
CMD_CHROOT="/usr/sbin/chroot"
CMD_CP="/bin/cp"
CMD_CUT="/bin/cut"
CMD_ECHO="/bin/echo"
CMD_GETCFG="/sbin/getcfg"
CMD_GREP="/bin/grep"
CMD_IFCONFIG="/sbin/ifconfig"
CMD_LN="/bin/ln"
CMD_MKDIR="/bin/mkdir"
CMD_MV="/bin/mv"
CMD_READLINK="/usr/bin/readlink"
CMD_RM="/bin/rm"
CMD_SED="/bin/sed"
CMD_SETCFG="/sbin/setcfg"
CMD_SLEEP="/bin/sleep"
CMD_SYNC="/bin/sync"
CMD_TAR="/bin/tar"
CMD_TOUCH="/bin/touch"
CMD_WLOG="/sbin/write_log"
#
##### System Defines #####
##################################
# please do not alter the values below
##################################
#
UPDATE_PROCESS="/tmp/update_process"
UPDATE_PB=0
UPDATE_P1=1
UPDATE_P2=2
UPDATE_PE=3
SYS_HOSTNAME=`/bin/hostname`
SYS_IP=`$CMD_IFCONFIG eth0 | $CMD_GREP "inet addr" | $CMD_CUT -f 2 -d ':' | $CMD_CUT -f 1 -d ' '`
SYS_CONFIG_DIR="/etc/config" #put the configuration files here
SYS_INIT_DIR="/etc/init.d"
SYS_rcS_DIR="/etc/rcS.d/"
SYS_rcK_DIR="/etc/rcK.d/"
SYS_QPKG_CONFIG_FILE="/etc/config/qpkg.conf" #qpkg infomation file
SYS_QPKG_CONF_FIELD_QPKGFILE="QPKG_File"
SYS_QPKG_CONF_FIELD_NAME="Name"
SYS_QPKG_CONF_FIELD_VERSION="Version"
SYS_QPKG_CONF_FIELD_ENABLE="Enable"
SYS_QPKG_CONF_FIELD_DATE="Date"
SYS_QPKG_CONF_FIELD_SHELL="Shell"
SYS_QPKG_CONF_FIELD_INSTALL_PATH="Install_Path"
SYS_QPKG_CONF_FIELD_CONFIG_PATH="Config_Path"
SYS_QPKG_CONF_FIELD_WEBUI="WebUI"
SYS_QPKG_CONF_FIELD_WEBPORT="Web_Port"
SYS_QPKG_CONF_FIELD_SERVICEPORT="Service_Port"
SYS_QPKG_CONF_FIELD_SERVICE_PIDFILE="Pid_File"
SYS_QPKG_CONF_FIELD_AUTHOR="Author"
WEB_SHARE=`/sbin/getcfg SHARE_DEF defWeb -d Qweb -f /etc/config/def_share.info`
DOWNLOAD_SHARE=`/sbin/getcfg SHARE_DEF defDownload -d Qdownload -f /etc/config/def_share.info`
#
##### QPKG Info #####
##################################
# please enter the details below
##################################
#
. qpkg.cfg
#
#####	Func ######
##################################
# custum exit
##################################
#
_exit(){
	local ret=0
	
	case $1 in
		0)#normal exit
			ret=0
			if [ "x$QPKG_INSTALL_MSG" != "x" ]; then
				$CMD_WLOG "${QPKG_INSTALL_MSG}" 4
			else
				$CMD_WLOG "${QPKG_NAME} ${QPKG_VER} installation succeeded." 4
			fi
			$CMD_ECHO "$UPDATE_PE" > ${UPDATE_PROCESS}
		;;
		*)
			ret=1
			if [ "x$QPKG_INSTALL_MSG" != "x" ];then
				$CMD_WLOG "${QPKG_INSTALL_MSG}" 1
			else
				$CMD_WLOG "${QPKG_NAME} ${QPKG_VER} installation failed" 1
			fi
			$CMD_ECHO -1 > ${UPDATE_PROCESS}
		;;
	esac	
	exit $ret
}
#
##################################
# Determine BASE installation location and assigned to $QPKG_DIR
##################################
#
find_base(){
	# Determine BASE installation location according to smb.conf	
	publicdir=`/sbin/getcfg Public path -f /etc/config/smb.conf`
	if [ ! -z $publicdir ] && [ -d $publicdir ];then
		publicdirp1=`/bin/echo $publicdir | /bin/cut -d "/" -f 2`
		publicdirp2=`/bin/echo $publicdir | /bin/cut -d "/" -f 3`
		publicdirp3=`/bin/echo $publicdir | /bin/cut -d "/" -f 4`
		if [ ! -z $publicdirp1 ] && [ ! -z $publicdirp2 ] && [ ! -z $publicdirp3 ]; then
			[ -d "/${publicdirp1}/${publicdirp2}/Public" ] && QPKG_BASE="/${publicdirp1}/${publicdirp2}"
		fi
	fi
	
	# Determine BASE installation location by checking where the Public folder is.
	if [ -z $QPKG_BASE ]; then
		for datadirtest in /share/HDA_DATA /share/HDB_DATA /share/HDC_DATA /share/HDD_DATA /share/HDE_DATA /share/HDF_DATA /share/HDG_DATA /share/HDH_DATA /share/MD0_DATA /share/MD1_DATA /share/MD2_DATA /share/MD3_DATA; do
			[ -d $datadirtest/Public ] && QPKG_BASE="/${publicdirp1}/${publicdirp2}"
		done
	fi
	if [ -z $QPKG_BASE ] ; then
		echo "The Public share not found."
		_exit 1
	fi
	QPKG_INSTALL_PATH="${QPKG_BASE}/.qpkg"
	QPKG_DIR="${QPKG_INSTALL_PATH}/${QPKG_NAME}"
}
#
##################################
# Link service start/stop script
##################################
#
link_start_stop_script(){
	if [ "x${QPKG_SERVICE_PROGRAM}" != "x" ]; then
		$CMD_ECHO "Link service start/stop script: ${QPKG_SERVICE_PROGRAM}"
		$CMD_LN -sf "${QPKG_DIR}/${QPKG_SERVICE_PROGRAM}" "${SYS_INIT_DIR}/${QPKG_SERVICE_PROGRAM}"
		$CMD_LN -sf "${SYS_INIT_DIR}/${QPKG_SERVICE_PROGRAM}" "${SYS_rcS_DIR}/QS${QPKG_RC_NUM}${QPKG_NAME}"
		$CMD_LN -sf "${SYS_INIT_DIR}/${QPKG_SERVICE_PROGRAM}" "${SYS_rcK_DIR}/QK${QPKG_RC_NUM}${QPKG_NAME}"
		$CMD_CHMOD 755 "${QPKG_DIR}/${QPKG_SERVICE_PROGRAM}"
	fi

	# Only applied on TS-109/209/409 for chrooted env
	if [ -d ${QPKG_ROOTFS} ]; then
		if [ "x${QPKG_SERVICE_PROGRAM_CHROOT}" != "x" ]; then
			$CMD_MV ${QPKG_DIR}/${QPKG_SERVICE_PROGRAM_CHROOT} ${QPKG_ROOTFS}/etc/init.d
			$CMD_CHMOD 755 ${QPKG_ROOTFS}/etc/init.d/${QPKG_SERVICE_PROGRAM_CHROOT}
		fi
	fi
}
#
##################################
# Set QPKG information
##################################
#
register_qpkg(){
	$CMD_ECHO "Set QPKG information to $SYS_QPKG_CONFIG_FILE"
	[ -f ${SYS_QPKG_CONFIG_FILE} ] || $CMD_TOUCH ${SYS_QPKG_CONFIG_FILE}
	$CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_NAME} "${QPKG_NAME}" -f ${SYS_QPKG_CONFIG_FILE}
	$CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_VERSION} "${QPKG_VER}" -f ${SYS_QPKG_CONFIG_FILE}
		
	#default value to activate(or not) your QPKG if it was a service/daemon
	$CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_ENABLE} "UNKNOWN" -f ${SYS_QPKG_CONFIG_FILE}

	#set the qpkg file name
	[ "x${SYS_QPKG_CONF_FIELD_QPKGFILE}" = "x" ] && $CMD_ECHO "Warning: ${SYS_QPKG_CONF_FIELD_QPKGFILE} is not specified!!"
	[ "x${SYS_QPKG_CONF_FIELD_QPKGFILE}" = "x" ] || $CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_QPKGFILE} "${QPKG_QPKG_FILE}" -f ${SYS_QPKG_CONFIG_FILE}
	
	#set the date of installation
	$CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_DATE} `date +%F` -f ${SYS_QPKG_CONFIG_FILE}
	
	#set the path of start/stop shell script
	[ "x${QPKG_SERVICE_PROGRAM}" = "x" ] || $CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_SHELL} "${QPKG_DIR}/${QPKG_SERVICE_PROGRAM}" -f ${SYS_QPKG_CONFIG_FILE}
	
	#set path where the QPKG installed, should be a directory
	$CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_INSTALL_PATH} "${QPKG_DIR}" -f ${SYS_QPKG_CONFIG_FILE}

	#set path where the QPKG configure directory/file is
	[ "x${QPKG_CONFIG_PATH}" = "x" ] || $CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_CONFIG_PATH} "${QPKG_CONFIG_PATH}" -f ${SYS_QPKG_CONFIG_FILE}
	
	#set the port number if your QPKG was a service/daemon and needed a port to run.
	[ "x${QPKG_SERVICE_PORT}" = "x" ] || $CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_SERVICEPORT} "${QPKG_SERVICE_PORT}" -f ${SYS_QPKG_CONFIG_FILE}

	#set the port number if your QPKG was a service/daemon and needed a port to run.
	[ "x${QPKG_WEB_PORT}" = "x" ] || $CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_WEBPORT} "${QPKG_WEB_PORT}" -f ${SYS_QPKG_CONFIG_FILE}

	#set the URL of your QPKG Web UI if existed.
	[ "x${QPKG_WEBUI}" = "x" ] || $CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_WEBUI} "${QPKG_WEBUI}" -f ${SYS_QPKG_CONFIG_FILE}

	#set the pid file path if your QPKG was a service/daemon and automatically created a pidfile while running.
	[ "x${QPKG_SERVICE_PIDFILE}" = "x" ] || $CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_SERVICE_PIDFILE} "${QPKG_SERVICE_PIDFILE}" -f ${SYS_QPKG_CONFIG_FILE}

	#Sign up
	[ "x${QPKG_AUTHOR}" = "x" ] && $CMD_ECHO "Warning: ${SYS_QPKG_CONF_FIELD_AUTHOR} is not specified!!"
	[ "x${QPKG_AUTHOR}" = "x" ] || $CMD_SETCFG ${QPKG_NAME} ${SYS_QPKG_CONF_FIELD_AUTHOR} "${QPKG_AUTHOR}" -f ${SYS_QPKG_CONFIG_FILE}		
}
#
##################################
# Check existing installation
##################################
#
check_existing_install(){
	CURRENT_QPKG_VER="`/sbin/getcfg ${QPKG_NAME} Version -f /etc/config/qpkg.conf`"
	QPKG_INSTALL_MSG="${QPKG_NAME} ${CURRENT_QPKG_VER} is already installed. Setup will now perform package upgrading."
	$CMD_ECHO "$QPKG_INSTALL_MSG"			
}
#
##################################
# Custom functions
##################################
# create user and group for running hello_qnap (Optional)
create_req_user_group(){
	/bin/grep openldap /etc/group
	[ $? = 0 ] || delgroup openldap
	/bin/grep openldap /etc/passwd
	[ $? = 0 ] || deluser openldap
	/bin/adduser -DH openldap 2>/dev/null
}
#
###############################
# Pre-install routine
##################################
#
pre_install(){
	# stop the service before we start the installation #(Do not remove, required routine)
	[ -f /etc/init.d/${QPKG_SERVICE_PROGRAM} ] && /etc/init.d/${QPKG_SERVICE_PROGRAM} stop
	$CMD_SLEEP 5
	$CMD_SYNC

	# look for the base dir to install and assign the value to $QNAP_DIR
	find_base #(Do not remove, required routine)
	
	# add your own routines below
}
#
##################################
# Post-install routine
##################################
#
post_install(){
	create_req_user_group

	# create rcS/rcK start/stop scripts 
	link_start_stop_script	#(Do not remove, required routine)
	register_qpkg						#(Do not remove, required routine)
}
#
##################################
# Pre-update routine
##################################
#
pre_update()
{
	# add your own routines below
	echo ""
}
#
##################################
# Update routines
##################################
#
update_routines()
{
	# add your own routines below
	echo ""
}
#
##################################
# Post-update routine
##################################
#
post_update()
{
	# add your own routines below
	echo ""
}
#
##################################
# Pre-remove routine
##################################
#pre_remove()
#{
		# add your own routines below
#}
#
##################################
# Post-remove routine
##################################
#post_remove()
#{
		# add your own routines below
#}

#
##################################
# Install routines
##################################
install_routines()
{
	# add your own routines below
	echo ""
}
#
##################################
# Main installation
##################################
#
install()
{
	# pre install routines (do not remove, required routine)
	pre_install
	
	if [ -f "${QPKG_SOURCE_DIR}/${QPKG_SOURCE_FILE}" ]; then
		
		# check for existing install
		if [ -d ${QPKG_DIR} ]; then
			check_existing_install
			$CMD_CHMOD 777 "${QPKG_DIR}"
			UPDATE_FLAG=1
			
			# pre update routines (do not remove, required routine)
			pre_update
		else
			# create main QNAP installation folder
			$CMD_MKDIR -p ${QPKG_DIR}
			$CMD_CHMOD 777 "${QPKG_DIR}"
		fi
		
		# install/update QPKG files 		
		if [ ${UPDATE_FLAG} -eq 1 ]; then
			# update routines (do not remove, required routine)
			update_routines 
			
			# post update routines (do not remove, required routine)
			post_update
		else
			# decompress the QNAP file (do not remove, required routine)
			$CMD_TAR xzf "${QPKG_SOURCE_DIR}/${QPKG_SOURCE_FILE}" -C ${QPKG_DIR}
			if [ $? = 0 ]; then
				# installation routines
				install_routines
			else
				return 2
			fi
		fi
		
		# install progress indicator (do not remove, required routine)
		$CMD_ECHO "$UPDATE_P2" > ${UPDATE_PROCESS}
		
		# post install routines (do not remove, required routine)
		post_install
		
		$CMD_SYNC
		return 0
	else
		return 1		
	fi
}

#
##################################
# Main
##################################
#
# install progress indicator
$CMD_ECHO "$UPDATE_PB" > ${UPDATE_PROCESS}

install
if [ $? = 0 ]; then
	QPKG_INSTALL_MSG="${QPKG_NAME} ${QPKG_VER} has been installed in $QPKG_DIR."
	$CMD_ECHO "$QPKG_INSTALL_MSG"
	_exit 0
elif [ $? = 1 ]; then
	QPKG_INSTALL_MSG="${QPKG_NAME} ${QPKG_VER} installation failed. ${QPKG_SOURCE_DIR}/${QPKG_SOURCE_FILE} file not found."
	$CMD_ECHO "$QPKG_INSTALL_MSG"
	_exit 1
elif [ $? = 2 ]; then
	${CMD_RM} -rf ${QPKG_INSTALL_PATH}
	QPKG_INSTALL_MSG="${QPKG_NAME} ${QPKG_VER} installation failed. ${QPKG_SOURCE_DIR}/${QPKG_SOURCE_FILE} file error."
	$CMD_ECHO "$QPKG_INSTALL_MSG"
	_exit 1
else
	# never reach here
	echo ""
fi

