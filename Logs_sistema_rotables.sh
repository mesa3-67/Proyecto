#!/bin/bash
set -euo pipefail
#######################################
# Logs de error del sistema rotables	#
# Logs de acceso del sistema rotables #
# Logs rotables usando logrotate			#
#######################################


#######################################	COLORES	#######################################
V="\e[1;32m"
AZUL="\e[1;34m"
FIN="\e[0m"


#######################################	LOGS ROTABLES	#######################################
echo -e "$AZUL ############################################################################## $FIN"
echo -e "$V Aplicando configuracion de logs del sistema rotables $FIN"; sleep 3

if sudo grep -q '/var/log/nginx/*.log {' /etc/logrotate.d/nginx; then
	echo -e "$V La configuracion ya existe $FIN"
else
	echo -e "$V La configuracion no existe, será aplicada ahora $FIN"
cat << EOF > /etc/logrotate.d/nginx
/var/log/nginx/access.log {
	daily
	rotate 14
	compress
	delaycompress
	missingok
	notifempty
	create 0640 www-data adm
	sharedscripts
	postrotate
		[ ! -f /run/nginx.pid ] || kill -USR1 $(cat /run/nginx.pid)
	endscript
}

/var/log/nginx/error.log {
	daily
	rotate 14
	compress
	delaycompress
	missingok
	notifempty
	create 0640 www-data adm
	sharedscripts
	postrotate
		[ ! -f /run/nginx.pid ] || kill -USR1 $(cat /run/nginx.pid)
	endscript
}
EOF
fi


echo -e "$AZUL ############################################################################## $FIN"
if sudo grep -q '/var/log/mariadb/*.log {' /etc/logrotate.d/nginx; then
	echo -e "$V La configuracion ya existe $FIN"
else
	echo -e "$V La configuracion no existe, será aplicada ahora $FIN"
	echo -e "$V Configurando logs rotables de postgresql $FIN"; sleep 3
cat << EOF > /etc/logrotate.d/mariadb
/var/log/mariadb/*.log {
	daily
	rotate 14
	compress
	delaycompress
	missingok
	notifempty
	create 0640 www-data adm
	sharedscripts
	postrotate
		[ ! -f /run/nginx.pid ] || kill -USR1 $(cat /run/nginx.pid)
	endscript
}
EOF
fi


echo -e "$AZUL ############################################################################## $FIN"
sleep 12
echo -e "$V Configuracion de logs rotables aplicada $FIN"

