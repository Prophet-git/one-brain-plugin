#!/bin/sh
# Tests de scripts/enable-autoupdate.sh
#
# Este script escribe en ~/.claude/settings.json, que es la configuración global de Claude Code
# de otra persona. Un merge mal hecho no le rompe One Brain: le rompe Claude Code entero. Por
# eso los casos de abajo son casi todos "NO tocar", no "sí escribir".
#
# Cada caso corre el script con un HOME falso, así que nunca toca la máquina de quien lo corre.

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPT="$DIR/../scripts/enable-autoupdate.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  ✗ %s\n     %s\n' "$1" "$2"; }

nuevo_home() {
  H=$(mktemp -d)
  mkdir -p "$H/.claude"
  printf '%s' "$H"
}

# Devuelve el valor de autoUpdate del marketplace prophet, o "ausente".
leer_autoupdate() {
  python3 - "$1" <<'PY' 2>/dev/null || printf 'error'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("ilegible"); raise SystemExit
m = (d.get("extraKnownMarketplaces") or {}).get("prophet")
if m is None:
    print("ausente")
else:
    print(str(m.get("autoUpdate")).lower())
PY
}

printf 'Tests de enable-autoupdate\n'

# --- 1. Sin settings.json: lo crea con la entrada ---
H=$(nuevo_home)
HOME="$H" XDG_CONFIG_HOME="$H/.config" sh "$SCRIPT"
R=$(leer_autoupdate "$H/.claude/settings.json")
[ "$R" = "true" ] && ok "sin settings.json, lo crea con autoUpdate:true" \
  || bad "sin settings.json, lo crea con autoUpdate:true" "obtuvo: $R"
rm -rf "$H"

# --- 2. Con settings.json existente: agrega SIN pisar lo que había ---
H=$(nuevo_home)
cat > "$H/.claude/settings.json" <<'JSON'
{
  "theme": "dark",
  "language": "Español",
  "permissions": { "allow": ["Read", "Bash(git *)"] }
}
JSON
HOME="$H" XDG_CONFIG_HOME="$H/.config" sh "$SCRIPT"
R=$(leer_autoupdate "$H/.claude/settings.json")
CONSERVA=$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
print("si" if d.get("theme")=="dark" and d.get("language")=="Español" and d["permissions"]["allow"]==["Read","Bash(git *)"] else "no")
' "$H/.claude/settings.json" 2>/dev/null)
[ "$R" = "true" ] && ok "agrega la entrada al settings existente" || bad "agrega la entrada al settings existente" "obtuvo: $R"
[ "$CONSERVA" = "si" ] && ok "no pisa el resto de la configuración" || bad "no pisa el resto de la configuración" "obtuvo: $CONSERVA"
[ -f "$H/.claude/settings.json.bak-onebrain" ] && ok "deja una copia del original" || bad "deja una copia del original" "no hay .bak-onebrain"
rm -rf "$H"

# --- 3. Ya existe la entrada con autoUpdate:false → se RESPETA ---
# Alguien que lo apagó a propósito no puede encontrárselo prendido en la próxima sesión.
H=$(nuevo_home)
cat > "$H/.claude/settings.json" <<'JSON'
{
  "extraKnownMarketplaces": {
    "prophet": {
      "source": { "source": "github", "repo": "Prophet-git/one-brain-plugin" },
      "autoUpdate": false
    }
  }
}
JSON
HOME="$H" XDG_CONFIG_HOME="$H/.config" sh "$SCRIPT"
R=$(leer_autoupdate "$H/.claude/settings.json")
[ "$R" = "false" ] && ok "respeta un autoUpdate:false puesto a mano" || bad "respeta un autoUpdate:false puesto a mano" "obtuvo: $R"
rm -rf "$H"

# --- 4. settings.json ROTO: no lo toca ---
H=$(nuevo_home)
printf '{ esto no es json valido ,,,' > "$H/.claude/settings.json"
ANTES=$(cat "$H/.claude/settings.json")
HOME="$H" XDG_CONFIG_HOME="$H/.config" sh "$SCRIPT"
DESPUES=$(cat "$H/.claude/settings.json")
[ "$ANTES" = "$DESPUES" ] && ok "un settings.json roto queda intacto (no lo empeora)" \
  || bad "un settings.json roto queda intacto" "el archivo cambió"
rm -rf "$H"

# --- 5. La marca corta: no vuelve a tocar nada ---
H=$(nuevo_home)
mkdir -p "$H/.config/one-brain"
: > "$H/.config/one-brain/autoupdate-configurado"
HOME="$H" XDG_CONFIG_HOME="$H/.config" sh "$SCRIPT"
[ ! -f "$H/.claude/settings.json" ] && ok "con la marca puesta no hace nada" \
  || bad "con la marca puesta no hace nada" "creó el settings igual"
rm -rf "$H"

# --- 6. Corrida dos veces: no duplica ni rompe ---
H=$(nuevo_home)
HOME="$H" XDG_CONFIG_HOME="$H/.config" sh "$SCRIPT"
HOME="$H" XDG_CONFIG_HOME="$H/.config" sh "$SCRIPT"
R=$(leer_autoupdate "$H/.claude/settings.json")
[ "$R" = "true" ] && ok "correrlo dos veces deja el mismo resultado" || bad "correrlo dos veces deja el mismo resultado" "obtuvo: $R"
rm -rf "$H"

# --- 7. Sin python ni jq: no toca el archivo ---
# Preferimos no actualizar solos antes que arruinarle la configuración a alguien.
H=$(nuevo_home)
cat > "$H/.claude/settings.json" <<'JSON'
{ "theme": "dark" }
JSON
PELADO=$(mktemp -d)
for b in sh mkdir rm cp mv command; do
  S=$(command -v "$b" 2>/dev/null); [ -n "$S" ] && ln -sf "$S" "$PELADO/$b" 2>/dev/null
done
ANTES=$(cat "$H/.claude/settings.json")
HOME="$H" XDG_CONFIG_HOME="$H/.config" PATH="$PELADO" sh "$SCRIPT" 2>/dev/null
DESPUES=$(cat "$H/.claude/settings.json")
[ "$ANTES" = "$DESPUES" ] && ok "sin python ni jq no toca el archivo" || bad "sin python ni jq no toca el archivo" "el archivo cambió"
rm -rf "$H" "$PELADO"

# --- 8. Sale rápido y en silencio (es un hook de arranque) ---
H=$(nuevo_home)
SALIDA=$(HOME="$H" XDG_CONFIG_HOME="$H/.config" sh "$SCRIPT" 2>&1)
[ -z "$SALIDA" ] && ok "no imprime nada" || bad "no imprime nada" "imprimió: $SALIDA"
HOME="$H" XDG_CONFIG_HOME="$H/.config" sh "$SCRIPT"; CODIGO=$?
[ "$CODIGO" -eq 0 ] && ok "siempre sale con código 0" || bad "siempre sale con código 0" "salió $CODIGO"
rm -rf "$H"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
