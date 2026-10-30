#!/bin/bash
# ============================================= #
# Automatizador de Fail2ban en Servidores Linux #
# Instalador y configurador que acumula los     #
# Inicio de sesión fallidos y bloqueos de IP    #
# Verison:  1.0                                 #
# Autor:    Data Center - MESA 3                #
# ============================================= #

# --- Colores ----
R='\e[1;31m'
G='\e[1;32m'
B='\e[1;34m'
N='\e[0m'

# --- Modo seguro ----
set -euo pipefail

# Verifica si es ROOT ---
verifica_root() {
if [ "$EUID" -ne 0 ]; then
  echo -e "$R Ejecute este script como root o con sudo.$N"
  exit 1
fi
}

# --- Instalamos servicios ---
install_servicios() {
echo -e "$B Actualizando e Instalando servicios.$N"
  if command -v nginx >/dev/null 2>&1 && command -v mariadb >/dev/null 2>&1; then
    echo -e "$G Nginx como MariaDB está instalado.$N"
    else
    echo -e "$R Faltan Nginx o MariaDB. Instálelos primero.$N"
    exit 1
  fi
  
  if [ ! -f /var/log/nginx/error.log ] || [ ! -f /var/log/nginx/access.log ]; then
    echo -e "$R No existen los logs de Nginx. Inicie Nginx (systemctl start nginx) y repita el .sh.$N"
    exit 1
  fi
  
  if ! command -v fial2ban-client >/dev/null 2>&1; then
    apt update -y
    apt install -y fail2ban python3-systemd 
    echo -e "$G Paquetes instalados correctamente.$N"
    else
    echo -e "$G Fail2ban ya se encuentra instalado.$N"
  fi
echo -e "$G Proceso completado.$N"
}

# --- Configurando archivos ---
confi_mariadb() {
CONF_FILE="/etc/mysql/mariadb.conf.d/99-fail2ban.cnf"
LOG_MARIADB="/var/log/mysql/error.log"

echo -e "$B Archivo a crear: [$CONF_FILE].$N"

  if [ -f "$CONF_FILE" ] && grep -q "^log_error = $LOG_MARIADB" "$CONF_FILE"; then
    echo -e "$G MariaDB ya estaba configurado.$N"
    else
      cat << EOF > "$CONF_FILE"
[mysqld]
log_error = $LOG_MARIADB
EOF
  
  install -d -o mysql -g adm -m 750 /var/log/mysql
  systemctl restart mariadb
  echo -e "$G Log de errores activados en $LOG_MARIADB.$N"
fi

echo -e "$B Verificando cambios.$N"
grep -E "^log_error" "$CONF_FILE"
  if [ ! -f "$LOG_MARIADB" ]; then
    echo -e "$R MariaDB no creó $LOG_MARIADB. Revise: journal -u mariadb -n 20.$N"
    exit 1
  fi
echo -e "$G Configuracion aplicada correctamente.$N"          
}
  
# --- Configurando archivo ---
confi_fail2ban() {
JAIL_LOCAL="/etc/fail2ban/jail.local"
echo -e "$B Configurando archivo de Fail2ban.$N"
  if [ ! -f "$JAIL_LOCAL" ]; then
    cp /etc/fail2ban/jail.conf "$JAIL_LOCAL"
    echo -e "$G Archivo jail.local inicializado desde jail.conf.$N"
    else 
    echo -e "$B El archivo jail.local ya esxite.$N"
  fi

cat << EOF > "/etc/fail2ban/fail2ban.local"
[Definition]
allowipv6 = auto
EOF

cat << EOF > "$JAIL_LOCAL"
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 192.168.13.0/24
bantime = 1h
findtime = 10m
maxretry = 3
bantime.increment = true
bantime.factor    = 2

action  = %(action_)s

# ----------- SSH ---------------
[sshd]
enabled = true
backend = systemd 
port    = ssh

# ----------- NGINX -------------
[nginx-http-auth]
enabled  = true
backend  = auto
port     = http,https
logpath  = /var/log/nginx/error.log

[nginx-botsearch]
enabled  = true
backend  = auto
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 5

[nginx-bad-request]
enabled  = true
backend  = auto
port     = http,https
logpath  = /var/log/nginx/access.log

# ---------- MariaDB ----------
[mysqld-auth]
enabled  = true
backend  = auto
port     = 3306
logpath  = /var/log/mysql/error.log
maxretry = 3

# ---------- Recidentes ------------
[recidive]
enabled  = true
backend  = auto
logpath  = /var/log/fail2ban.log
bantime = 1w
findtime = 1d
maxretry = 3
EOF

echo -e "$G Archivo configurado.$N"
}

# --- Habilitando el servicio ---
habilitar_service() {
echo -e "$B Valiando sintaxis de configuracion.$N"
  fail2ban-client -t
  
echo -e "$B Habilitando e iniciando servicios.$N"
  systemctl enable fail2ban
  systemctl restart fail2ban
echo -e "$G Servicios habilitados.$N"
}


# --- Llamado de funciones ---
verifica_root
install_servicios
confi_mariadb
confi_fail2ban
habilitar_service
