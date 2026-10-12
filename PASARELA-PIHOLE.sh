#!/bin/bash
# ============================================ #
# Automatizador de Pasarela de RED con Pihole  #
# Instala y configura el sistema como pasarela #
# De Wifi a Ethernet, DHCP activo, Secuestro   #
# De DNS, IP 192.168.13.1 - Servidores Linux   #
# Version:  1.2                                #
# Autor:    Data Center - MESA 3               #
# ============================================ #

# Colores
R="\e[1;31m"
G="\e[1;32m"
Y="\e[1;33m"
B="\e[1;34m"
N="\e[0m"

# Modo Seguro
set -euo pipefail

# Verificando privilegios 
verificar_root() {
if [ "$EUID" -ne 0 ]; then
  echo -e "$R Ejecuta el script como root.$N"
  exit
fi
}

# Actualizando el sistema 
actualizar_system() {
echo -e "$B Actualizando el sistema.$N"
  export DEBIAN_FRONTEND=noninteractive
  apt update && apt upgrade -y 2>/dev/null
  apt install -y curl iptables iptables-persistent netfilter-persistent 
echo -e "$G Sistema actualizado.$N"
}

# Detectando interface de red 
interface_red() {
ETHERNET=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(en|eth)' | head -n1)
WIFI=$(ip -o link show | awk -F': ' '{print $2}' | grep '^wl' | head -n1)
IP_FIJA="192.168.13.1"

if [ -z "$ETHERNET" ] || [ -z "$WIFI" ]; then
  echo -e "$R No se detectó la interfaz Ethernet (LAN) o WiFi (WAN).$N"
  exit 1
fi
echo -e "$G LAN: $ETHERNET | WAN: $WIFI$N"
}
# Esperando tener internet y DNS
internet_conect() {
echo -e "$Y Verificando salida a internet.$N"
  for _in in $(seq 1 15); do
    if curl -s --max-time 3 -o /dev/null https://install.pi-hole.net; then
    echo -e "$G Internet y DNS resuelve.$N"
    return 0
    fi
    sleep 2
  done
  echo -e "$R Sin internet o DNS, Revisa tu conexion a internet.$N"
  exit 1
}

# Creando el Netplan (IP FIJA)
config_netplan() {
  local NETPLAN="/etc/netplan/99-pasarela.yaml"
  
echo -e "$B Configurando netplan.$N"
cat <<EOF > $NETPLAN
network:
  version: 2
  ethernets:
    $ETHERNET:
      addresses: [$IP_FIJA/24]
EOF

echo -e "$G Netplan creado correctamente.$N"
  chmod 600 $NETPLAN
  netplan generate && netplan apply 2>/dev/null
}

# Activamos el reenvio de paquetes
reenvio_paquetes() {
echo -e "$B Activando el reenvío de paquetes.$N"
  echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-pasarela.conf > /dev/null
  sysctl --system > /dev/null
echo -e "$G Reenvio de paquetes activo.$N"
}

# Liberar e inmutar el puerto 53
port_53() {
  local RESOLV="/etc/resolv.conf"
  
echo -e "$B Liberando e Inmutando el puerto 53.$N"
  chattr -i "$RESOLV" 2>/dev/null
  systemctl stop systemd-resolved 2>/dev/null || true 
  systemctl disable systemd-resolved 2>/dev/null || true
  systemctl mask systemd-resolved 2>/dev/null || true
  rm -f "$RESOLV"
 
 cat > "$RESOLV" <<EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF
  
  systemctl restart NetworkManager 2>/dev/null || true 
  chattr +i "$RESOLV"
  
echo -e "$G El puerto 53 liberado y esta protegido.$N"
}

# Instalando PIHOLE de manera desatendida
install_pihole() {
echo -e "$Y Verificando Pihole.$N"
if command -v pihole > /dev/null 2>&1; then
  echo -e "$G Ya esta instalado Pihole.$N"
  else
  echo -e "$B Instalando Pihole.$N"
  mkdir -p /etc/pihole
  chmod 755 /etc/pihole
  
  cat <<EOF > /etc/pihole/pihole.toml
[dns]
interface = "$ETHERNET"
upstreams = [ "1.1.1.1", "1.0.0.1" ]

[dhcp]
active = true
start = "192.168.13.1"
end = "192.168.13.10"
router = "$IP_FIJA"
netmask = "255.255.255.0"
leaseTime = "45m"
ipv6 = false

[webserver]
active = true
port = "8080o,8443os,[::]:8080o,[::]:8443os"
EOF

  chmod 644 /etc/pihole/pihole.toml

  internet_conect
  curl -sSL https://install.pi-hole.net | PIHOLE_SKIP_OS_CHECK=true bash -s -- --unattended
  echo -e "$G Pihole instalado correctamente.$N"
fi
}

# Aplicando reglas nat a la pasarela 
reglas_nat() {
echo -e "$B Configurando IPtables.$N"
  iptables -t nat -F
  iptables -t nat -A POSTROUTING -o "$WIFI" -j MASQUERADE
  
  iptables -t nat -A PREROUTING -i "$ETHERNET" -p udp --dport 53 -j REDIRECT --to-ports 53 
  iptables -t nat -A PREROUTING -i "$ETHERNET" -p tcp --dport 53 -j REDIRECT --to-ports 53
  
  #iptables -A FORWARD -i "$ETHERNET" -p udp --dport 53 ! -d $IP_FIJA -j DROP
  #iptables -A FORWARD -i "$ETHERNET" -p tcp --dport 53 ! -d $IP_FIJA -j DROP
  
  iptables -A FORWARD -p tcp --dport 853 -j DROP
  iptables -A FORWARD -p udp --dport 853 -j DROP
  
  netfilter-persistent save > /dev/null
echo -e "$G Reglas NAT aplicadas.$N"
}

# Ejecucion principal
  verificar_root
  actualizar_system
  interface_red
  config_netplan
  reenvio_paquetes
  port_53
  internet_conect
  install_pihole
  reglas_nat
  echo -e "$G Pasarela creada.$N"
