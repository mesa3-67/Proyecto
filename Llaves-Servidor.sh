#!/bin/bash
set -euo pipefail

# Verificar que se ejecute como root para modificar servicios y firewall
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root (sudo)."
  exit 1
fi


# 1. Consultar de forma automática los datos de la máquina local
LOCAL_USER=$(logname || echo $SUDO_USER)
LOCAL_HOST=$(hostname)
LOCAL_IP=$(hostname -I | awk '{print $1}')

echo "=========================================================="
echo " DETECTADOS DATOS DE LA MÁQUINA LOCAL"
echo "=========================================================="
echo "Usuario actual: $LOCAL_USER"
echo "Hostname:       $LOCAL_HOST"
echo "IP Local:       $LOCAL_IP"
echo "=========================================================="
echo ""

# Instalar de forma silenciosa las herramientas de persistencia para iptables
if ! dpkg -s iptables-persistent &> /dev/null; then
    echo "Instalando herramientas de persistencia para iptables..."
    export DEBIAN_FRONTEND=noninteractive
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
    apt-get update -y && apt-get install -y iptables-persistent netfilter-persistent
else
    echo "iptables-persistent ya está instalado. Omitiendo instalación."
fi

# 2. Preguntar explícitamente al usuario en la consola si desea ser Master o Esclava
ROL=""
while true; do
    echo "¿Qué rol deseas asignar a esta máquina?"
    echo "1) Master"
    echo "2) Esclava"
    read -p "Selecciona una opción (1 o 2): " OPNC
    
    case $OPNC in
        1)
            ROL="Master"
            break
            ;;
        2)
            ROL="Esclava"
            break
            ;;
        *)
            echo -e "Opción no válida. Por favor selecciona 1 o 2.\n"
            ;;
    esac
done

echo -e "\n>>> Configurando este nodo como: $ROL <<<\n"

# Pedir la IP de la otra máquina para las reglas de red y firewall
read -p "Por favor, introduce la dirección IP de la OTRA máquina (nodo remoto): " IP_DEL_OTRO_NODO

if [ -z "$IP_DEL_OTRO_NODO" ]; then
    echo "La IP del otro nodo es obligatoria para configurar iptables y Fail2ban. Saliendo."
    exit 1
fi

# 3. Generación y configuración local de llaves SSH (Secciones 5 y 7)
USER_HOME=$(eval echo ~$LOCAL_USER)
SSH_DIR="$USER_HOME/.ssh"

if [ ! -d "$SSH_DIR" ]; then
    mkdir -p "$SSH_DIR"
fi

if [ ! -f "$SSH_DIR/id_ed25519" ]; then
    echo "Generando par de llaves SSH ed25519..."
    ssh-keygen -t ed25519 -N "" -f "$SSH_DIR/id_ed25519" -C "$LOCAL_USER@$LOCAL_HOST"
else
    echo "El par de llaves SSH ya existe en $SSH_DIR/id_ed25519."
fi

# Ajustar permisos estrictos
chmod 700 "$SSH_DIR"
if [ -f "$SSH_DIR/authorized_keys" ]; then
    chmod 600 "$SSH_DIR/authorized_keys"
fi
chown -R "$LOCAL_USER:$LOCAL_USER" "$SSH_DIR"

# 4. Inyección EOF para configurar Fail2ban (Sección 13.2)
JAIL_LOCAL="/etc/fail2ban/jail.local"
echo "Configurando directivas en $JAIL_LOCAL..."
mkdir -p /etc/fail2ban

cat << EOF > "$JAIL_LOCAL"
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 $LOCAL_IP $IP_DEL_OTRO_NODO

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF

echo "Archivo $JAIL_LOCAL inyectado con éxito."

# 5. Aplicar reglas de iptables (Sección 13.1)
echo "Aplicando reglas de iptables para el puerto 22..."

# Intentar pausar Fail2ban si el servicio existe para evitar guardar cadenas f2b temporales
if systemctl list-units --full --all | grep -q "fail2ban.service"; then
    systemctl stop fail2ban
fi

# Insertar la regla en la cadena INPUT (permitir tráfico SSH desde el otro nodo)
iptables -I INPUT 3 -p tcp --dport 22 -s "$IP_DEL_OTRO_NODO" -j ACCEPT

# Guardar las reglas persistentemente si netfilter-persistent está instalado
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
else
    echo "Aviso: netfilter-persistent no está instalado. Las reglas de iptables podrían no persistir tras reiniciar."
fi

# Reanudar o iniciar Fail2ban
if systemctl list-units --full --all | grep -q "fail2ban.service"; then
    systemctl start fail2ban
    fail2ban-client reload &> /dev/null
fi

# 6. Endurecimiento de OpenSSH (Sección 9)
SSHD_CONFIG="/etc/ssh/sshd_config"
echo "Aplicando endurecimiento del servicio SSH en $SSHD_CONFIG..."

cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"

set_sshd_directive() {
    local key="$1"
    local value="$2"
    if grep -q "^#\?$key" "$SSHD_CONFIG"; then
        sed -i "s|^#\?$key.*|$key $value|" "$SSHD_CONFIG"
    else
        echo "$key $value" >> "$SSHD_CONFIG"
    fi
}

set_sshd_directive "PubkeyAuthentication" "yes"
set_sshd_directive "PasswordAuthentication" "no"
set_sshd_directive "KbdInteractiveAuthentication" "no"
set_sshd_directive "PermitRootLogin" "no"
set_sshd_directive "MaxAuthTries" "3"
set_sshd_directive "LoginGraceTime" "30"

# Validar y reiniciar
if sshd -t; then
    echo "La sintaxis de SSH es correcta. Reiniciando servicio..."
    systemctl restart ssh
    echo "¡Proceso finalizado! Este nodo ha quedado configurado como $ROL."
else
    echo "Error crítico en la configuración de sshd_config. Restaurando copia de seguridad..."
    mv "${SSHD_CONFIG}.bak" "$SSHD_CONFIG"
    systemctl restart ssh
    exit 1
fi

