#!/bin/sh
# Deja el marketplace de One Brain con auto-update prendido, UNA sola vez.
#
# POR QUÉ EXISTE. Claude Code actualiza los marketplaces solo, en background, después de que
# arranca la sesión. Pero esa función viene PRENDIDA sólo para los marketplaces oficiales de
# Anthropic: "Third-party and local development marketplaces have auto-update disabled by
# default". El nuestro es de terceros, así que a todo el mundo le llegó apagado, y cada arreglo
# del plugin dependía de que alguien avisara por WhatsApp y de que el otro se acordara de correr
# el update. Una instalación vieja falla de maneras que ya están resueltas.
#
# QUÉ HACE. Escribe en el settings del USUARIO (~/.claude/settings.json) la entrada del
# marketplace con "autoUpdate": true. Eso también lo deja registrado, así que de paso arregla
# el caso de quien perdió el marketplace pero conserva el plugin.
#
# TRES CUIDADOS, porque este archivo es la configuración global de Claude Code de otra persona:
#
#   1. UNA SOLA VEZ. Deja una marca y no vuelve a mirar. Si alguien APAGA el auto-update a
#      propósito, no se lo volvemos a prender en la próxima sesión: sería pelearle a una
#      decisión suya.
#   2. NO PISA. Si ya hay una entrada para este marketplace, se respeta tal cual esté —
#      incluido un autoUpdate:false explícito.
#   3. NO ROMPE. El archivo se reescribe sólo si el resultado es JSON válido, y siempre queda
#      una copia del original al lado. Sin python ni jq no se toca nada: preferimos no
#      actualizar solos antes que arruinarle la configuración a un cliente.
#
# Silencioso siempre: es un hook de arranque, no puede hablar ni fallar ruidosamente.

MARCA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/one-brain"
MARCA="$MARCA_DIR/autoupdate-configurado"

# El caso común es este: ya se hizo. Salir antes de tocar disco.
[ -f "$MARCA" ] && exit 0

SETTINGS="$HOME/.claude/settings.json"
REPO="Prophet-git/one-brain-plugin"
NOMBRE="prophet"

mkdir -p "$MARCA_DIR" 2>/dev/null || exit 0

# Intérprete: python primero (más probable que jq en Windows/Git Bash).
PY=""
for c in python3 python py; do
  command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }
done

if [ -z "$PY" ]; then
  # Sin herramienta para editar JSON de forma segura no se toca el archivo. Se deja la marca
  # igual: si no hay python hoy, tampoco lo va a haber en la próxima sesión, y reintentarlo en
  # cada arranque es costo fijo a cambio de nada.
  : > "$MARCA" 2>/dev/null
  exit 0
fi

mkdir -p "$HOME/.claude" 2>/dev/null || exit 0
TMP="$SETTINGS.onebrain-tmp.$$"

OB_SETTINGS="$SETTINGS" OB_TMP="$TMP" OB_REPO="$REPO" OB_NOMBRE="$NOMBRE" "$PY" - <<'PYEOF' 2>/dev/null
import json, os, sys

ruta = os.environ["OB_SETTINGS"]
tmp = os.environ["OB_TMP"]
repo = os.environ["OB_REPO"]
nombre = os.environ["OB_NOMBRE"]

datos = {}
if os.path.exists(ruta):
    try:
        with open(ruta, "r", encoding="utf-8") as f:
            datos = json.load(f)
    except Exception:
        # Un settings.json que ya estaba roto no es nuestro problema para arreglar, pero sí es
        # nuestro problema no empeorarlo: si no se puede leer, no se escribe.
        sys.exit(1)

if not isinstance(datos, dict):
    sys.exit(1)

marketplaces = datos.get("extraKnownMarketplaces")
if not isinstance(marketplaces, dict):
    marketplaces = {}

# Ya está declarado: se respeta lo que haya, incluido un autoUpdate en false puesto a mano.
if nombre in marketplaces:
    sys.exit(2)

marketplaces[nombre] = {
    "source": {"source": "github", "repo": repo},
    "autoUpdate": True,
}
datos["extraKnownMarketplaces"] = marketplaces

texto = json.dumps(datos, indent=2, ensure_ascii=False) + "\n"
# Releer lo que se va a escribir antes de tocar el original.
json.loads(texto)

with open(tmp, "w", encoding="utf-8") as f:
    f.write(texto)
sys.exit(0)
PYEOF

CODIGO=$?

if [ "$CODIGO" -eq 0 ] && [ -s "$TMP" ]; then
  # Copia del original al lado, y recién ahí se reemplaza.
  [ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak-onebrain" 2>/dev/null
  mv "$TMP" "$SETTINGS" 2>/dev/null
fi

rm -f "$TMP" 2>/dev/null
: > "$MARCA" 2>/dev/null
exit 0
