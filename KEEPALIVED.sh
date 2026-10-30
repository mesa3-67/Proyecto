#!/bin/bash

#modo Seguro
set -euo pipefail

#colores
R='\e[1;31m'
G='\e[1;32m'
Y='\e[1;33m'
B='\e[1;34m'
N='\e[0m'

verificar_root(){
if [ "$EUID" -ne 0 ]; then
	echo -e "$R este script se debe ejecutar como root$N"; exit 1
fi
}

#Recolectando datos
preguntas_rp() {
echo -e "$B Configuracion basada en preguntas.$N"

while true; do
  read -rp "¿Cuál es el rol de este nodo? (1: MASTER, 2: BACKUP) [1/2]: " ROL_OPCION
  case "$ROL_OPCION" in
    1|master|MASTER)
        ROL="MASTER"
        ROUTER_ID="NODO1"
        STATE="MASTER"
        PRIORITY="150"
        break
        ;;
    2|backup|BACKUP)
        ROL="BACKUP"
        ROUTER_ID="NODO2"
        STATE="BACKUP"
        PRIORITY="100"
        break
        ;;
    *)
        echo -e "$R Opcion no valida. Introduce 1 para MASTER o 2 para BACKUP.$N"
        ;;
    esac
done
echo -e "$G Rol asignado exitosamente: $ROL ($ROUTER_ID)$N\n"

# Puerto Web
read -rp "Introduce el puerto web para pihole de ambos: " INPUT_PORT
PUERTO_WEB="${INPUT_PORT:-8080}"

# Contraseña
read -rsp "Introduce la contraseña para la API / Panel web de Pihole de ambos nodos: " INPUT_PASS
echo 
CLAVE_PIHOLE="${INPUT_PASS:-9099}"

echo -e "$G Parámetros guardados correctamente.$N"
}

#instalacion y conf de keepalived
configurar_keepalived(){
	echo -e "$B configurando keepalived (redundancia VRRP y VIP   192.168.13.100).... $N"
	apt install -y keepalived 
	
	WAN_IF=$(ip route show default | awk '{print $5; exit}')
	LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(en|enx|eth|enp)' | grep -vx "$WAN_IF" | head -n1)

#seccion q crea sripts auxiliares en /etc/keepalived
	mkdir -p /etc/keepalived
	
cat << EOF > /etc/keepalived/check_internet.sh
#!/bin/bash
WAN_IF="$WAN_IF"
ping -c 2 -i 0.2 -W 1 -I "\$WAN_IF" 8.8.8.8 >/dev/null 2>&1
EOF

cat << EOF > /etc/keepalived/check_services.sh
#!/bin/bash
systemctl is-active --quiet nginx      || exit 1
systemctl is-active --quiet mariadb    || exit 1
systemctl is-active --quiet pihole-FTL || exit 1
exit 0
EOF

cat << EOF > /etc/keepalived/notify.sh
#!/bin/bash
case "\$1" in
  MASTER)
    sysctl -w net.ipv4.ip_forward=1
    pihole-FTL --config dhcp.active true
    pihole restartdns
    ;;
  BACKUP|FAULT)
    pihole-FTL --config dhcp.active false
    pihole restartdns
    sysctl -w net.ipv4.ip_forward=0
    ;;
esac
EOF

	chmod 750 /etc/keepalived/*.sh
	chown root:root /etc/keepalived/*.sh

#archiv keepalive.conf
cat << EOF > /etc/keepalived/keepalived.conf
global_defs {
	router_id $ROUTER_ID
	enable_script_security
	script_user root
	vrrp_garp_master_delay 2
}

vrrp_script chk_internet {
	script "/etc/keepalived/check_internet.sh"
	interval 1
	timeout 3
	weight -60
	fall 1
	rise 2
}

vrrp_script chk_services{
	script "/etc/keepalived/check_services.sh"
	interval 2
	timeout 5
	weight -60
	fall 2
	rise 2
}

vrrp_instance VI_1{
	state $STATE
	interface $LAN_IF
	virtual_router_id 51
	priority $PRIORITY
	advert_int 1

	authentication {
	    auth_type PASS
	    auth_pass MESA-313
	}
	
	virtual_ipaddress{
	192.168.13.100/24
	}
	
	track_script{
	     chk_internet
	     chk_services
	}
	
	notify_master "/etc/keepalived/notify.sh MASTER"
	notify_backup "/etc/keepalived/notify.sh BACKUP"
	notify_fault  "/etc/keepalived/notify.sh FAULT"
}
EOF


  chmod 640 /etc/keepalived/keepalived.conf
  chown root:root /etc/keepalived/keepalived.conf
  
#Validar sintaxis e iniciar keepalived
	keepalived -t -f /etc/keepalived/keepalived.conf
	systemctl enable keepalived
	systemctl restart keepalived
     echo -e "$G keepalived configurado correctamente$N"
}


#vip como gateway
confi_gateway(){
echo -e "$B configurando credencialesy parametrso de pihole......$N"

	if command -v pihole > /dev/null 2>&1; then
	#Establecer la contraseña introducida interactivamente
	pihole setpassword "$CLAVE_PIHOLE" > /dev/null 2>&1 || true
	
	#configurar puerto web de forma idepotent
	pihole-FTL --config webserver.port "$PUERTO_WEB" 2>/dev/null || true
	
	# configurar parametros DHCP orientados a la vip
	pihole-FTL --config dhcp.router 192.168.13.100 2>/dev/null || true
	pihole-FTL --config misc.dnsmasq_lines '["dhcp-option=6,192.168.13.100"]' 2>/dev/null || true
	pihole-FTL --config dhcp.start 192.168.13.10 2>/dev/null || true
	pihole-FTL --config dhcp.end 192.168.13.20 2>/dev/null || true
	systemctl restart pihole-FTL 2>/dev/null || true
	echo -e "$G pihole configurado con puerto $PUERTO_WEB y nueva contraseña$N"
else
	echo -e "$Y pi-hole no esta instalado en este nodo. omisivo en esta fase$N"
fi
}

#ejecucion
verificar_root
preguntas_rp
configurar_keepalived
confi_gateway
