#!/usr/bin/env bash
#===============================================================================
#  backup_rotativo.sh
#
#  Qué hace:
#    1. Crea un respaldo comprimido (.tar.gz) de las carpetas indicadas y de
#       las bases de datos (MariaDB y, opcionalmente, PostgreSQL).
#    2. Lo envía por SSH (con rsync) a OTRA computadora.
#    3. Verifica en la computadora de destino que el archivo llegó íntegro
#       (suma de verificación SHA-256).
#    4. Solo si todo salió bien, borra los respaldos más antiguos en el destino
#       y deja únicamente los últimos KEEP (por defecto 5).
#    5. Borra la copia temporal local: el respaldo NO se queda en este equipo.
#
#  Pensado para: Ubuntu Server 24.04 LTS. Se ejecuta como root desde cron.
#
#  Configuración: crea /etc/itsi-backup.conf (ver la guía). Si el archivo no
#  existe se usan los valores por defecto de la sección siguiente.
#===============================================================================
set -Eeuo pipefail
umask 077
export LC_ALL=C
cd /

#------------------------- VALORES POR DEFECTO ---------------------------------
DEST_USER="backup"                      # usuario en la PC de destino
DEST_HOST="192.168.10.2"                # IP REAL de la PC de destino (no la VIP)
DEST_PORT="22"                          # puerto SSH del destino
DEST_BASE="/home/backup/respaldos"      # carpeta base en el destino
SSH_KEY="/root/.ssh/id_ed25519_backup"  # llave privada (sin contraseña)
KEEP=5                                  # cantidad de respaldos a conservar
SOURCES=(/etc /var/www /home)           # carpetas a respaldar
BACKUP_MARIADB="yes"                    # yes/no
BACKUP_POSTGRES="no"                    # yes/no (Odoo usa PostgreSQL)
STAGING_BASE="/var/backups/itsi-staging" # carpeta temporal local
LOG_FILE="/var/log/itsi-backup.log"
LOCK_FILE="/run/lock/itsi-backup.lock"
RSYNC_TIMEOUT=120                       # segundos sin actividad antes de abortar
BWLIMIT_KBPS=0                          # 0 = sin límite de ancho de banda
#------------------------------------------------------------------------------

CONFIG_FILE="${ITSI_BACKUP_CONF:-/etc/itsi-backup.conf}"
if [[ -r "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

HOST_SHORT="$(hostname -s)"
DEST_DIR="${DEST_BASE}/${HOST_SHORT}"
STAMP="$(date +%Y%m%d_%H%M%S)"
NAME="backup_${HOST_SHORT}_${STAMP}.tar.gz"

WORKDIR=""
TRANSFER_STARTED=0
SUCCESS=0

SSH_OPTS=(
    -i "$SSH_KEY"
    -p "$DEST_PORT"
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o StrictHostKeyChecking=yes
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=3
)

#--------------------------------- FUNCIONES -----------------------------------
log() {
    local level="$1"
    shift
    printf '%s [%s] %s\n' "$(date '+%F %T')" "$level" "$*" | tee -a "$LOG_FILE"
}

fail() {
    log ERROR "$*" >&2
    exit 1
}

remote() {
    # SC2029: la expansión en el cliente es intencional (rutas y nombres ya validados).
    # shellcheck disable=SC2029
    ssh "${SSH_OPTS[@]}" "${DEST_USER}@${DEST_HOST}" "$@"
}

cleanup() {
    # Si la transferencia empezó pero el proceso no terminó bien, se intenta
    # borrar en el destino lo que haya quedado de ESTA corrida.
    if (( TRANSFER_STARTED == 1 && SUCCESS == 0 )); then
        remote "rm -f -- '${DEST_DIR}/${NAME}' '${DEST_DIR}/${NAME}.sha256'" \
            >/dev/null 2>&1 || true
    fi
    # La copia temporal local siempre se elimina.
    if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
        rm -rf -- "$WORKDIR"
    fi
}
trap cleanup EXIT

#------------------------------ VALIDACIONES -----------------------------------
(( EUID == 0 )) || { echo "Este script debe ejecutarse como root." >&2; exit 1; }

touch "$LOG_FILE"
chmod 640 "$LOG_FILE"

# Evita que dos copias corran al mismo tiempo (por ejemplo, si una tarda más de
# 15 minutos). Si ya hay una en marcha, esta sale sin error.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log WARN "Ya hay un respaldo en ejecución; se omite esta corrida."
    exit 0
fi

[[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || fail "KEEP debe ser un entero >= 1 (valor actual: '$KEEP')."
[[ "$BWLIMIT_KBPS" =~ ^[0-9]+$ ]] || fail "BWLIMIT_KBPS debe ser un entero >= 0."
[[ -r "$SSH_KEY" ]] || fail "No se puede leer la llave SSH: $SSH_KEY"

for cmd in tar gzip rsync ssh sha256sum stat; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Falta el comando '$cmd'. Instálalo con apt."
done

DUMP_BIN=""
if [[ "$BACKUP_MARIADB" == "yes" ]]; then
    if command -v mariadb-dump >/dev/null 2>&1; then
        DUMP_BIN="mariadb-dump"
    elif command -v mysqldump >/dev/null 2>&1; then
        DUMP_BIN="mysqldump"
    else
        fail "BACKUP_MARIADB=yes pero no existe mariadb-dump ni mysqldump."
    fi
fi
if [[ "$BACKUP_POSTGRES" == "yes" ]]; then
    command -v pg_dumpall >/dev/null 2>&1 || fail "BACKUP_POSTGRES=yes pero no existe pg_dumpall."
    command -v runuser >/dev/null 2>&1 || fail "Falta el comando 'runuser'."
fi

log INFO "=== Inicio de respaldo: ${NAME} ==="

#------------------------ 1. PREPARAR CARPETA TEMPORAL -------------------------
install -d -m 700 "$STAGING_BASE"
WORKDIR="$(mktemp -d -p "$STAGING_BASE" run.XXXXXX)"
mkdir -p "$WORKDIR/db"

#------------------------ 2. PROBAR CONEXIÓN AL DESTINO ------------------------
# Se prueba antes de gastar tiempo y disco generando el respaldo.
remote "mkdir -p '${DEST_DIR}' && chmod 700 '${DEST_DIR}'" \
    || fail "No se pudo conectar o preparar ${DEST_HOST}:${DEST_DIR} (revisa red, llave y known_hosts)."

#------------------------ 3. VOLCADO DE BASES DE DATOS -------------------------
if [[ "$BACKUP_MARIADB" == "yes" ]]; then
    log INFO "Volcando MariaDB con ${DUMP_BIN}..."
    "$DUMP_BIN" --all-databases --single-transaction --routines --events --triggers \
        | gzip -c > "$WORKDIR/db/mariadb_all.sql.gz" \
        || fail "Falló el volcado de MariaDB."
fi

if [[ "$BACKUP_POSTGRES" == "yes" ]]; then
    log INFO "Volcando PostgreSQL con pg_dumpall..."
    runuser -u postgres -- pg_dumpall \
        | gzip -c > "$WORKDIR/db/postgres_all.sql.gz" \
        || fail "Falló el volcado de PostgreSQL."
fi

#------------------------ 4. CREAR EL ARCHIVO COMPRIMIDO -----------------------
tar_items=()
for src in "${SOURCES[@]}"; do
    if [[ -e "$src" ]]; then
        tar_items+=("${src#/}")
    else
        log WARN "No existe ${src}; se omite."
    fi
done

log INFO "Creando ${NAME}..."
tar_rc=0
tar --numeric-owner -czf "$WORKDIR/$NAME" \
    -C / "${tar_items[@]}" \
    -C "$WORKDIR" db \
    2>>"$LOG_FILE" || tar_rc=$?

# GNU tar: 0 = correcto; 1 = algún archivo cambió mientras se leía (el archivo
# sigue siendo utilizable); 2 = error grave.
if (( tar_rc == 1 )); then
    log WARN "Algunos archivos cambiaron durante la lectura (tar devolvió 1)."
elif (( tar_rc != 0 )); then
    fail "tar falló con código ${tar_rc}."
fi

tar -tzf "$WORKDIR/$NAME" >/dev/null 2>&1 || fail "El archivo generado está dañado."
( cd "$WORKDIR" && sha256sum "$NAME" > "${NAME}.sha256" )
SIZE_BYTES="$(stat -c %s "$WORKDIR/$NAME")"

#------------------------ 5. ENVIAR AL OTRO EQUIPO -----------------------------
rsync_args=(-t "--timeout=${RSYNC_TIMEOUT}" -e "ssh ${SSH_OPTS[*]}")
if (( BWLIMIT_KBPS > 0 )); then
    rsync_args+=("--bwlimit=${BWLIMIT_KBPS}")
fi

log INFO "Enviando a ${DEST_USER}@${DEST_HOST}:${DEST_DIR}/ ..."
TRANSFER_STARTED=1
rsync "${rsync_args[@]}" \
    "$WORKDIR/$NAME" "$WORKDIR/${NAME}.sha256" \
    "${DEST_USER}@${DEST_HOST}:${DEST_DIR}/" \
    || fail "rsync no pudo enviar el respaldo."

#------------------------ 6. VERIFICAR INTEGRIDAD EN EL DESTINO ----------------
remote "cd '${DEST_DIR}' && sha256sum -c -- '${NAME}.sha256'" >/dev/null \
    || fail "La suma SHA-256 en el destino NO coincide; se descarta este respaldo."
log INFO "Integridad verificada en el destino (SHA-256 correcto)."

#------------------------ 7. ROTACIÓN EN EL DESTINO ----------------------------
# Solo se llega aquí si el respaldo nuevo ya está verificado. Así, un fallo
# nunca deja al destino con menos respaldos buenos de los que tenía.
rotation_out="$(
    remote bash -s -- "$DEST_DIR" "$KEEP" <<'REMOTE_EOF'
set -eu
export LC_ALL=C
dir="$1"
keep="$2"
cd "$dir"
shopt -s nullglob
files=(backup_*.tar.gz)
total=${#files[@]}
if (( total > keep )); then
    for f in "${files[@]:0:total-keep}"; do
        rm -f -- "$f" "$f.sha256"
        echo "eliminado: $f"
    done
fi
remaining=(backup_*.tar.gz)
echo "respaldos conservados: ${#remaining[@]}"
find "$dir" -maxdepth 1 -type f -name '.backup_*' -mmin +60 -delete
REMOTE_EOF
)" || fail "Falló la rotación en el destino."

while IFS= read -r line; do
    [[ -n "$line" ]] && log INFO "[destino] ${line}"
done <<< "$rotation_out"

SUCCESS=1
log INFO "=== Respaldo completado: ${NAME} (${SIZE_BYTES} bytes) ==="
