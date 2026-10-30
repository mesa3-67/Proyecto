#!/bin/bash
set -euo pipefail

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

          sudo apt update > /dev/null 2>&1    
     
    if command -V curl &> /dev/null; then
echo -e "$V Paquete para instalación acitvo $F"
  else
      sudo apt install curl -y > /dev/null
    fi 
	

echo -e "$V=====================================================$F"
echo -e "  ¡Instalando $V NETDATA $F $R Esto tardara unos segundos! $F"
echo -e "$V=====================================================$F"

curl https://get.netdata.cloud/kickstart.sh > /tmp/netdata-kickstart.sh && sh /tmp/netdata-kickstart.sh > /dev/null 2>&1    
    

sleep 2

echo -e "$v ========================================================$F"
echo -e "$V CONFIGURANDO CORREO ELCTROCNICO $F"
echo -e "$V ========================================================$F"
sleep 1
	read -p "Dirección de correo electronico: " correo
        read -p "contraseña de correo electronico: " API
        
	
	if msmtp --v &> /dev/null; then
echo   -e "$V PAQUETE DE MSMTP $R ACTIVO $F"
        else
echo   -e "$V INSTALANDO PAQUETE $R MSMTP $F"
      sudo apt install msmtp msmtp-mta ca-certificates -y
	fi
	
echo   -e "$V PREPARANDO ALARMAS DE NOTIFICACIONES $F"
       sudo tee /etc/netdata/health_alarm_notify.conf << EOF > /dev/null 2>&1   
date_format=''

sendmail=""

curl=""

nc=""

logger=""

aws=""

sendsms=""

EMAIL_SENDER=""

SEND_EMAIL="YES"

DEFAULT_RECIPIENT_EMAIL="$correo"

SEND_DYNATRACE="YES"

DYNATRACE_SERVER=""

DYNATRACE_TOKEN=""

DYNATRACE_SPACE=""

DYNATRACE_TAG_VALUE=""

DYNATRACE_ANNOTATION_TYPE="Netdata Alarm"

DYNATRACE_EVENT="CUSTOM_INFO"

DEFAULT_RECIPIENT_DYNATRACE=""

SEND_GOTIFY="YES"


GOTIFY_APP_TOKEN=""
GOTIFY_APP_URL=""

DEFAULT_RECIPIENT_GOTIFY=""

SEND_OPSGENIE="YES"

OPSGENIE_API_KEY=""
OPSGENIE_API_URL=""

DEFAULT_RECIPIENT_OPSGENIE=""

SEND_PUSHOVER="YES"

PUSHOVER_APP_TOKEN=""

DEFAULT_RECIPIENT_PUSHOVER=""

SEND_PUSHBULLET="YES"

PUSHBULLET_ACCESS_TOKEN=""
DEFAULT_RECIPIENT_PUSHBULLET=""

PUSHBULLET_SOURCE_DEVICE=""

SEND_TWILIO="YES"

TWILIO_ACCOUNT_SID=""
TWILIO_ACCOUNT_TOKEN=""
TWILIO_NUMBER=""
DEFAULT_RECIPIENT_TWILIO=""

SEND_MESSAGEBIRD="YES"

MESSAGEBIRD_ACCESS_KEY=""
MESSAGEBIRD_NUMBER=""
DEFAULT_RECIPIENT_MESSAGEBIRD=""

SEND_KAVENEGAR="YES"

KAVENEGAR_API_KEY=""
KAVENEGAR_SENDER=""
DEFAULT_RECIPIENT_KAVENEGAR=""

SEND_TELEGRAM="YES"

TELEGRAM_API_URL=""

TELEGRAM_BOT_TOKEN=""

TELEGRAM_RETRIES_ON_LIMIT="0"

DEFAULT_RECIPIENT_TELEGRAM=""

SEND_SLACK="YES"

SLACK_WEBHOOK_URL=""

DEFAULT_RECIPIENT_SLACK=""

SEND_MSTEAMS="YES"

MSTEAMS_WEBHOOK_URL=""

DEFAULT_RECIPIENT_MSTEAMS=""

MSTEAMS_ICON_DEFAULT="♡"
MSTEAMS_ICON_CLEAR="💚"
MSTEAMS_ICON_WARNING="⚠️"
MSTEAMS_ICON_CRITICAL="🔥"

MSTEAMS_COLOR_DEFAULT="0076D7"
MSTEAMS_COLOR_CLEAR="65A677"
MSTEAMS_COLOR_WARNING="FFA500"
MSTEAMS_COLOR_CRITICAL="D93F3C"

SEND_ROCKETCHAT="YES"

ROCKETCHAT_WEBHOOK_URL=""

DEFAULT_RECIPIENT_ROCKETCHAT=""

SEND_ALERTA="YES"

ALERTA_WEBHOOK_URL=""

ALERTA_API_KEY=""

DEFAULT_RECIPIENT_ALERTA=""

SEND_FLOCK="YES"

FLOCK_WEBHOOK_URL=""

DEFAULT_RECIPIENT_FLOCK=""

SEND_DISCORD="YES"

DISCORD_WEBHOOK_URL=""

DEFAULT_RECIPIENT_DISCORD=""

SEND_HIPCHAT="YES"

HIPCHAT_SERVER="api.hipchat.com"

HIPCHAT_AUTH_TOKEN=""

DEFAULT_RECIPIENT_HIPCHAT=""

SEND_KAFKA="YES"

KAFKA_URL=""

KAFKA_SENDER_IP=""

SEND_PD="YES"

DEFAULT_RECIPIENT_PD=""

USE_PD_VERSION="1"

SEND_FLEEP="YES"

DEFAULT_RECIPIENT_FLEEP=""

FLEEP_SENDER=""

SEND_IRC="YES"

DEFAULT_RECIPIENT_IRC=""

IRC_NETWORK=""

IRC_PORT=6667

IRC_NICKNAME=""

IRC_REALNAME=""

SEND_SYSLOG="NO"

SYSLOG_FACILITY=''

DEFAULT_RECIPIENT_SYSLOG="netdata"

SEND_PROWL="YES"

DEFAULT_RECIPIENT_PROWL=""

SEND_AWSSNS="YES"

AWSSNS_MESSAGE_FORMAT="${status} on ${host} at ${date}: ${chart} ${value_string}"

DEFAULT_RECIPIENT_AWSSNS=""

SEND_SMS="YES"

DEFAULT_RECIPIENT_SMS=""

SEND_MATRIX="YES"

MATRIX_HOMESERVER=

MATRIX_ACCESSTOKEN=

DEFAULT_RECIPIENT_MATRIX=""

SEND_SMSEAGLE="YES"

DEFAULT_RECIPIENT_SMSEAGLE="999888777"

SMSEAGLE_API_URL=""

SMSEAGLE_API_ACCESSTOKEN=""

SMSEAGLE_MSG_TYPE="sms"

SMSEAGLE_CALL_DURATION="10"

SMSEAGLE_VOICE_ID="1"

SEND_NTFY="YES"

NTFY_USERNAME=""

NTFY_PASSWORD=""

NTFY_ACCESS_TOKEN=""

DEFAULT_RECIPIENT_NTFY=""

SEND_ILERT="YES"

ILERT_ALERT_SOURCE_URL=""

DEFAULT_RECIPIENT_ILERT=""

SEND_SIGNL4="YES"

DEFAULT_RECIPIENT_SIGNL4=""

SEND_CUSTOM="YES"

DEFAULT_RECIPIENT_CUSTOM=""

custom_sender() {

    local msg="${host} ${status_message}: ${alarm} ${raised_for}"

    urlencode "${msg:0:160}" >/dev/null; msg="${REPLY}"

    to="${1}"

    info "not sending custom notification to ${to}, for ${status} of '${host}.${chart}.${name}' - custom_sender() is not configured."
}
EOF
    		    			
echo -e "$R CONFIGURANDO CONEXION DE CLAVE $F"
sudo tee /etc/netdata/stream.conf << EOF > /dev/null 2>&1 
[66093669-c72d-4a5f-8bfc-35d14b3cfa56]
enabled = yes
default memory mode = dbengine
EOF

    sudo tee /etc/msmtprc > /dev/null 2>&1 << EOF
defaults
auth             on
tls              on
tls_trust_file   /etc/ssl/certs/ca-certificates.crt
logfile          /var/log/msmtp.log

account          default
host             smtp.gmail.com
port             587
from             $correo
user             $correo
password         $API
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
     
     
     
     
     
     
     
