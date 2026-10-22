#!/bin/bash
set -euo pipefail

################################ COLORES ################################
V="\e[1;32m"
R="\e[1;31m"
A="\e[1;33m"
AZUL="\e[1;34m"
FIN="\e[0m"
PARPADEO="\e[5;7m"


################################	VERIFICACIÓN DE SUPERUSUARIO	################################
if [ "$(whoami)" == "root" ]; then
	echo -e "$V PUEDES CONTINUAR $FIN"; sleep 3
	echo " ";
	clear
else
	echo -e "$R NECESITAS SUPER USUARIO $FIN"; sleep 3
	clear; exit 1
fi

################################  VERIFICANDO DEPENDENCIAS PARA AGENTES ################################
echo -e "$AZUL ########################################################################################### $FIN"
echo -e "$V Verificando las dependencias necesarias $FIN"

curl https://get.netdata.cloud/kickstart.sh > /tmp/netdata-kickstart.sh && sh /tmp/netdata-kickstart.sh > /dev/null 2>&1 

################################ CONFIGURANDO CONEXION MONITOREO Y SERVIDOR ################################
echo -e "$AZUL ########################################################################################### $FIN"
echo -e "$V Configurando conexion de servidor $FIN"

     mkdir -p /etc/netdata


read -p "Numero de la ip de UBUNTU:" ip_ubuntu
tee "/etc/netdata/stream.conf" << EOF > /dev/null 2>&1 
[stream]
enabled = yes
destination = $ip_ubuntu:19999
api key = 66093669-c72d-4a5f-8bfc-35d14b3cfa5b
EOF

 if [ -f /etc/netdata/netdata.conf ]; then
    sed -i 's/memory mode = .*/memory mode = none/g' /etc/netdata/netdata.conf 2>/dev/null || true
    else
    tee "/etc/netdata/netdata.conf" <<EOF > /dev/null 2>&1 
[global]
    memory mode = none
EOF
  fi
     
echo "REINCIO DEL SISTEMA"
     systemctl daemon-reload
     systemctl restart netdata
     systemctl enable netdata     
    
         
         
         
         
         
