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
#	openldap.sh
#
#	Abstract: 
#		A QPKG start/stop script for
#		OpenLDAP v2.4.23
#
#	HISTORY:
#		2010/11/05 -	Created - AndyChuo (zeonism at gmail dot come) 
# 
#================================================================

#export LD_LIBRARY_PATH=/usr/lib

DAEMON="/usr/sbin/slapd"
RETVAL=0

QPKG_NAME="OpenLDAP"
QPKG_DIR=""
WEB_SHARE=`/sbin/getcfg SHARE_DEF defWeb -d Qweb -f /etc/config/def_share.info`

SLAPD_CONF="/etc/openldap/slapd.conf"
SLAPD_PIDFILE=""
SLAPD_USER="openldap"
SLAPD_GROUP="openldap"
SLAPD_OPTIONS=""
SLAPD_SERVICES=""

# Configure if the slurpd daemon should be started. Possible values:
# - yes:   Always start slurpd
# - no:    Never start slurpd
# - auto:  Start slurpd if a replica option is found in slapd.conf (default)
SLURPD_START=auto

_exit()
{
	/bin/echo -e "Error: $*"
	/bin/echo
	exit 1
}

# Determine BASE installation location according to smb.conf
find_base() {	
	BASE=""
	DEV_DIR="HDA HDB HDC HDD HDE HDF HDG HDH MD0 MD1 MD2 MD3"
	publicdir=`/sbin/getcfg Public path -f /etc/config/smb.conf`
	if [ ! -z $publicdir ] && [ -d $publicdir ];then
		BASE=`echo $publicdir |awk -F/Public '{ print $1 }'`
	else
		for datadirtest in $DEV_DIR; do
			[ -d /share/${datadirtest}_DATA/Public ] && BASE=/share/${datadirtest}_DATA
		done
	fi
	if [ -z $BASE ]; then
		echo "The base directory cannot be found."
		_exit 1
	else
		QPKG_DIR=${BASE}/.qpkg/${QPKG_NAME}
	fi
}

create_symlinks(){
	DIRS="bin etc lib sbin"
	for i in $DIRS
	do
		j="`/bin/ls ${QPKG_DIR}/$i`"
		for k in $j
		do
			l="/usr"
			[ $i = "etc" ] && l=""
			[ ! -e "$l/$i/$k" ] && /bin/ln -sf "${QPKG_DIR}/$i/$k" $l/$i/$k
		done
	done
	/bin/ln -sf ${QPKG_DIR}/lib/libsasl2.so.2.0.23 /usr/lib/libsasl2.so.2
	/bin/ln -sf ${QPKG_DIR}/lib/libsasl2.so.2.0.23 /usr/lib/libsasl2.so
	[ -d /var/state/saslauthd ] || /bin/ln -sf ${QPKG_DIR}/var/state/saslauthd /var/state
	[ -d /var/openldap-data ] || /bin/ln -sf ${QPKG_DIR}/var/openldap-data /var/
	[ -d /share/${WEB_SHARE}/phpldapadmin ] || /bin/ln -sf ${QPKG_DIR}/phpldapadmin /share/${WEB_SHARE}/phpldapadmin
}

# get the QPKG dir
find_base

# export LD_LIBRARY_PATH
export LD_LIBRARY_PATH=${QPKG_DIR}/lib:/usr/local/lib

# create req. symlinks
create_symlinks

# Stop processing if slapd is not there
[ -x /usr/sbin/slapd ] || exit 0

# Stop processing if the config file is not there
if [ ! -r "$SLAPD_CONF" ]; then
  cat <<EOF >&2
No configuration file was found for slapd at $SLAPD_CONF.
An example slapd.conf is in /etc/openldap/slapd.conf.default
EOF
  _exit
fi

# Find out the name of slapd's pid file
if [ -z "$SLAPD_PIDFILE" ]; then
        SLAPD_PIDFILE=`sed -ne 's/^pidfile[[:space:]]\+\(.\+\)/\1/p' \
                "$SLAPD_CONF"`
fi

# Make sure the pidfile directory exists with correct permissions
piddir=`dirname "$SLAPD_PIDFILE"`
if [ ! -d "$piddir" ]; then
        mkdir -p "$piddir"
        [ -z "$SLAPD_USER" ] || chown -R "$SLAPD_USER" "$piddir"
        [ -z "$SLAPD_GROUP" ] || chgrp -R "$SLAPD_GROUP" "$piddir"
fi

# Pass the user and group to run under to slapd
if [ "$SLAPD_USER" ]; then
        SLAPD_OPTIONS="-u $SLAPD_USER $SLAPD_OPTIONS"
fi

if [ "$SLAPD_GROUP" ]; then
        SLAPD_OPTIONS="-g $SLAPD_GROUP $SLAPD_OPTIONS"
fi

SLAPD_OPTIONS="-4 -f $SLAPD_CONF $SLAPD_OPTIONS"

# make sure the directory that stores the db has the correct permission
chown -R openldap.openldap "${QPKG_DIR}/var/openldap-"*

# Start the slapd daemon and capture the error message if any to
# $reason.
start_slapd() {
        echo -n " slapd"
        if [ -z "$SLAPD_SERVICES" ]; then
                reason="`${QPKG_DIR}/bin/start-stop-daemon --start --quiet --oknodo \
                        --pidfile "$SLAPD_PIDFILE" --background \
                        --exec /usr/sbin/slapd -- $SLAPD_OPTIONS 2>&1`"
        else
                reason="`${QPKG_DIR}/bin/start-stop-daemon --start --quiet --oknodo \
                        --pidfile "$SLAPD_PIDFILE" \
                        --exec /usr/sbin/slapd -- -h "$SLAPD_SERVICES" $SLAPD_OPTIONS 2>&1`"
        fi
}

# Tell the user that something went wrong and give some hints for
# resolving the problem.
report_failure() {
        if [ -n "$reason" ]; then
                echo " - failed: "
                echo "$reason"
        else
                echo " - failed."
                cat <<EOF
The operation failed but no output was produced. For hints on what went
wrong please refer to the system's logfiles (e.g. /var/log/syslog) or
try running the daemon in Debug mode like via "slapd -d 16383" (warning:
this will create copious output).
EOF

                if [ -n "$SLURPD_OPTIONS" -o \
                     -n "$SLAPD_OPTIONS" -o \
                     -n "$SLAPD_SERVICES" ]; then
                        cat << EOF

Below, you can find the command line options used by this script to
run slapd and slurpd. Do not forget to specify those options if you
want to look to debugging output:
EOF
                        if [ -z "$SLAPD_SERVICES" ]; then
                                if [ -n "$SLAPD_OPTIONS" ]; then
                                        echo "  slapd $SLAPD_OPTIONS"
                                fi
                        else
                                echo "  slapd -h '$SLAPD_SERVICES' $SLAPD_OPTIONS"
                        fi

                        if [ "$SLURPD" = "yes" -a -n "$SLURPD_OPTIONS" ]; then
                                echo "  slurpd $SLURPD_OPTIONS"
                        fi
                fi
        fi
}

# Stop the slapd daemon and capture the error message (if any) to
# $reason.
stop_slapd() {
        echo -n " slapd"
        reason="`${QPKG_DIR}/bin/start-stop-daemon --stop --quiet --oknodo --retry 10 \
                --pidfile "$SLAPD_PIDFILE" \
                --exec /usr/sbin/slapd 2>&1`"
}

# start saslauthd
start_saslauthd(){
	/usr/sbin/saslauthd -a getpwent -n 1 -m /var/state/saslauthd > /dev/null 2>&1
}

# stop saslauthd
stop_saslauthd(){
	if [ -n "`pidof saslauthd`" ]; then
		/usr/bin/killall saslauthd 2>/dev/null
	fi
}

# Start the OpenLDAP daemons
start() {
	echo "Starting Saslauthd"
	start_saslauthd
	echo -n "Starting OpenLDAP:"
	trap 'report_failure' 0
	start_slapd
	trap "-" 0
	echo .
}

# Stop the OpenLDAP daemons
stop() {
        echo "Stopping Saslauthd"
        stop_saslauthd
	echo -n "Stopping OpenLDAP:"
	trap 'report_failure' 0
	stop_slapd
	trap "-" 0
	echo .
}

case "$1" in
  start)
        start ;;
  stop)
        stop ;;
  restart|force-reload)
        stop
        start
        ;;
  *)
        echo "Usage: $0 {start|stop|restart|force-reload}"
        exit 1
        ;;
esac
    

