#!/bin/bash
#######################################################
#	|=====SCRIPT DE ASTERISK: v20=====|	      #
#	- ACTUALIZA PAQUETES			      #
#	- INSTALA ASTERIS			      #
#	- INSTALA PAQUETES DE AUDIO EN ES	      #
#	- CREAR USER CON SU CONTRA Y NUM	      #
#	- AGREGA LAS EXTENCIONES		      #
#	- REINICIA ASTERIS			      #
#######################################################
#VARIABLES DE COLORES
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[0;33m'
AZUL='\033[0;34m'
FIN='\033[0m'
set -euo pipefail

#verifica si sos super user:
if [[ $(whoami) != "root" ]]; then
	echo -e "$AZUL Tienes que estar como super usuario para asi ejecutar este script $FIN";	exit 0
else echo -e "$VERDE Bienvenido puedes continuar $FIN"
fi


#pregunta si quieres continuar ejecutando el script
read -p "quieres continuar con el script (s/n): " sn
sn=${sn,,}
if [[ "$sn" == "s" ]]; then
echo -e "$VERDE ejecutando el script....... $FIN"; sleep 2
clear


#actualiza los paquetes:
echo -e "$AMARILLO ========= AREA DE ACTUALIZACION ========= $FIN"
echo -e "$VERDE Se actualizaran los paquetes a continuacion: $FIN"
echo -e "$VERDE Espere: $FIN"; sleep 4
echo -e "$VERDE actulizando............. $FIN"
sudo apt update &>/dev/null
echo -e "$VERDE Ya casi $FIN"
echo -e "$VERDE Espere: $FIN"
sudo apt upgrade -y &>/dev/null
echo -e "$VERDE Se actualizaron los paquetes $FIN"
echo -e "$AMARILLO ========================================= $FIN"
echo -e "$AZUL =========================================== $FIN"
echo -e "$VERDE         Continuando con el script $FIN"
echo -e "$AZUL =========================================== $FIN"; sleep 4
echo " "


#instalacion de asterisk
    echo -e "$AMARILLO ========= AREA DE VERIFICACION DE ASTERISK ========= $FIN"
if which asterisk; then
    echo -e "$VERDE YA cuentas con la aplicacion asterisk $FIN"; sleep 4
else
    echo -e "$AMARILLO no tienes instalado asterisk $FIN"
    echo -e "$VERDE Espere instalando asteris::: $FIN"
sudo apt-get update &>/dev/null
    sleep 2
sudo apt install asterisk -y &>/dev/null
    echo -e "$VERDE Se instalo ASTERISK correctamente $FIN"
    echo -e "$AMARILLO ==================================================== $FIN"
fi
echo " "


#instalacion de paquetes de audios en español
echo -e "$AMARILLO ========= AREA DE VERIFICACION DE PAQUETES ========= $FIN"
if dpkg -s asterisk-core-sounds-es &>/dev/null && \
   dpkg -s asterisk-core-sounds-es-g722 &>/dev/null && \
   dpkg -s asterisk-core-sounds-es-gsm &>/dev/null && \
   dpkg -s asterisk-core-sounds-es-wav &>/dev/null; then
   
echo -e "$VERDE Ya cuentas con los paquetes de audios en español $FIN"; sleep 4
else
echo -e "$AMARILLO instalando los paquetes de audios en español $FIN"; sleep 4
sudo apt-get install -y \
	asterisk-core-sounds-es \
	asterisk-core-sounds-es-g722 \
	asterisk-core-sounds-es-gsm \
	asterisk-core-sounds-es-wav	
echo -e "$VERDE se instalaron correctamente $FIN"; sleep 4
clear
echo -e "$AMARILLO ==================================================== $FIN"
fi
echo " "


#reiniciando servicio de asterisk
echo -e "$AMARILLO ========= AREA DE REINICIO DE ASTERISK ========= $FIN"
echo -e "$VERDE reiniciando asterisk espera: $FIN"
echo -e "$VERDE           listo $FIN"
sudo service asterisk restart
echo -e "$AMARILLO ================================================ $FIN"
echo " "


#configuracion del directorio sip.conf
echo -e "$AMARILLO ========= AREA DE CONF DEL SIP ========= $FIN"
if sudo grep -q '^allowoverlap=no$' /etc/asterisk/sip.conf; then
	echo -e "$VERDE la configuracion ya existe, no se escribira de nuevo :) $FIN"
else
	echo -e "$VERDE configurando el archivo sip.conf espere: $FIN"
sudo sed -i '127i\
allowoverlap=no\
udpbindaddr=0.0.0.0\
tcpenable=no\
tcpbindaddr=0.0.0.0\
transport=udp\
srvlookup=yes\
language=es\
disallow=all\
allow=alaw\
allow=ulaw\
\
[authentication]\
[Telefonos](!)\
type=friend\
host=dynamic\
context=comunes\
' /etc/asterisk/sip.conf	
echo -e "$VERDE La configuracion fue agregada correctamente $FIN"
fi
sleep 4
echo -e "$AMARILLO ========================================= $FIN"; sleep 4
echo " "

#==================================================================================================================================================
#EMPIEZAN LAS OPCIONES DEL MENU:
while true
do
read -p "crear usuario manualmente (s/n): " manualito
manualito=${manualito,,}
if [[ "$manualito" == "s" ]]; then
clear
echo -e "$VERDE iniciando $FIN"

#apartado donde agrega usuarios
echo " "
echo -e "$AMARILLO =============configurando info de usuarios=================== $FIN"
echo " "
#user1
echo -e "$AZUL CREACION DEL PRIMER USURIO ::::::::::::::::::::::::::::::::::::: $FIN"
read -p "Escribe el nombre del primer user: " user1
read -p "Asignale un numero de 4 digitos para que sea su numero telefonico: " num1 
read -p "Asignale una contraseña al usuario: " contra1
echo -e "$AMARILLO ======================================================= $FIN "

#agregando los usuarios a sip.conf
echo "agregando usuaris al archivo sip.conf"

#se tiene q agregar en la linea 144
sudo sed -i '144r /dev/stdin' /etc/asterisk/sip.conf <<EOF
[$user1](Telefonos)
	username=$user1$num1
	callerid=$user1
	secret=$contra1

EOF

#reiniciando servicio de asterisk
echo -e "$AMARILLO reiniciando asterisk $FIN"
sudo service asterisk restart

#configuracion del directorio extensions.conf
echo "configurando el archivo extensions.conf espere...."
sudo sed -i '1r /dev/stdin' /etc/asterisk/extensions.conf <<EOF
[comunes]
exten => $num1,1,Dial(SIP/$user1)
EOF

#reiniciando dialplan de asterisk
echo -e "$VERDE reiniciando dialplan $FIN"
sudo asterisk -rx "dialplan reload"
sleep 2
EQUIPO=$(hostname -I | awk '{print $1}')
echo -e "$AZUL ===================================================== $FIN"
echo -e "$VERDE Direcion IP: $EQUIPO $FIN"
echo -e "$AZUL ===================================================== $FIN"
echo -e "$VERDE USUARIO AGREGADO: $FIN"
echo -e "$VERDE nombre: $user1 num de telefono: $num1 contraseña: $contra1 $FIN"
echo -e "$AZUL ===================================================== $FIN"
echo -e "$VERDE TODO LISTO $FIN"; sleep 4
exit

elif [[ "$manualito" == "n" ]]; then
echo -e "$AMARILLO no quiso crear los user manualmente $FIN"
break
else echo -e "$ROJO opcion no valida intenta de nuevo $FIN"
fi
done

elif [[ "$sn" == "n" ]]; then
echo -e "$ROJO no quiso ejecutar el script $FIN"
clear
exit

else echo -e "$AMARILLO opcion no valida intente escribiendo s o n: $FIN"
fi
