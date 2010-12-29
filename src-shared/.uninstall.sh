#!/bin/sh

WEB_SHARE=`/sbin/getcfg SHARE_DEF defWeb -d Qweb -f /etc/config/def_share.info`
QPKG_DIR=""
QPKG_NAME="OpenLDAP"

/bin/deluser openldap
/bin/delgroup openldap

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

remove_symlinks(){
	DIRS="bin etc lib sbin"
	for i in $DIRS
	do
		j="`/bin/ls ${QPKG_DIR}/$i`"
		for k in $j
		do
			l="/usr"
			[ $i = "etc" ] && l=""
			/bin/rm -rf $l/$i/$k
		done
	done
}
find_base
remove_symlinks

/bin/ln -sf /usr/lib/libsasl2.so.2.0.22 /usr/lib/libsasl2.so.2
/bin/ln -sf /usr/lib/libsasl2.so.2.0.22 /usr/lib/libsasl2.so

/bin/rm -rf /var/state/saslauthd /share/${WEB_SHARE}/phpldapadmin /etc/init.d/openldap.sh

TEMPDIR=`mktemp -d /share/Public/openldap-data-backup.XXXXXX`
/bin/mkdir -p $TEMPDIR/{openldap-data,openldap-slurp}
/bin/cp -af /var/openldap-data/* $TEMPDIR/openldap-data/

/bin/rm -rf /var/openldap-data

/sbin/write_log "[OpenLDAP] Your OpenLDAP database has been backed up to $TEMPDIR." 4

