#!/bin/bash


V="\e[1;32m"
R="\e[1;31m"
A="\e[1;34m"
F="\e[0m"



if [ "$(whoami)" == "root" ]; then
  echo -e "$V Bienvenido $R $HOSTNAME👤 $V podemos comenzar $F"
  else
  echo -e "$R Debes ingresar como super $LUZ  usuario🫆$F"
  exit 1
  fi

	

echo "====================================================="
echo   Instalando netdata
echo "====================================================="

curl https://get.netdata.cloud/kickstart.sh > /tmp/netdata-kickstart.sh && sh /tmp/netdata-kickstart.sh > /dev/null 2>&1    
    

    sudo apt update > /dev/null 2>&1    
    sudo apt install msmtp msmtp-mta bsd-mailx -y > /dev/null 2>&1    
    

sleep 2

echo "#####################################################"
echo " CONFIGURANDO CORREO ELCTROCNICO "
echo "####################################################"

	read -p "Dirección de correo electronico: " correo
        read -p "contraseña de correo electronico: " API
        
	
sudo tee "/etc/msmtprc" << EOF > /dev/null 2>&1    
defaults
auth           on
tls            on
tls_starttls   on
tls_true_file  /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           smtp.gmail.com
port           587
from           $correo
user           $correo
password       $API
EOF

sudo chmod 600 /etc/msmtprc	
	
sudo tee /etc/netdata/health_alarm_notify.conf << EOF > /dev/null 2>&1   
EMAIL_SENDER="$correo"
SEND_EMAIL="YES"
DEFAULT_RECIPIENT_EMAIL="$correo"
EOF
    		
    			
echo -e "$R CONFIGURANDO CONEXION DE CLAVE $F"
sudo tee /etc/netdata/stream.conf << EOF > /dev/null 2>&1 
[66093669-c72d-4a5f-8bfc-35d14b3cfa5b]
enabled = yes
default memory mode = dbengine
EOF




      if iptables -V &> /dev/null; then
echo -e "$V PAQUETE DE IPTABLAS ACTIVCO $F"
      sudo iptables -A INPUT -p tcp --dport 19999 -j ACCEPT
      else
echo -e "$R Instalando iptablas $F"
      apt install ipatables-persistent -y 
      sudo iptables -A INPUT -p tcp --dport 19999 -j ACCEPT
      fi
      
      sudo netfilter-persistent save > /dev/null 2>&1
      sleep 2

     sudo systemctl restart netdata > /dev/null 2>&1  
     echo -e "NETDATA ESTA:"
     sudo systemctl is-active netdata

