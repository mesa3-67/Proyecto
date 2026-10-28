#!/usr/bin/env bash
#===============================================================================
#  instalar_backup_terraform.sh
#
#  Instalador de RESPALDOS AUTOMÁTICOS CON ROTACIÓN usando Terraform
#  (Ubuntu Server 24.04 LTS · PostgreSQL · cada 15 minutos · 5 copias)
#
#  Qué hace, en una frase:
#    Pregunta si esta PC es el ORIGEN (tiene los datos) o el DESTINO (guarda las
#    copias), instala Terraform si falta, y deja que Terraform configure la PC:
#      ORIGEN : paquetes, llave SSH, script de respaldo, configuración, cron,
#               rotación del log y (cuando el destino está listo) primer respaldo.
#      DESTINO: paquetes, usuario sin contraseña, carpeta, llave autorizada.
#
#  Es IDEMPOTENTE: puedes ejecutarlo todas las veces que quieras; si todo ya está
#  bien, Terraform responde "sin cambios" y no se modifica nada. Si algo fue
#  borrado o alterado a mano, lo detecta y lo repara.
#
#  Si ocurre CUALQUIER error, el script se detiene en el acto y lo informa por
#  consola (y en /var/log/itsi-backup-instalador.log).
#
#  Uso:   sudo ./instalar_backup_terraform.sh            (modo interactivo)
#         sudo ./instalar_backup_terraform.sh --estado   (¿sigue todo en orden?)
#         sudo ./instalar_backup_terraform.sh --desinstalar
#         ./instalar_backup_terraform.sh --extraer CARPETA  (solo escribe los
#                                                            archivos Terraform)
#         ./instalar_backup_terraform.sh --ayuda
#===============================================================================
set -Eeuo pipefail
umask 022
export LC_ALL=C

VERSION_INSTALADOR="1.0"
BASE_DIR="${ITSI_DIR_BASE:-/opt/itsi-backup}"
LOG_FILE="${ITSI_LOG_INSTALADOR:-/var/log/itsi-backup-instalador.log}"
LOCK_DIR="${ITSI_LOCK_DIR:-/run/lock}"
TF_BIN="${ITSI_TF_BIN:-terraform}"
TF_MIN="1.4.0"
# Huella VIGENTE de la llave con la que HashiCorp firma su repositorio apt
# (publicada en https://www.hashicorp.com/security). La anterior,
# 798A EC65 4E5C 1542 8C8E 42EE AA16 FCBC A621 E701, se usó hasta el 10-sep-2026.
HASHICORP_FPR_VIGENTE="D55C0D1AC78A8D8126CB631CFC9CA96ACA026560"
KEYRING="/usr/share/keyrings/hashicorp-archive-keyring.gpg"
APT_LIST="/etc/apt/sources.list.d/hashicorp.list"

LOG_LISTO=0
ERROR_REPORTADO=0
ACCION="instalar"
EXTRAER_DIR=""
TMP_LIST=()

if [[ -t 1 ]]; then
    C_ROJO=$'\e[31m'; C_VERDE=$'\e[32m'; C_AMARILLO=$'\e[33m'; C_AZUL=$'\e[36m'; C_NEG=$'\e[1m'; C_FIN=$'\e[0m'
else
    C_ROJO=""; C_VERDE=""; C_AMARILLO=""; C_AZUL=""; C_NEG=""; C_FIN=""
fi

#------------------------------- MENSAJES --------------------------------------
_log() {
    local nivel="$1"
    shift
    if (( LOG_LISTO == 1 )); then
        printf '%s [%s] %s\n' "$(date '+%F %T')" "$nivel" "$*" >> "$LOG_FILE"
    fi
}
info()   { printf '%s[INFO]%s  %s\n' "$C_AZUL" "$C_FIN" "$*"; _log INFO "$*"; }
ok()     { printf '%s[ OK ]%s  %s\n' "$C_VERDE" "$C_FIN" "$*"; _log OK "$*"; }
warn()   { printf '%s[AVISO]%s %s\n' "$C_AMARILLO" "$C_FIN" "$*" >&2; _log AVISO "$*"; }
titulo() { printf '\n%s== %s ==%s\n' "$C_NEG" "$*" "$C_FIN"; _log INFO "== $* =="; }

fail() {
    ERROR_REPORTADO=1
    printf '\n%s[ERROR]%s %s\n' "$C_ROJO" "$C_FIN" "$*" >&2
    _log ERROR "$*"
    exit 1
}

on_err() {
    local rc="$1" linea="$2" cmd="$3"
    if (( ERROR_REPORTADO == 0 )); then
        ERROR_REPORTADO=1
        printf '\n%s[ERROR]%s Falló un comando inesperadamente (código %s) en la línea %s:\n         %s\n' \
            "$C_ROJO" "$C_FIN" "$rc" "$linea" "$cmd" >&2
        _log ERROR "Falló un comando (código $rc) en la línea $linea: $cmd"
    fi
}

on_exit() {
    local rc=$?
    local d
    for d in "${TMP_LIST[@]:-}"; do
        [[ -n "$d" && -e "$d" ]] && rm -rf -- "$d"
    done
    if (( rc != 0 )); then
        printf '%s[ERROR]%s El instalador se detuvo (código %s). Nada más se ejecutó después del error.\n' \
            "$C_ROJO" "$C_FIN" "$rc" >&2
        if (( LOG_LISTO == 1 )); then
            printf '        Detalle completo en: %s\n' "$LOG_FILE" >&2
        fi
    fi
}
trap 'on_err $? $LINENO "$BASH_COMMAND"' ERR
trap on_exit EXIT

nuevo_tmp() {
    local t
    t="$(mktemp -d)"
    TMP_LIST+=("$t")
    printf '%s' "$t"
}

#--------------------------------- AYUDA ---------------------------------------
uso() {
    cat <<EOF
Instalador de respaldos con Terraform v${VERSION_INSTALADOR} (Ubuntu Server 24.04 LTS)

Uso:
  sudo $0                  Instalación interactiva (pregunta si es ORIGEN o DESTINO)
  sudo $0 --estado         Comprueba si la PC sigue como Terraform la dejó
  sudo $0 --desinstalar    Retira cron, script y configuración del ORIGEN
  $0 --extraer CARPETA     Solo escribe los archivos Terraform (para hacerlo a mano)
  $0 --ayuda               Esta ayuda

Orden recomendado:
  1) ORIGEN   (crea la llave SSH y la muestra)      -> responde "n" a "¿destino listo?"
  2) DESTINO  (pegas la llave pública del origen)
  3) ORIGEN otra vez (confirma la huella, prueba la conexión, primer respaldo)

Respuestas automáticas (sin preguntas), mediante variables de entorno:
  ITSI_ROL=origen|destino          ITSI_REUTILIZAR=s|n
  Origen : ITSI_DEST_HOST  ITSI_DEST_USER  ITSI_DEST_PORT  ITSI_DEST_BASE
           ITSI_FUENTES    ITSI_KEEP       ITSI_INTERVALO  ITSI_RESPALDAR_POSTGRESQL=s|n
           ITSI_DESTINO_LISTO=s|n          ITSI_HUELLA_OK=s|n
  Destino: ITSI_USUARIO  ITSI_CARPETA  ITSI_ORIGEN_IP  ITSI_LLAVE_PUBLICA
Otras: ITSI_DIR_BASE (carpeta de los proyectos, por defecto /opt/itsi-backup),
       ITSI_PERMITIR_DESTINO_LOCAL=1 (solo pruebas), ITSI_PERMITIR_OTRO_SO=1,
       ITSI_HASHICORP_FPR=<huella> (si HashiCorp rota otra vez su llave).
EOF
}

#--------------------------- ARGUMENTOS ----------------------------------------
while (( $# > 0 )); do
    case "$1" in
        -h|--ayuda|--help) uso; exit 0 ;;
        --version) echo "instalar_backup_terraform.sh v${VERSION_INSTALADOR}"; exit 0 ;;
        --extraer)
            ACCION="extraer"
            [[ $# -ge 2 && -n "$2" ]] || fail "--extraer necesita una carpeta de destino. Ejemplo: $0 --extraer /opt/itsi-backup"
            EXTRAER_DIR="$2"
            shift
            ;;
        --estado) ACCION="estado" ;;
        --desinstalar) ACCION="desinstalar" ;;
        *) fail "Opción desconocida: '$1'. Usa --ayuda." ;;
    esac
    shift
done

#------------------------ ARCHIVOS DEL PROYECTO TERRAFORM ----------------------
# Se escriben TAL CUAL (heredoc con delimitador entre comillas: no se expande nada).
# escribir_si_cambia solo toca el archivo si su contenido cambió (idempotencia).
escribir_si_cambia() {
    local dst="$1" modo="$2" tmp
    tmp="$(mktemp)"
    cat > "$tmp"
    if [[ -f "$dst" ]] && cmp -s "$tmp" "$dst"; then
        chmod "$modo" "$dst"
    else
        install -m "$modo" "$tmp" "$dst"
    fi
    rm -f "$tmp"
}

#@@PROYECTO@@

#------------------------------ PREGUNTAS --------------------------------------
# ask VAR "Pregunta" "defecto" "regex" "mensaje de error"
#   - Si existe la variable de entorno ITSI_<VAR>, la usa sin preguntar.
#   - Si la respuesta no es válida: en modo interactivo reintenta (máx. 3 veces);
#     con variable de entorno falla de inmediato.
ask() {
    local _var="$1" _q="$2" _def="${3:-}" _re="${4:-}" _msg="${5:-Valor no válido.}"
    local _env="ITSI_${_var}" _val="" _intentos=0 _desde_env=0 _prompt
    if [[ -n "${!_env+x}" ]]; then
        _val="${!_env}"
        _desde_env=1
    fi
    while :; do
        if (( _desde_env == 0 )); then
            _prompt="$_q"
            [[ -n "$_def" ]] && _prompt+=" [$_def]"
            _prompt+=": "
            printf '%s' "$_prompt" >&2
            IFS= read -r _val || fail "No hay entrada disponible para responder: '$_q'. Para modo automático usa ${_env}=..."
            [[ -z "$_val" ]] && _val="$_def"
        fi
        if [[ -z "$_re" || "$_val" =~ $_re ]]; then
            printf -v "$_var" '%s' "$_val"
            _log INFO "Respuesta $_var='$_val'"
            return 0
        fi
        if (( _desde_env == 1 )); then
            fail "El valor de ${_env} no es válido ('$_val'). $_msg"
        fi
        printf '%s[AVISO]%s %s (escribiste: "%s")\n' "$C_AMARILLO" "$C_FIN" "$_msg" "$_val" >&2
        _intentos=$((_intentos + 1))
        (( _intentos < 3 )) || fail "Demasiados intentos con respuestas no válidas. Vuelve a ejecutar el instalador."
    done
}

# confirm VAR "Pregunta" s|n  -> devuelve 0 si la respuesta es sí
confirm() {
    local _var="$1" _q="$2" _def="${3:-n}" _ans=""
    ask "$_var" "$_q" "$_def" '^([sS]|[sS][iíIÍ]|[yY]|[yY][eE][sS]|[nN]|[nN][oO])$' "Responde s (sí) o n (no)."
    _ans="${!_var}"
    [[ "$_ans" =~ ^([sS]|[sS][iíIÍ]|[yY]|[yY][eE][sS])$ ]]
}

RE_HOST='^[A-Za-z0-9._-]+$'
RE_USER='^[a-z][a-z0-9_-]{0,31}$'
RE_PORT='^[0-9]{1,5}$'
RE_RUTA='^/[A-Za-z0-9._/-]+$'
RE_KEEP='^[1-9][0-9]{0,2}$'
RE_INTERVALO='^(1|2|3|4|5|6|10|12|15|20|30)$'
RE_PUBKEY='^ssh-ed25519 [A-Za-z0-9+/]+={0,2}( [A-Za-z0-9._@-]+)?$'
RE_IPORIGEN='^[A-Za-z0-9._:/-]*$'

validar_fuentes() {
    local f
    [[ -n "$1" ]] || return 1
    for f in $1; do
        [[ "$f" =~ ^/[A-Za-z0-9._/-]*$ ]] || return 1
    done
    return 0
}

es_destino_local() {
    local h="$1" ip
    case "$h" in localhost|127.*|::1|"$(hostname)"|"$(hostname -s)") return 0 ;; esac
    for ip in $(hostname -I 2>/dev/null || true); do
        [[ "$h" == "$ip" ]] && return 0
    done
    return 1
}

#------------------------------ VERIFICACIONES ---------------------------------
requerir_root() {
    (( EUID == 0 )) || fail "Este instalador debe ejecutarse como root. Usa: sudo $0"
}

verificar_so() {
    local id="" ver=""
    if [[ -r /etc/os-release ]]; then
        id="$(. /etc/os-release && printf '%s' "${ID:-}")"
        ver="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
    fi
    if [[ "$id" != "ubuntu" || "$ver" != "24.04" ]]; then
        if [[ "${ITSI_PERMITIR_OTRO_SO:-0}" == "1" ]]; then
            warn "Sistema detectado: ${id:-desconocido} ${ver:-?}. Este proyecto está probado en Ubuntu Server 24.04 LTS; continúas bajo tu responsabilidad."
        else
            fail "Sistema detectado: ${id:-desconocido} ${ver:-?}. Este instalador es solo para Ubuntu Server 24.04 LTS."
        fi
    fi
    ok "Sistema: Ubuntu $ver"
}

preparar_log_y_candado() {
    install -d -m 755 "$(dirname "$LOG_FILE")"
    [[ -f "$LOG_FILE" ]] || install -m 600 /dev/null "$LOG_FILE"
    LOG_LISTO=1
    _log INFO "---- Inicio: instalador v${VERSION_INSTALADOR}, acción=${ACCION}, usuario=$(id -un) ----"
    [[ -d "$LOCK_DIR" ]] || install -d -m 755 "$LOCK_DIR"
    exec 8>"$LOCK_DIR/itsi-backup-instalador.lock"
    flock -n 8 || fail "Ya hay otra copia del instalador ejecutándose. Espera a que termine."
}

#------------------------------ TERRAFORM --------------------------------------
version_ge() { # version_ge A B -> 0 si A >= B
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" == "$2" ]]
}

tf_version_actual() {
    "$TF_BIN" version 2>/dev/null | head -n 1 | sed -E 's/^[^0-9]*([0-9]+(\.[0-9]+)*).*/\1/'
}

instalar_terraform_apt() {
    local tmp codename arch fprs esperado cand
    local -a aceptadas=("$HASHICORP_FPR_VIGENTE")
    local f encontrada=0
    titulo "Instalando Terraform desde el repositorio oficial de HashiCorp"
    command -v apt-get >/dev/null 2>&1 || fail "No existe apt-get; este instalador es para Ubuntu."

    info "Instalando requisitos (ca-certificates, curl, gpg)..."
    apt-get -o DPkg::Lock::Timeout=120 update -qq \
        || warn "apt-get update devolvió errores (algún repositorio no responde); intento continuar."
    apt-get -o DPkg::Lock::Timeout=120 install -y -qq ca-certificates curl gpg \
        || fail "No se pudieron instalar ca-certificates, curl y gpg (¿hay Internet?)."

    codename="$( . /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
    [[ -n "$codename" ]] || fail "No pude determinar el nombre en clave de Ubuntu (UBUNTU_CODENAME)."
    arch="$(dpkg --print-architecture)"

    tmp="$(nuevo_tmp)"
    info "Descargando la llave de firma de HashiCorp..."
    curl -fsSL --retry 3 --max-time 60 -o "$tmp/hashicorp.asc" https://apt.releases.hashicorp.com/gpg \
        || fail "No se pudo descargar https://apt.releases.hashicorp.com/gpg. Revisa Internet, DNS o el proxy de la red. (Alternativa: instala Terraform a mano; ver el manual, camino B.)"
    gpg --batch --yes --dearmor -o "$tmp/hashicorp.gpg" "$tmp/hashicorp.asc" \
        || fail "La llave descargada no es una llave GPG válida."

    if [[ -n "${ITSI_HASHICORP_FPR:-}" ]]; then
        esperado="$(printf '%s' "$ITSI_HASHICORP_FPR" | tr -d ' ' | tr '[:lower:]' '[:upper:]')"
        [[ "$esperado" =~ ^[0-9A-F]{40}$ ]] || fail "ITSI_HASHICORP_FPR debe tener 40 caracteres hexadecimales (sin espacios)."
        aceptadas+=("$esperado")
    fi
    fprs="$(gpg --batch --show-keys --with-colons "$tmp/hashicorp.gpg" | awk -F: '$1=="fpr"{print toupper($10)}')"
    for f in $fprs; do
        for esperado in "${aceptadas[@]}"; do
            [[ "$f" == "$esperado" ]] && encontrada=1
        done
    done
    if (( encontrada == 0 )); then
        fail "La huella de la llave descargada NO coincide con la esperada ($HASHICORP_FPR_VIGENTE).
         Huellas recibidas: $(printf '%s ' $fprs)
         NO se instaló nada. Compara con la huella publicada en https://www.hashicorp.com/security
         y, solo si coincide, vuelve a ejecutar con: ITSI_HASHICORP_FPR=<huella> sudo -E $0"
    fi
    ok "Huella de la llave de HashiCorp verificada"

    install -m 0644 "$tmp/hashicorp.gpg" "$KEYRING"
    printf 'deb [arch=%s signed-by=%s] https://apt.releases.hashicorp.com %s main\n' "$arch" "$KEYRING" "$codename" \
        | escribir_si_cambia "$APT_LIST" 644

    info "Actualizando la lista de paquetes e instalando terraform..."
    apt-get -o DPkg::Lock::Timeout=120 update -qq \
        || warn "apt-get update devolvió errores; verifico si Terraform quedó disponible."
    cand="$(apt-cache policy terraform 2>/dev/null | awk '/Candidate:/{print $2}')"
    if [[ -z "$cand" || "$cand" == "(none)" ]]; then
        fail "apt no encuentra el paquete 'terraform' en el repositorio de HashiCorp para '$codename'. Revisa la conexión y $APT_LIST."
    fi
    apt-get -o DPkg::Lock::Timeout=120 install -y -qq terraform \
        || fail "No se pudo instalar el paquete terraform."
}

asegurar_terraform() {
    local v=""
    if command -v "$TF_BIN" >/dev/null 2>&1; then
        v="$(tf_version_actual)"
        [[ -n "$v" ]] || fail "$TF_BIN está instalado pero no pude leer su versión."
        if version_ge "$v" "$TF_MIN"; then
            ok "$TF_BIN $v ya está instalado (se requiere >= $TF_MIN)"
            return 0
        fi
        warn "$TF_BIN $v es anterior a la mínima ($TF_MIN)."
    fi
    [[ "$TF_BIN" == "terraform" ]] \
        || fail "ITSI_TF_BIN=$TF_BIN no está instalado o es muy antiguo; solo 'terraform' se instala automáticamente."
    instalar_terraform_apt
    command -v terraform >/dev/null 2>&1 || fail "Terraform no quedó disponible en el PATH tras la instalación."
    v="$(tf_version_actual)"
    [[ -n "$v" ]] && version_ge "$v" "$TF_MIN" || fail "Quedó instalada la versión '$v', pero se requiere >= $TF_MIN."
    ok "Terraform $v instalado"
}

tf_cmd() { # tf_cmd DIR subcomando args...
    local dir="$1"
    shift
    "$TF_BIN" -chdir="$dir" "$@"
}

# PARES recurso:paso  (para verificar que la PC sigue como Terraform la dejó)
PARES_ORIGEN=(paquetes:origen_paquetes llave_ssh:origen_llave script_respaldo:origen_script
              configuracion:origen_config cron:origen_cron logrotate:origen_logrotate
              conexion:origen_conexion primer_respaldo:origen_primer_respaldo)
PARES_DESTINO=(paquetes:destino_paquetes usuario:destino_usuario llave_autorizada:destino_llave
               verificar_ssh:destino_ssh)

# verificar_pasos ROL DIR MODO   (MODO = reporte | reparar)
#   Corre "pasos.sh <paso> --verificar" con el MISMO entorno que Terraform aplicó
#   la última vez. Los pasos que ya no están bien se acumulan en REEMPLAZOS
#   (-replace=...), que obliga a Terraform a volver a aplicarlos.
REEMPLAZOS=()
verificar_pasos() {
    local rol="$1" dir="$2" modo="$3"
    local estado entorno par recurso paso addr k v resultado=0 linea
    local -a pares
    REEMPLAZOS=()
    if [[ "$rol" == "origen" ]]; then pares=("${PARES_ORIGEN[@]}"); else pares=("${PARES_DESTINO[@]}"); fi
    estado="$(tf_cmd "$dir" state list 2>/dev/null || true)"
    if [[ -z "$estado" ]]; then
        [[ "$modo" == "reporte" ]] && info "Todavía no hay nada aplicado por Terraform en $dir."
        return 0
    fi
    entorno="$(tf_cmd "$dir" output -raw entorno_shell 2>/dev/null || true)"
    if [[ -z "$entorno" ]]; then
        [[ "$modo" == "reporte" ]] && warn "No se pudo leer el entorno guardado por Terraform."
        return 0
    fi
    while IFS= read -r linea; do
        k="${linea%%=*}"
        v="${linea#*=}"
        if [[ "$k" =~ ^ITSI_[A-Z_]+$ ]]; then export "$k=$v"; fi
    done <<< "$entorno"
    for par in "${pares[@]}"; do
        recurso="${par%%:*}"
        paso="${par##*:}"
        addr="$(grep -E "^terraform_data\.${recurso}(\[[0-9]+\])?\$" <<< "$estado" | head -n 1 || true)"
        [[ -n "$addr" ]] || continue
        if bash "$dir/files/pasos.sh" "$paso" --verificar >/dev/null 2>&1; then
            [[ "$modo" == "reporte" ]] && ok "$paso: en orden"
        else
            resultado=1
            REEMPLAZOS+=("-replace=$addr")
            if [[ "$modo" == "reporte" ]]; then
                warn "$paso: NO está como Terraform lo dejó (se repara al ejecutar el instalador)"
            else
                warn "Se detectó que '$paso' fue alterado o borrado: Terraform lo volverá a aplicar."
            fi
        fi
    done
    return "$resultado"
}

# terraform_aplicar ROL DIR
terraform_aplicar() {
    local rol="$1" dir="$2" salida
    export TF_IN_AUTOMATION=1 TF_INPUT=0
    titulo "Terraform: init"
    salida="$(mktemp)"
    TMP_LIST+=("$salida")
    if ! tf_cmd "$dir" init -input=false -no-color 2>&1 | tee -a "$salida"; then
        fail "terraform init falló. Mira el mensaje de arriba."
    fi
    _log INFO "terraform init OK"
    titulo "Terraform: validate"
    if ! tf_cmd "$dir" validate -no-color 2>&1 | tee -a "$salida"; then
        fail "terraform validate encontró errores en la configuración (arriba está el detalle)."
    fi
    verificar_pasos "$rol" "$dir" reparar || true
    titulo "Terraform: apply"
    : > "$salida"
    if ! tf_cmd "$dir" apply -input=false -auto-approve -no-color "${REEMPLAZOS[@]}" 2>&1 | tee -a "$salida"; then
        [[ -f "$LOG_FILE" ]] && cat "$salida" >> "$LOG_FILE"
        local causas
        causas="$(grep -E '\[ERROR\]|Error:|validation|Invalid' "$salida" | head -n 8 || true)"
        fail "Terraform no pudo completar el 'apply'. Causa(s) principal(es):
$causas
         (Todo lo anterior al error ya quedó aplicado; al corregir la causa y volver a ejecutar, continúa sin repetir lo hecho.)"
    fi
    cat "$salida" >> "$LOG_FILE"
    ok "terraform apply terminado sin errores"
}

#------------------------ LECTURA/ESCRITURA DE terraform.tfvars ----------------
tfvar_get() { # tfvar_get ARCHIVO CLAVE -> valor sin comillas
    local f="$1" k="$2"
    [[ -f "$f" ]] || return 0
    sed -n -E "s/^${k}[[:space:]]*=[[:space:]]*//p" "$f" | head -n 1 | sed -E 's/^"//; s/"[[:space:]]*$//'
}
tfvar_get_lista() { # lista HCL ["/a", "/b"] -> /a /b
    local f="$1" k="$2"
    [[ -f "$f" ]] || return 0
    sed -n -E "s/^${k}[[:space:]]*=[[:space:]]*\[(.*)\][[:space:]]*$/\1/p" "$f" | head -n 1 | tr -d '"' | tr ',' ' ' | tr -s ' ' | sed -E 's/^ //; s/ $//'
}
lista_hcl() { # "/a /b" -> "/a", "/b"
    local out="" f
    for f in $1; do out+="\"$f\", "; done
    printf '%s' "${out%, }"
}

#------------------------------ FLUJO: ORIGEN ----------------------------------
asegurar_known_hosts() {
    local host="$R_DEST_HOST" port="$R_DEST_PORT" kh="/root/.ssh/known_hosts" entry scan tmp fp
    [[ "$port" == "22" ]] && entry="$host" || entry="[$host]:$port"
    install -d -m 700 /root/.ssh
    [[ -f "$kh" ]] || install -m 600 /dev/null "$kh"
    if ssh-keygen -F "$entry" -f "$kh" >/dev/null 2>&1; then
        ok "El destino ($entry) ya figura en known_hosts (huella ya confiada)"
        return 0
    fi
    info "Obteniendo la huella SSH del destino ($host:$port)..."
    tmp="$(nuevo_tmp)"
    scan="$(ssh-keyscan -T 10 -p "$port" -t ed25519 "$host" 2>/dev/null || true)"
    [[ -n "$scan" ]] || fail "No pude obtener la huella SSH de $host:$port. Revisa que el destino esté encendido, que SSH escuche en ese puerto y que el firewall lo permita."
    printf '%s\n' "$scan" > "$tmp/scan"
    fp="$(ssh-keygen -lf "$tmp/scan" | awk '{print $2}' | head -n 1)"
    [[ -n "$fp" ]] || fail "No pude calcular la huella recibida del destino."
    printf '\n  Huella (ED25519) que presenta el destino:\n      %s%s%s\n' "$C_NEG" "$fp" "$C_FIN"
    printf '  Debe ser IDÉNTICA a la que mostró el instalador al terminar en la PC DESTINO.\n'
    printf '  (También puedes verla allí con: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub)\n\n'
    confirm HUELLA_OK "¿La huella coincide? (s/N)" n \
        || fail "Huella no confirmada. No se guardó nada en known_hosts. Revisa la IP del destino y vuelve a ejecutar."
    cat "$tmp/scan" >> "$kh"
    ok "Huella del destino guardada en $kh"
}

escribir_tfvars_origen() {
    local dir="$1" listo="$2"
    escribir_si_cambia "$dir/terraform.tfvars" 600 <<EOF
# Generado por instalar_backup_terraform.sh (puedes editarlo; vuelve a ejecutar el instalador).
destino_host         = "$R_DEST_HOST"
destino_user         = "$R_DEST_USER"
destino_port         = $R_DEST_PORT
destino_base         = "$R_DEST_BASE"
ssh_key_path         = "$R_SSH_KEY"
keep                 = $R_KEEP
intervalo_minutos    = $R_INTERVALO
fuentes              = [$(lista_hcl "$R_FUENTES")]
respaldar_postgresql = $R_POSTGRES
destino_listo        = $listo
EOF
}

flujo_origen() {
    local dir="$BASE_DIR/origen" tv="$BASE_DIR/origen/terraform.tfvars" reutilizar=0
    titulo "Configuración de la PC ORIGEN"
    emitir_origen "$dir"
    R_SSH_KEY="/root/.ssh/id_ed25519_itsi_backup"
    R_DESTINO_YA_LISTO="false"

    if [[ -f "$tv" ]] && confirm REUTILIZAR "Ya existe una configuración guardada del ORIGEN. ¿Reutilizarla sin volver a preguntar? (S/n)" s; then
        reutilizar=1
        R_DEST_HOST="$(tfvar_get "$tv" destino_host)"
        R_DEST_USER="$(tfvar_get "$tv" destino_user)"
        R_DEST_PORT="$(tfvar_get "$tv" destino_port)"
        R_DEST_BASE="$(tfvar_get "$tv" destino_base)"
        R_SSH_KEY="$(tfvar_get "$tv" ssh_key_path)"
        R_KEEP="$(tfvar_get "$tv" keep)"
        R_INTERVALO="$(tfvar_get "$tv" intervalo_minutos)"
        R_FUENTES="$(tfvar_get_lista "$tv" fuentes)"
        R_POSTGRES="$(tfvar_get "$tv" respaldar_postgresql)"
        R_DESTINO_YA_LISTO="$(tfvar_get "$tv" destino_listo)"
        [[ -n "$R_DEST_HOST" && -n "$R_DEST_USER" && -n "$R_DEST_PORT" && -n "$R_DEST_BASE" && -n "$R_KEEP" \
           && -n "$R_INTERVALO" && -n "$R_FUENTES" && -n "$R_POSTGRES" ]] \
            || fail "El archivo $tv está incompleto o dañado. Bórralo y vuelve a ejecutar para responder las preguntas de nuevo."
        info "Se reutiliza la configuración de $tv"
    else
        local d_user="itsibackup" d_base d_fuentes="/etc /var/www /home" d_pg="s" _dummy
        [[ -f "$tv" ]] && d_user="$(tfvar_get "$tv" destino_user)"
        cat <<'TXT'

  A continuación se piden los datos. Entre corchetes aparece el valor por defecto
  (pulsa Enter para aceptarlo).

  1) Datos de la PC DESTINO (la otra computadora que guardará las copias):
TXT
        ask DEST_HOST "     IP REAL del destino (nunca la IP virtual de keepalived)" "" "$RE_HOST" "Usa una IP o nombre válido (letras, números, punto, guion)."
        if es_destino_local "$R_DEST_HOST"; then
            if [[ "${ITSI_PERMITIR_DESTINO_LOCAL:-0}" == "1" ]]; then
                warn "El destino ($R_DEST_HOST) es ESTA MISMA PC. Se permite solo porque ITSI_PERMITIR_DESTINO_LOCAL=1 (pruebas)."
            else
                fail "El destino ($R_DEST_HOST) es esta misma PC. Un respaldo en la misma computadora no protege contra su falla. Indica la IP REAL de la OTRA PC."
            fi
        fi
        ask DEST_USER "     Usuario SSH del destino (no uses 'backup': es una cuenta del sistema en Ubuntu)" "$d_user" "$RE_USER" "Minúsculas, números, guion o guion bajo; empieza con letra."
        if [[ "$R_DEST_USER" == "backup" ]]; then
            fail "'backup' es una cuenta del sistema de Ubuntu (uid 34, sin shell). Usa otro nombre, por ejemplo itsibackup."
        fi
        ask DEST_PORT "     Puerto SSH del destino" "22" "$RE_PORT" "Debe ser un número."
        (( R_DEST_PORT >= 1 && R_DEST_PORT <= 65535 )) || fail "El puerto debe estar entre 1 y 65535."
        d_base="/home/${R_DEST_USER}/respaldos"
        ask DEST_BASE "     Carpeta del destino donde se guardan las copias (debe ser la misma que se use en el destino)" "$d_base" "$RE_RUTA" "Ruta absoluta sin espacios."
        cat <<'TXT'

  2) Qué se respalda y cada cuánto:
TXT
        ask FUENTES "     Carpetas a respaldar, separadas por espacio" "$d_fuentes" "" ""
        validar_fuentes "$R_FUENTES" || fail "Las carpetas a respaldar deben ser rutas absolutas sin espacios ni caracteres especiales (valor: '$R_FUENTES')."
        for _dummy in $R_FUENTES; do
            [[ -e "$_dummy" ]] || warn "La carpeta $_dummy no existe en esta PC; el respaldo la omitirá con un aviso."
        done
        ask KEEP "     Cuántos respaldos conservar" "5" "$RE_KEEP" "Un entero entre 1 y 999."
        (( R_KEEP <= 365 )) || fail "KEEP debe estar entre 1 y 365."
        ask INTERVALO "     Cada cuántos minutos respaldar (1,2,3,4,5,6,10,12,15,20,30)" "15" "$RE_INTERVALO" "El valor debe dividir 60 exactamente."
        if command -v pg_dumpall >/dev/null 2>&1 && id postgres >/dev/null 2>&1; then d_pg="s"; else d_pg="n"; fi
        if confirm RESPALDAR_POSTGRESQL "     ¿Esta PC tiene PostgreSQL y quieres incluir un volcado completo? (s/n)" "$d_pg"; then
            R_POSTGRES="true"
        else
            R_POSTGRES="false"
        fi
    fi

    # Archivos de configuración de Terraform con el estado ACTUAL de "destino_listo"
    escribir_tfvars_origen "$dir" "$R_DESTINO_YA_LISTO"

    if [[ "$R_DESTINO_YA_LISTO" == "true" ]]; then
        # Reejecución: el destino ya estaba listo; todo en una sola pasada.
        asegurar_known_hosts
        terraform_aplicar origen "$dir"
        resumen_origen
        return 0
    fi

    # Fase 1: preparar el origen (paquetes, llave, script, cron...) sin tocar el destino.
    terraform_aplicar origen "$dir"
    local pub="${R_SSH_KEY}.pub"
    [[ -f "$pub" ]] || fail "No existe la llave pública $pub tras aplicar Terraform."
    titulo "Llave pública de este ORIGEN (cópiala EXACTAMENTE, es una sola línea)"
    printf '\n%s%s%s\n\n' "$C_NEG" "$(cat "$pub")" "$C_FIN"
    printf '  Esa línea se pega cuando el instalador la pida en la PC DESTINO.\n\n'

    if confirm DESTINO_LISTO "¿Ya ejecutaste este instalador en la PC DESTINO (opción destino) y terminó sin errores? (s/N)" n; then
        asegurar_known_hosts
        escribir_tfvars_origen "$dir" "true"
        terraform_aplicar origen "$dir"
        resumen_origen
    else
        cat <<EOF

  Perfecto. Pasos que siguen:
    1) En la PC DESTINO ejecuta este mismo instalador, elige "destino" y pega la llave de arriba.
    2) Vuelve a esta PC y ejecuta de nuevo: sudo $0
       (reutiliza esta configuración; responde "s" a "¿destino listo?").
  La fase 1 de este origen ya quedó aplicada y no se repetirá.
EOF
    fi
}

resumen_origen() {
    titulo "ORIGEN listo"
    cat <<EOF

  Terraform dejó configurado:
    - /usr/local/sbin/itsi-backup-run.sh   (script de respaldo)
    - /etc/itsi-backup.conf                (parámetros)
    - /etc/cron.d/itsi-backup              (cada ${R_INTERVALO} minutos)
    - /etc/logrotate.d/itsi-backup         (rotación del log)
    - ${R_SSH_KEY} (+ .pub)                (llave SSH)
  Cómo comprobarlo:
    sudo tail -n 20 /var/log/itsi-backup.log
    (en el DESTINO)  sudo ls -lh ${R_DEST_BASE}/*/
    sudo $0 --estado
EOF
}

#------------------------------ FLUJO: DESTINO ---------------------------------
escribir_tfvars_destino() {
    local dir="$1"
    escribir_si_cambia "$dir/terraform.tfvars" 600 <<EOF
# Generado por instalar_backup_terraform.sh (puedes editarlo; vuelve a ejecutar el instalador).
usuario_backup       = "$R_USUARIO"
carpeta_respaldos    = "$R_CARPETA"
llave_publica_origen = "$R_LLAVE_PUBLICA"
ip_origen            = "$R_ORIGEN_IP"
EOF
}

validar_llave_publica() {
    local k="$1" t
    [[ "$k" =~ $RE_PUBKEY ]] || return 1
    t="$(mktemp)"
    printf '%s\n' "$k" > "$t"
    if ssh-keygen -l -f "$t" >/dev/null 2>&1; then rm -f "$t"; return 0; fi
    rm -f "$t"
    return 1
}

flujo_destino() {
    local dir="$BASE_DIR/destino" tv="$BASE_DIR/destino/terraform.tfvars"
    titulo "Configuración de la PC DESTINO"
    emitir_destino "$dir"

    if [[ -f "$tv" ]] && confirm REUTILIZAR "Ya existe una configuración guardada del DESTINO. ¿Reutilizarla sin volver a preguntar? (S/n)" s; then
        R_USUARIO="$(tfvar_get "$tv" usuario_backup)"
        R_CARPETA="$(tfvar_get "$tv" carpeta_respaldos)"
        R_LLAVE_PUBLICA="$(tfvar_get "$tv" llave_publica_origen)"
        R_ORIGEN_IP="$(tfvar_get "$tv" ip_origen)"
        [[ -n "$R_USUARIO" && -n "$R_CARPETA" && -n "$R_LLAVE_PUBLICA" ]] \
            || fail "El archivo $tv está incompleto o dañado. Bórralo y vuelve a ejecutar para responder las preguntas de nuevo."
        info "Se reutiliza la configuración de $tv"
    else
        local d_user="itsibackup"
        cat <<'TXT'

  Datos de esta PC DESTINO. Entre corchetes está el valor por defecto (Enter = aceptar).
TXT
        ask USUARIO "  Usuario que recibirá los respaldos (no uses 'backup': es una cuenta del sistema)" "$d_user" "$RE_USER" "Minúsculas, números, guion o guion bajo; empieza con letra."
        [[ "$R_USUARIO" != "backup" ]] || fail "'backup' es una cuenta del sistema de Ubuntu (uid 34, sin shell). Usa otro nombre, por ejemplo itsibackup."
        ask CARPETA "  Carpeta donde se guardarán las copias (debe ser la misma que se indique en el origen)" "/home/${R_USUARIO}/respaldos" "$RE_RUTA" "Ruta absoluta sin espacios."
        ask ORIGEN_IP "  IP del ORIGEN para limitar la llave a esa IP (Enter = sin limitar)" "" "$RE_IPORIGEN" "Solo letras, números, punto, dos puntos, barra y guion."
        printf '\n  Pega la llave pública del ORIGEN (UNA línea que empieza con ssh-ed25519):\n'
        ask LLAVE_PUBLICA "  Llave pública" "" "$RE_PUBKEY" "Debe ser una línea: ssh-ed25519 AAAA... comentario"
        validar_llave_publica "$R_LLAVE_PUBLICA" || fail "La llave pública pegada no es válida (ssh-keygen la rechazó). Cópiala completa desde el origen."
    fi
    escribir_tfvars_destino "$dir"
    terraform_aplicar destino "$dir"

    local hf=""
    [[ -f /etc/ssh/ssh_host_ed25519_key.pub ]] && hf="$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')"
    titulo "DESTINO listo"
    cat <<EOF

  Terraform dejó configurado:
    - Usuario '${R_USUARIO}' (sin contraseña; solo entra con la llave del origen)
    - Carpeta ${R_CARPETA} (permiso 700)
    - Llave del origen autorizada con la opción 'restrict'

  Huella SSH (ED25519) de ESTA PC — el origen te pedirá compararla:
      ${hf:-no disponible}

  Ahora vuelve al ORIGEN y ejecuta de nuevo el instalador (responde "s" a "¿destino listo?").
EOF
}

#------------------------ ESTADO / DESINSTALAR / EXTRAER -----------------------
pedir_rol() {
    ask ROL "¿Esta PC es el ORIGEN (tiene los datos y genera los respaldos) o el DESTINO (guarda las copias)? (o/d)" "" '^([oO]|[dD]|[oO]rigen|[dD]estino|origen|destino)$' "Responde o (origen) o d (destino)."
    case "$R_ROL" in
        o|O|origen|Origen) R_ROL="origen" ;;
        *) R_ROL="destino" ;;
    esac
}

accion_estado() {
    requerir_root
    verificar_so
    preparar_log_y_candado
    command -v "$TF_BIN" >/dev/null 2>&1 || fail "$TF_BIN no está instalado; no hay nada que verificar."
    pedir_rol
    local dir="$BASE_DIR/$R_ROL" rc=0
    titulo "Estado de la PC ($R_ROL)"
    [[ -d "$dir" ]] || fail "No existe $dir: este instalador todavía no configuró esta PC como $R_ROL."
    verificar_pasos "$R_ROL" "$dir" reporte || rc=$?
    if (( rc == 0 )); then ok "Todo está como Terraform lo dejó."; else warn "Hay pasos alterados. Ejecuta el instalador para repararlos."; fi
}

accion_desinstalar() {
    requerir_root
    verificar_so
    preparar_log_y_candado
    command -v "$TF_BIN" >/dev/null 2>&1 || fail "$TF_BIN no está instalado; no hay nada que desinstalar."
    pedir_rol
    local dir="$BASE_DIR/$R_ROL"
    if [[ "$R_ROL" == "destino" ]]; then
        warn "El DESTINO no se desinstala automáticamente: el usuario, la carpeta y TODOS los respaldos se conservan a propósito."
        info "Para borrarlos a mano: ver el capítulo de desinstalación del manual."
        return 0
    fi
    [[ -d "$dir" ]] || fail "No existe $dir: no hay nada que desinstalar."
    confirm CONFIRMAR_DESINSTALAR "Se retirarán cron, script, configuración y logrotate del ORIGEN (NO se borran llaves, logs ni respaldos). ¿Continuar? (s/N)" n \
        || { info "Cancelado."; return 0; }
    export TF_IN_AUTOMATION=1 TF_INPUT=0
    tf_cmd "$dir" destroy -input=false -auto-approve -no-color || fail "terraform destroy falló."
    ok "ORIGEN desinstalado. Las llaves SSH, los logs y los respaldos en el destino siguen intactos."
}

accion_extraer() {
    local base="$EXTRAER_DIR"
    install -d -m 755 "$base"
    emitir_origen "$base/origen"
    emitir_destino "$base/destino"
    ok "Archivos Terraform escritos en $base/origen y $base/destino"
    cat <<EOF

  Para hacerlo a mano (camino B del manual):
    cd $base/origen   o   cd $base/destino
    # crea terraform.tfvars con tus valores (ver el manual) y luego:
    terraform init
    terraform validate
    terraform plan
    terraform apply
EOF
}

#---------------------------------- PRINCIPAL ----------------------------------
main() {
    case "$ACCION" in
        extraer) accion_extraer; return 0 ;;
        estado) accion_estado; return 0 ;;
        desinstalar) accion_desinstalar; return 0 ;;
    esac
    titulo "Instalador de respaldos con Terraform v${VERSION_INSTALADOR}"
    requerir_root
    verificar_so
    preparar_log_y_candado
    pedir_rol
    asegurar_terraform
    if [[ "$R_ROL" == "origen" ]]; then flujo_origen; else flujo_destino; fi
    ok "Proceso terminado."
}

main
