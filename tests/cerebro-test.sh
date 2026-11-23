#!/bin/sh
# Batería de "a qué cerebro va cada cosa": todo lo que manda el plugin tiene que salir con el
# token del cerebro de la sesión, nunca con el de la máquina por defecto.
#
# Nació de dos cruces reales (23-nov-2026): onebrain-save ignoraba ONE_BRAIN_TOKEN_FILE y
# guardaba en el cerebro por defecto, y Semana subía las horas de TODAS las carpetas con el token
# de la sesión que la disparaba. Un server falso anota el token de cada pedido.
#
# Archivo aparte de run.sh porque necesita un server levantado (mismo patrón que skills-test.sh).
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/.." && pwd)

PASS=0; FAIL=0
assert_eq() { # <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s (esperado=%s actual=%s)\n' "$1" "$2" "$3"; fi
}

# Este test puede correr adentro de una sesión de Claude Code, que exporta su id, su proceso y su
# archivo de entorno: con eso los scripts resolverían la carpeta de ESA sesión y no la del caso.
unset CLAUDE_CODE_SESSION_ID CLAUDE_PID CLAUDE_ENV_FILE OB_CWD ONE_BRAIN_STATE_DIR ONE_BRAIN_TOKEN_FILE ONE_BRAIN_TOKEN

TMP=$(mktemp -d)
MOCK=""
limpiar() { [ -n "$MOCK" ] && kill "$MOCK" 2>/dev/null; rm -rf "$TMP"; }
trap limpiar EXIT INT TERM

# --- server falso: anota "METODO RUTA TOKEN" por pedido, responde {} -------------------------
cat > "$TMP/mock.py" <<'EOF'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
LOG = sys.argv[1]
class H(BaseHTTPRequestHandler):
    def _r(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode("utf8", "replace") if n else ""
        auth = self.headers.get("Authorization", "-").replace("Bearer ", "")
        cerebro = self.headers.get("x-onebrain-cerebro", "-")
        with open(LOG, "a") as f:
            f.write("%s %s %s %s\n" % (self.command, self.path.split("?")[0], auth, cerebro))
        with open(LOG + ".cuerpos", "a") as f:
            f.write("%s %s\n" % (self.path.split("?")[0], body.replace("\n", " ")))
        b = b"{}"
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    do_GET = _r; do_POST = _r
    def log_message(self, *a): pass
s = HTTPServer(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
EOF
LOG="$TMP/pedidos.log"; : > "$LOG"
python3 "$TMP/mock.py" "$LOG" > "$TMP/puerto" 2>/dev/null & MOCK=$!
ESPERA=0
while [ "$ESPERA" -lt 200 ] && [ ! -s "$TMP/puerto" ]; do sleep 0.05; ESPERA=$((ESPERA + 1)); done
PUERTO=$(head -n 1 "$TMP/puerto")
[ -n "$PUERTO" ] || { echo "FAIL: el server falso no arrancó"; exit 1; }
URL="http://127.0.0.1:$PUERTO"
ESPERA=0
while [ "$ESPERA" -lt 200 ]; do curl -s --max-time 1 "$URL/listo" >/dev/null 2>&1 && break; sleep 0.05; ESPERA=$((ESPERA + 1)); done
: > "$LOG"

# --- una Mac de mentira: el cerebro por defecto es "prophet"; la sesión usa "elprofeta" --------
H="$TMP/home"
mkdir -p "$H/.config/one-brain" "$H/.claude"
printf 'ob_prophet_aaaa1111' > "$H/.config/one-brain/token"
OTRO="$TMP/otro-cerebro"; mkdir -p "$OTRO"
printf 'ob_elprofeta_bbbb2222' > "$OTRO/token"

# Tokens que llegaron a <ruta>, uno por línea, sin repetir.
tokens_en() { grep " $1 " "$LOG" | awk '{print $3}' | sort -u | tr '\n' ' ' | sed 's/ $//'; }

# --- 1. onebrain-save con ONE_BRAIN_TOKEN_FILE -----------------------------------------------
HOME="$H" ONE_BRAIN_URL="$URL" ONE_BRAIN_TOKEN_FILE="$OTRO/token" \
  sh "$ROOT/core/bin/onebrain-save" --type aprendizaje --title "t" --content "c" --entities "x" >/dev/null 2>&1
assert_eq "onebrain-save usa ONE_BRAIN_TOKEN_FILE" "ob_elprofeta_bbbb2222" "$(tokens_en /api/entry)"
: > "$LOG"

# --- 2. la cola (ob_try_save) con ONE_BRAIN_TOKEN_FILE ---------------------------------------
HOME="$H" ONE_BRAIN_URL="$URL" ONE_BRAIN_TOKEN_FILE="$OTRO/token" \
  sh -c '. "$1/core/scripts/capture-lib.sh"; ob_try_save "{\"type\":\"aprendizaje\"}"' _ "$ROOT" >/dev/null 2>&1
assert_eq "la cola reintenta con ONE_BRAIN_TOKEN_FILE" "ob_elprofeta_bbbb2222" "$(tokens_en /api/entry)"
: > "$LOG"

# --- 3. onebrain-save con ONE_BRAIN_STATE_DIR (lo que ya andaba, que no se rompa) -----------
HOME="$H" ONE_BRAIN_URL="$URL" ONE_BRAIN_STATE_DIR="$OTRO" \
  sh "$ROOT/core/bin/onebrain-save" --type aprendizaje --title "t" --content "c" --entities "x" >/dev/null 2>&1
assert_eq "onebrain-save usa ONE_BRAIN_STATE_DIR" "ob_elprofeta_bbbb2222" "$(tokens_en /api/entry)"
: > "$LOG"

# --- 4. sin nada: el cerebro por defecto, como siempre -----------------------------------------
HOME="$H" ONE_BRAIN_URL="$URL" \
  sh "$ROOT/core/bin/onebrain-save" --type aprendizaje --title "t" --content "c" --entities "x" >/dev/null 2>&1
assert_eq "sin variables: el cerebro por defecto" "ob_prophet_aaaa1111" "$(tokens_en /api/entry)"
: > "$LOG"

# --- 5. los comandos en Node resuelven el mismo archivo que el shell --------------------------
NODE_TF=$(HOME="$H" ONE_BRAIN_TOKEN_FILE="$OTRO/token" node --input-type=module -e \
  "import('$ROOT/core/scripts/project-lib.mjs').then(m => console.log(m.tokenFile()))" 2>/dev/null)
assert_eq "Node: tokenFile respeta ONE_BRAIN_TOKEN_FILE" "$OTRO/token" "$NODE_TF"
NODE_TF=$(HOME="$H" ONE_BRAIN_STATE_DIR="$OTRO" node --input-type=module -e \
  "import('$ROOT/core/scripts/project-lib.mjs').then(m => console.log(m.tokenFile()))" 2>/dev/null)
assert_eq "Node: tokenFile respeta ONE_BRAIN_STATE_DIR" "$OTRO/token" "$NODE_TF"
NODE_TF=$(HOME="$H" node --input-type=module -e \
  "import('$ROOT/core/scripts/project-lib.mjs').then(m => console.log(m.tokenFile()))" 2>/dev/null)
assert_eq "Node: sin variables, el token de siempre" "$H/.config/one-brain/token" "$NODE_TF"

# --- 6. Semana: sólo sube desde el cerebro por defecto --------------------------------------
# Semana lee TODAS las sesiones de la Mac. Si la sube una sesión de otro cerebro, las horas de
# todas las carpetas terminan ahí. Hasta que cada bloque sepa a qué cerebro pertenece (por
# .onebrain), una sesión de otro cerebro no sube nada.
mkdir -p "$H/.claude/projects/-tmp-x"
printf '%s\n' '{"type":"user","timestamp":"2026-11-23T10:00:00.000Z","sessionId":"s1","cwd":"/tmp/x","message":{"role":"user","content":"hola"}}' \
  '{"type":"assistant","timestamp":"2026-11-23T10:05:00.000Z","sessionId":"s1","cwd":"/tmp/x","message":{"role":"assistant","model":"claude-opus-5-5","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":1,"output_tokens":1}}}' \
  > "$H/.claude/projects/-tmp-x/s1.jsonl"
HOME="$H" ONE_BRAIN_URL="$URL" ONE_BRAIN_SEMANA_DIR="$TMP/semana-otro" ONE_BRAIN_TOKEN_FILE="$OTRO/token" \
  sh "$ROOT/bin/onebrain-semana-push" --ahora >/dev/null 2>&1
assert_eq "Semana no sube desde otro cerebro (ONE_BRAIN_TOKEN_FILE)" "" "$(tokens_en /api/semana/bloques)"
: > "$LOG"
HOME="$H" ONE_BRAIN_URL="$URL" ONE_BRAIN_SEMANA_DIR="$TMP/semana-otro2" ONE_BRAIN_STATE_DIR="$OTRO" \
  sh "$ROOT/bin/onebrain-semana-push" --ahora >/dev/null 2>&1
assert_eq "Semana no sube desde otro cerebro (ONE_BRAIN_STATE_DIR)" "" "$(tokens_en /api/semana/bloques)"
: > "$LOG"
# Control: desde el cerebro por defecto sí sube (si no, los dos de arriba pasarían de vacíos).
HOME="$H" ONE_BRAIN_URL="$URL" ONE_BRAIN_SEMANA_DIR="$TMP/semana-def" \
  sh "$ROOT/bin/onebrain-semana-push" --ahora >/dev/null 2>&1
assert_eq "Semana sube desde el cerebro por defecto" "ob_prophet_aaaa1111" "$(tokens_en /api/semana/bloques)"

# ============ .onebrain: el repo dice a qué cerebro pertenece ===============================
# Los `sh -c` que cargan capture-lib.sh le pasan su ruta como $0: así encuentra state-dir.sh,
# igual que en un hook real. Con `_` caería al respaldo sin .onebrain y el test no probaría nada.
REPO="$TMP/repo-profeta"; mkdir -p "$REPO/sub/hondo"
printf '# del proyecto de ebooks\ncerebro: elprofeta\n' > "$REPO/.onebrain"
CAJON="$H/.config/one-brain/cerebros/elprofeta"
cerebros_en() { grep " $1 " "$LOG" | awk '{print $4}' | sort -u | tr '\n' ' ' | sed 's/ $//'; }

# --- 7. sin la llave de ese cerebro: se cierra, nunca cae al por defecto ---------------------
HDR=$(cd "$REPO/sub/hondo" && HOME="$H" sh "$ROOT/scripts/headers.sh" 2>/dev/null)
assert_eq ".onebrain sin llave: el MCP no manda token" "{}" "$HDR"
HDR=$(cd "$REPO/sub" && HOME="$H" ONE_BRAIN_TOKEN=ob_prophet_aaaa1111 sh "$ROOT/scripts/headers.sh" 2>/dev/null)
assert_eq ".onebrain sin llave: ONE_BRAIN_TOKEN de otro cerebro tampoco" "{}" "$HDR"
assert_eq ".onebrain sin llave: el cajón no hereda el token de la Mac" "no" "$([ -e "$CAJON/token" ] && echo si || echo no)"
(cd "$REPO/sub" && HOME="$H" ONE_BRAIN_URL="$URL" sh "$ROOT/core/bin/onebrain-save" --type aprendizaje --title "t" --content "c" --entities "x" >/dev/null 2>&1)
assert_eq ".onebrain sin llave: onebrain-save no manda nada" "" "$(tokens_en /api/entry)"
assert_eq ".onebrain sin llave: queda en la cola de ESE cerebro" "1" "$(ls "$CAJON/queue" 2>/dev/null | wc -l | tr -d ' ')"
LINEA=$(cd "$REPO" && HOME="$H" sh -c '. "$1/core/scripts/state-dir.sh"; ob_linea_cerebro' _ "$ROOT")
assert_eq ".onebrain sin llave: el arranque avisa" "1" "$(printf '%s' "$LINEA" | grep -c 'no tiene su llave')"
: > "$LOG"

# --- 8. conectar guarda la llave aparte, sin tocar la de por defecto -------------------------
SHA_ANTES=$(shasum "$H/.config/one-brain/token" | awk '{print $1}')
(cd "$REPO" && HOME="$H" sh "$ROOT/core/bin/onebrain-cerebro" conectar ob_elprofeta_bbbb2222 >/dev/null 2>&1)
assert_eq "conectar: la llave por defecto no cambia" "$SHA_ANTES" "$(shasum "$H/.config/one-brain/token" | awk '{print $1}')"
assert_eq "conectar: la llave nueva va a cerebros/elprofeta" "ob_elprofeta_bbbb2222" "$(cat "$CAJON/token" 2>/dev/null)"
# GNU primero: en Linux `stat -f` es el del filesystem y no falla, así que nunca caía al -c.
assert_eq "conectar: permisos 600" "600" "$(stat -c '%a' "$CAJON/token" 2>/dev/null || stat -f '%Lp' "$CAJON/token" 2>/dev/null)"
(cd "$REPO" && HOME="$H" sh "$ROOT/core/bin/onebrain-token" set ob_obel_cccc3333 >/dev/null 2>&1)
assert_eq "token set: en una carpeta de elprofeta no acepta un token de otro cerebro" "ob_elprofeta_bbbb2222" "$(cat "$CAJON/token" 2>/dev/null)"

# --- 9. con la llave: todo sale con elprofeta, desde cualquier subcarpeta ---------------------
HDR=$(cd "$REPO/sub/hondo" && HOME="$H" sh "$ROOT/scripts/headers.sh" 2>/dev/null)
assert_eq ".onebrain: el MCP manda la llave de elprofeta y el cerebro" \
  '{"Authorization":"Bearer ob_elprofeta_bbbb2222","x-onebrain-client":"claude-code","x-onebrain-cerebro":"elprofeta"}' "$HDR"
(cd "$REPO/sub" && HOME="$H" ONE_BRAIN_URL="$URL" sh "$ROOT/core/bin/onebrain-save" --type aprendizaje --title "t" --content "c" --entities "x" >/dev/null 2>&1)
assert_eq ".onebrain: onebrain-save usa la llave de elprofeta" "ob_elprofeta_bbbb2222" "$(tokens_en /api/entry)"
assert_eq ".onebrain: onebrain-save manda el cerebro de la carpeta" "elprofeta" "$(cerebros_en /api/entry)"
: > "$LOG"
(cd "$REPO" && HOME="$H" ONE_BRAIN_URL="$URL" sh -c '. "$1/core/scripts/capture-lib.sh"; ob_flush_queue' "$ROOT/core/scripts/capture-lib.sh" "$ROOT" >/dev/null 2>&1)
assert_eq ".onebrain: la cola de elprofeta sale con su llave" "ob_elprofeta_bbbb2222" "$(tokens_en /api/entry)"
: > "$LOG"
LINEA=$(cd "$REPO/sub" && HOME="$H" sh -c '. "$1/core/scripts/state-dir.sh"; ob_linea_cerebro' _ "$ROOT")
assert_eq ".onebrain: la línea del arranque" "One Brain · Team: elprofeta (por .onebrain)" "$LINEA"
LINEA=$(cd "$TMP" && HOME="$H" sh -c '. "$1/core/scripts/state-dir.sh"; ob_linea_cerebro' _ "$ROOT")
assert_eq "sin .onebrain: la línea de siempre" "One Brain · Team: prophet" "$LINEA"
(cd "$TMP" && HOME="$H" ONE_BRAIN_URL="$URL" sh "$ROOT/core/bin/onebrain-save" --type aprendizaje --title "t" --content "c" --entities "x" >/dev/null 2>&1)
assert_eq "sin .onebrain: el cerebro por defecto, sin header de cerebro" "ob_prophet_aaaa1111 -" "$(tokens_en /api/entry) $(cerebros_en /api/entry)"
: > "$LOG"

# --- 10. .onebrain que nombra el cerebro por defecto: el cajón de siempre ----------------------
REPO2="$TMP/repo-prophet"; mkdir -p "$REPO2"; printf 'cerebro: prophet\n' > "$REPO2/.onebrain"
SD=$(cd "$REPO2" && HOME="$H" sh -c '. "$1/core/scripts/state-dir.sh"; ob_state_dir' _ "$ROOT")
assert_eq ".onebrain del cerebro por defecto: el cajón de siempre" "$H/.config/one-brain" "$SD"

# --- 10b. "team:" es el nombre nuevo; "cerebro:" sigue valiendo -------------------------------
REPO4="$TMP/repo-team"; mkdir -p "$REPO4"; printf 'team: elprofeta\n' > "$REPO4/.onebrain"
LINEA=$(cd "$REPO4" && HOME="$H" sh -c '. "$1/core/scripts/state-dir.sh"; ob_linea_cerebro' _ "$ROOT")
assert_eq ".onebrain con team: la línea del arranque" "One Brain · Team: elprofeta (por .onebrain)" "$LINEA"

# --- 11. el cerebro queda fijo para la sesión (CLAUDE_ENV_FILE) --------------------------------
ENVF="$TMP/env-sesion"; : > "$ENVF"
(cd "$REPO" && HOME="$H" CLAUDE_ENV_FILE="$ENVF" OB_CWD="$REPO/sub" sh -c '. "$1/core/scripts/capture-lib.sh"; . "$1/core/scripts/session-start-lib.sh"; ob_fijar_cerebro_de_sesion' "$ROOT/core/scripts/capture-lib.sh" "$ROOT")
assert_eq "arranque con .onebrain: fija el cajón para Bash" "export ONE_BRAIN_STATE_DIR='$CAJON'" "$(cat "$ENVF")"
: > "$ENVF"
(cd "$TMP" && HOME="$H" CLAUDE_ENV_FILE="$ENVF" OB_CWD="$TMP" sh -c '. "$1/core/scripts/capture-lib.sh"; . "$1/core/scripts/session-start-lib.sh"; ob_fijar_cerebro_de_sesion' "$ROOT/core/scripts/capture-lib.sh" "$ROOT")
assert_eq "arranque sin .onebrain: no fija nada" "" "$(cat "$ENVF")"
(cd "$TMP/otro-cerebro" && HOME="$H" ONE_BRAIN_STATE_DIR="$CAJON" ONE_BRAIN_URL="$URL" sh "$ROOT/core/bin/onebrain-save" --type aprendizaje --title "t" --content "c" --entities "x" >/dev/null 2>&1)
assert_eq "fijado: un cd a otra carpeta sigue guardando en elprofeta" "ob_elprofeta_bbbb2222" "$(tokens_en /api/entry)"
: > "$LOG"

# --- 12. usar escribe .onebrain en la raíz del repo --------------------------------------------
REPO3="$TMP/repo-nuevo"; mkdir -p "$REPO3/a/b"; git -C "$REPO3" init -q
(cd "$REPO3/a/b" && HOME="$H" sh "$ROOT/core/bin/onebrain-cerebro" usar elprofeta >/dev/null 2>&1)
assert_eq "usar: .onebrain en la raíz del repo" "team: elprofeta" "$(cat "$REPO3/.onebrain" 2>/dev/null)"
(cd "$H" && HOME="$H" sh "$ROOT/core/bin/onebrain-cerebro" usar elprofeta >/dev/null 2>&1)
assert_eq "usar: nunca en la carpeta del usuario" "no" "$([ -e "$H/.onebrain" ] && echo si || echo no)"

# --- 13. Semana: cada sesión va al cerebro de su carpeta --------------------------------------
mkdir -p "$H/.claude/projects/-repo-profeta"
sed "s#/tmp/x#$REPO/sub#g; s/\"s1\"/\"s-profeta\"/g" "$H/.claude/projects/-tmp-x/s1.jsonl" > "$H/.claude/projects/-repo-profeta/s-profeta.jsonl"
: > "$LOG"; : > "$LOG.cuerpos"
HOME="$H" ONE_BRAIN_URL="$URL" ONE_BRAIN_SEMANA_DIR="$TMP/semana-13" \
  sh "$ROOT/bin/onebrain-semana-push" --ahora >/dev/null 2>&1
CUERPOS=$(grep '^/api/semana/bloques' "$LOG.cuerpos")
assert_eq "Semana por defecto: sube la sesión sin .onebrain" "1" "$(printf '%s' "$CUERPOS" | grep -c '"s1')"
assert_eq "Semana por defecto: NO sube la sesión de elprofeta" "0" "$(printf '%s' "$CUERPOS" | grep -c 's-profeta')"
: > "$LOG"; : > "$LOG.cuerpos"
(cd "$REPO/sub" && HOME="$H" ONE_BRAIN_URL="$URL" ONE_BRAIN_SEMANA_DIR="$TMP/semana-13" \
  sh "$ROOT/bin/onebrain-semana-push" --ahora >/dev/null 2>&1)
CUERPOS=$(grep '^/api/semana/bloques' "$LOG.cuerpos")
assert_eq "Semana de elprofeta: sube con su llave" "ob_elprofeta_bbbb2222" "$(tokens_en /api/semana/bloques)"
assert_eq "Semana de elprofeta: sube su sesión" "1" "$(printf '%s' "$CUERPOS" | grep -c 's-profeta')"
assert_eq "Semana de elprofeta: NO sube la sesión del por defecto" "0" "$(printf '%s' "$CUERPOS" | grep -c '"s1')"
assert_eq "Semana de elprofeta: cache propio" "si" "$([ -f "$TMP/semana-13/cerebros/elprofeta/cache.json" ] && echo si || echo no)"

# --- 14. el MCP corre en la carpeta del plugin: la carpeta de la sesión sale de otro lado ------
# (a) lo que anotó el arranque para ESTE id de sesión
HOME="$H" sh -c '. "$1/core/scripts/state-dir.sh"; ob_anotar_sesion ses-123 "$2"' _ "$ROOT" "$REPO/sub"
HDR=$(cd "$ROOT" && HOME="$H" CLAUDE_CODE_SESSION_ID=ses-123 sh "$ROOT/scripts/headers.sh" 2>/dev/null)
assert_eq "MCP en la carpeta del plugin: usa la carpeta que anotó el arranque" "1" "$(printf '%s' "$HDR" | grep -c ob_elprofeta_bbbb2222)"
# (b) sin registro: la carpeta del proceso de Claude Code
(cd "$REPO/sub" && exec sleep 30) & DUENO=$!
sleep 0.2
HDR=$(cd "$ROOT" && HOME="$H" CLAUDE_CODE_SESSION_ID=ses-sin-registro CLAUDE_PID=$DUENO sh "$ROOT/scripts/headers.sh" 2>/dev/null)
kill "$DUENO" 2>/dev/null
assert_eq "MCP en la carpeta del plugin: usa la carpeta del proceso de Claude Code" "1" "$(printf '%s' "$HDR" | grep -c ob_elprofeta_bbbb2222)"
# (c) un id de sesión con caracteres raros no se usa como ruta
HOME="$H" sh -c '. "$1/core/scripts/state-dir.sh"; ob_anotar_sesion "../../x" "$2"' _ "$ROOT" "$REPO"
assert_eq "un id de sesión raro no escribe fuera de sesiones/" "no" "$([ -e "$H/.config/x" ] || [ -e "$H/.config/one-brain/x" ] && echo si || echo no)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
