#!/bin/bash
# ---------------------------------------------------- #
# Automatizador de Redundancia y Sincronizacion de red #
# Instalador, configurador, sincronizador de Pihole    #
# Keepalived, Nebula-Sync. (Servidores linux)          #
# Ubuntu Server 24.04 LTS.			       #
# Version 2.0 - Mesa 3				       #
# ---------------------------------------------------- #

# Modo Seguro
set -euo pipefail

# Colores
R='\e[1;31m'
G='\e[1;32m'
B='\e[1;34m'
N='\e[0m'

# Validando privilegios
verificar_root() {
if [ "$EUID" -ne 0 ]; then
  echo -e "$R Este script debe ejecutarse como root.$N"
  exit 1
fi
}

# Preguntas para completar datos reales
preguntas_rp() {
echo -e "$B Configuracion basada en preguntas.$N"

# IPs de las máquinas
read -rp "Introduce la IP LAN del Nodo 1 (Master): " INPUT_IP1
IP_NODO1="${INPUT_IP1:-192.168.13.200}"

read -rp "Intruduce la IP LAN del Nodo 2 (Backup): " INPUT_IP2
IP_NODO2="${INPUT_IP2:-192.168.13.201}"

# Puerto Web
read -rp "Introduce el puerto web para pihole de ambos: " INPUT_PORT
PUERTO_WEB="${INPUT_PORT:-8080}"

# Contraseña
read -rsp "Introduce la contraseña para la API / Panel web de Pihole de ambos nodos: " INPUT_PASS
echo 
CLAVE_PIHOLE="${INPUT_PASS:-9099}"

echo -e "$G Parámetros guardados correctamente.$N"
}

# Configurando de Nebula-Sync
confi_nebula() {
echo -e "$B Configurando Nebula-Sync.$N"

  if ! command -v docker > /dev/null 2>&1 || ! docker compose version > /dev/null 2>&1; then
      apt-get update -y
      apt install -y docker.io docker-compose-v2 
      systemctl enable --now docker 
  fi
  
  mkdir -p /opt/nebula-sync
  cd /opt/nebula-sync
  touch .env
  chmod 600 .env
  
  cat << EOF > .env
PRIMARY=http://$IP_NODO1:$PUERTO_WEB|$CLAVE_PIHOLE
REPLICAS=http://$IP_NODO2:$PUERTO_WEB|$CLAVE_PIHOLE
FULL_SYNC=false
RUN_GRAVITY=false
CRON=*/10 * * * *
TZ=UTC
SYNC_CONFIG_DNS=true
SYNC_CONFIG_DNS_EXCLUDE=interface
SYNC_CONFIG_DHCP=true
SYNC_CONFIG_DHCP_EXCLUDE=active
SYNC_GRAVITY_GROUP=true
SYNC_GRAVITY_AD_LIST=true
SYNC_GRAVITY_AD_LIST_BY_GROUP=true
SYNC_GRAVITY_DOMAIN_LIST=true
SYNC_GRAVITY_DOMAIN_LIST_BY_GROUP=true
SYNC_GRAVITY_CLIENT=true
SYNC_GRAVITY_CLIENT_BY_GROUP=true
EOF

  
  cat << EOF > compose.yaml
services:
  nebula-sync:
    image: ghcr.io/lovelaze/nebula-sync:latest
    container_name: nebula-sync
    restart: unless-stopped
    env_file: .env
EOF

# Levantar contenedor 
  docker compose up -d --force-recreate 
  
  echo -e "$B Esperando la primera sincronizacion...$N"
  sleep 8
  docker logs --tail 15 nebula-sync
  
echo -e "$G Nebula-Sync implementado y sincronizandose cada: 10Minutos.$N"
}

# Ejecucion principal del script
verificar_root
preguntas_rp
confi_nebula
