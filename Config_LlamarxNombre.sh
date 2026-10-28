#!/bin/bash

sudo tee /usr/local/bin/rs > /dev/null << 'EOF'
#!/bin/bash
BASE="https://raw.github.com/mesa3-67/Proyecto/main"

if [ -z "$1" ]; then
    echo "Uso: rs script.sh [argumentos]"
    exit 1
fi

SCRIPT="$1"
shift

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

curl -fsSL "$BASE/$SCRIPT" -o "$TMP" || { echo "Error: no se pudo descargar $SCRIPT"; exit 1; }
bash "$TMP" "$@"
EOF

sudo chmod +x /usr/local/bin/rs || true
