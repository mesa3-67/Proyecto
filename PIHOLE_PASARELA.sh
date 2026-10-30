#!/bin/bash
set -euo pipefail

#variables colores
R="\e[1;31m"
G="\e[1;32m"
Y="\e[1;33m"
B="\e[1;34m"
N="\e[0m"

verificar_root(){
if [ "$EUID" -ne 0 ]; then
	echo -e "$R Tiene que ser super usuario $N"; exit 1
fi
}


configurar_parametros(){
echo -e "$B--- configuracion de pasarela ---$N"
read -rp "intoduce la IP fija para la pasarela [192.168.13.199]: " INPUT_IP
IP_FIJA="${INPUT_IP:-192.168.13.199}"
echo -e "$G IP fija asignada: $IP_FIJA$N\n"

echo -e "$B---configuracion de seguridad Pihole---$N"

while true; do
read -rsp "introduce la contraseña para el panel web de pihole: " PASS_PIHOLE
echo
read -rsp "Confirma la contraseña: " PASS_PIHOLE_CONFIRM
echo
if [ "$PASS_PIHOLE" = "$PASS_PIHOLE_CONFIRM" ]; then
  if [ -z "$PASS_PIHOLE" ]; then
  	echo -e "$Y ADVERTENCIA: la contraseña esta vacia se recomienda establecer una. $N"
  fi
  	echo -e "$G contraseña configurada correctamente. $N\n"
  	break
  	else
  	echo -e "$R las contraseñas no coinciden intentalo de nuevo $N\n"
fi
done
}

#seccion de actualizacion del sistema
actualizar_system(){
	echo -e "$B actualizando listas de paquetes del sistema $N"
export DEBIAN_FRONTEND=nointeractive
	apt-get update
	apt-get upgrade -y
	apt-get install -y curl iptables iptables-persistent netfilter-persistent
	echo -e "$G sistema actualizado $N"
}

#seccion q verifica la interfaces de red
interface_red(){
	WAN=$(ip route show default | awk '{print $5; exit}' || true)
	ETHERNET=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(en|eth)' | grep -vx "$WAN" | head -n1 || true)
	
    if [ -z "$ETHERNET" ] || [ -z "$WAN" ]; then
    	echo -e "$R no se detecto la interfaz LAN o la WAN. $N"; exit 1
    fi
    	echo -e "$G LAN: $ETHERNET | WAN: $WAN$N"
}

#seccion de spera a tener internet y dns
esperar_internet(){
	echo -e "$Y verificando salida a internet $N"
	for _ in $(seq 1 15); do
if curl -s --max-time 3 -o /dev/null https://install.pi-hole.net; then
	echo -e "$G internet y dns funcionan $N"
	return 0
fi
	sleep 2
done
	echo -e "$R sin internet o DNS, Revisa la WAN ($WAN) y /etc/resolv.conf. $N"
	exit 1
}

#seccion q crea el netplan IP FIJA
config_netplan(){
local NETPLAN="/etc/netplan/99-pasarela.yaml"
	echo -e "$B configurando netplan para $ETHERNET.$N"
	cat <<EOF> "$NETPLAN"
network:
  version: 2
  ethernets:
    $ETHERNET:
      dhcp4: false
      addresses: [$IP_FIJA/24]
EOF

	chmod 600 "$NETPLAN"
	netplan generate
	netplan apply
	echo -e "$G netplan aplicado correctamente. $N"
}

#seccion que activa el renvio de paqt
reenvio_paquetes(){
	echo -e "$B activando el reenvio de paquetes IPv4. $N"
	echo -e "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-pasarela.conf
	sysctl --system > /dev/null
	echo -e "$G reenvio de paquetes activo $N"
}

#seccion que libera e inmuta el puerto 53
port_53(){
	local RESOLV="/etc/resolv.conf"
	
	echo -e "$B liberando e inmutando el puerto 53$N"
	
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
systemctl mask systemd-resolved 2>/dev/null || true

	chattr -i "$RESOLV" 2>/dev/null || true
	rm -f "$RESOLV"

cat > "$RESOLV" <<EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
options trust-ad
EOF

	systemctl restart NetworkManager 2>/dev/null || true
	chattr +i "$RESOLV"
	echo -e "$G puerto 53 liberado y protegido. $N"
}

#seccion de instalacion de pihole v6
install_pihole(){
	echo -e "$Y verificando instalacion de pihole v6 $N"
if command -v pihole > /dev/null 2>&1; then
	echo -e "$G pihole ya esta instalao $N"
	return 0
fi

	echo -e "$B instalando Pi-hole v6 de forma desatendida $N"
	mkdir -p /etc/pihole
	chmod 755 /etc/pihole
	rm -f /etc/pihole/setupVars.conf # es de v5, nose usa en v6
	
cat <<EOF > /etc/pihole/pihole.toml
[dns]
interface = "$ETHERNET"
upstreams = [ "1.1.1.1", "1.0.0.1" ]

[dhcp]
active = true
start = "192.168.13.10" 
end = "192.168.13.100"
router = "$IP_FIJA"
netmask = "255.255.255.0"
leaseTime = "45m"
ipv6 = false

[webserver]
port = "8080o,8443os,[::]:8080o,[::]:8443os"
EOF
	chmod 644 /etc/pihole/pihole.toml
	
	esperar_internet
	curl -sSL https://install.pi-hole.net | PIHOLE_SKIP_OS_CHECK=true bash /dev/stdin --unattended
	
	if ! command -v pihole > /dev/null 2>&1; then
		echo -e "$R la instalacion de pihole fallo. revia /etc/pihole/install.log$N"
		exit 1
	fi
		echo -e "$G pihole v6 instalado correctamente$N"
		echo -e "$B configurando contraseña de pihole $N"
		pihole setpassword "$PASS_PIHOLE" > /dev/null 2>&1 || true
		
		echo -e "$G pihole instalado correctamente $N"
		
}

#seccion de aplicacion de reglas nat
reglas_nat(){
     echo -e "$B configurando reglas IPTABLES y NAT$N"

	iptables -t nat -F
	iptables -t nat -A POSTROUTING -o "$WAN" -j MASQUERADE
	# Redirige cualquier consulta DNS al puerto 53
	iptables -t nat -A PREROUTING -i "$ETHERNET" -p udp --dport 53 -j REDIRECT --to-ports 53
	iptables -t nat -A PREROUTING -i "$ETHERNET" -p tcp --dport 53 -j REDIRECT --to-ports 53
	# Bloqueo a consultas solo con VIP
  local DNS="${VIP:-192.168.13.100}"
  iptables -A FORWARD -i "$ETHERNET" -p udp --dport 53 ! -d "$DNS" -j DROP
  iptables -A FORWARD -i "$ETHERNET" -p tcp --dport 53 ! -d "$DNS" -j DROP
  # Bloqueo DNS sobre TLS, puerto 853
	iptables -A FORWARD -p tcp --dport 853 -j DROP
	iptables -A FORWARD -p udp --dport 853 -j DROP

	netfilter-persistent save > /dev/null
	echo -e "$G reglas NAT aplicadas y guardadas.$N"
}

#ejecucion principal
	verificar_root
	configurar_parametros
	actualizar_system
	interface_red
	config_netplan
	reenvio_paquetes
	port_53
	esperar_internet
	install_pihole
	reglas_nat
		echo -e "$G pasarela de red creada con exito $N"

