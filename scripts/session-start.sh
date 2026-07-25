#!/bin/sh
# SessionStart: (1) brief del equipo, (2) síntesis pendiente, (3) fallback: si la
# sesión anterior quedó con trabajo sin guardar, ofrecer capturarlo ahora.
# Silencioso ante cualquier fallo (nunca bloquea el arranque).
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -r "$DIR/capture-lib.sh" ] || exit 0
. "$DIR/capture-lib.sh"
# Reintentar guardados que quedaron en cola (offline previo). BACKGROUNDEADO A PROPÓSITO:
# el propio bloque de abajo ya backgroundea sus curls (context/synthesis/etc.) para acotar el
# arranque a ~8s (la MÁS lenta, no la suma; ver comentario más abajo) — si el flush corriera
# acá de forma sincrónica, sumaría hasta 20×8s ANTES de que ese bloque siquiera arranque. El
# subshell "( ... & )" lanza el flush y sigue de largo sin esperarlo (fire-and-forget): el
# arranque nunca queda bloqueado por la cola, sin importar cuán lenta/caída esté la red.
( ob_flush_queue >/dev/null 2>&1 & )

INPUT=$(cat 2>/dev/null)
SESSION=$(ob_json_field session_id "$INPUT")
# Self-test del parser (Capa 3): ¿el hook puede leer el input en ESTE entorno? Se reporta al
# server (header x-hook-ok) para que el operador lo vea en el panel, y si falla se avisa fuerte
# en el contexto de arranque. Nunca en silencio.
HOOK_OK=$(ob_selftest)

# feat_on <slug>: 0 (on) si el feature no está explícitamente en false, o si no
# hay features.json cacheado (default ON). Misma lógica que plugin/bin/onebrain-feature.
# Se define ACÁ ARRIBA a propósito: dos de las llamadas de abajo tienen EFECTO en el server
# (/api/synthesis reclama el candado atómico del día, /api/mentions marca resoluciones como
# vistas). Antes se llamaban siempre y el resultado se descartaba después, así que alguien con
# la síntesis apagada le bloqueaba el día a todo su equipo por 6 horas en cada arranque, y
# perdía avisos de menciones en silencio. Lee el cache del arranque anterior, que es
# exactamente lo que corresponde para decidir si vale la pena llamar.
feat_on() {
  FFILE="$HOME/.config/one-brain/features.json"
  [ -r "$FFILE" ] || return 0
  ! grep -qE "\"$1\"[[:space:]]*:[[:space:]]*false" "$FFILE" 2>/dev/null
}

TOKEN_FILE="$HOME/.config/one-brain/token"
URL="${ONE_BRAIN_URL:-https://one-brain-kappa.vercel.app}"
BRIEF=""; SYN=""; HELLO=""; RESUME=""; MENTIONS=""; SAVEBIN=""; TOKENWARN=""; HAS_TOKEN=0
if [ -r "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
  HAS_TOKEN=1
  TOKEN=$(tr -d ' \t\r\n' < "$TOKEN_FILE")
  # Recordatorio del canal de guardado a prueba de "deferred": SOLO en instalaciones YA
  # onboardeadas (con token). Sin token, onebrain-save encola en silencio para siempre (nunca
  # guarda de verdad) — mostrar este mensaje ahí sería engañoso, así que va adentro del gate.
  SAVEBIN="Para guardar en One Brain usá el comando: $DIR/../bin/onebrain-save (canal Bash, no depende de la tool MCP)."
  # Versión instalada del plugin (del manifest). Se reporta piggyback en la llamada de contexto
  # (x-plugin-version) para que el panel avise SOLO si estás atrasado — Fase 2 del aviso de update.
  PLUGIN_VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DIR/../.claude-plugin/plugin.json" 2>/dev/null | head -n1)
  GREETED_MARKER="$HOME/.config/one-brain/greeted"
  DO_HELLO=0; [ ! -e "$GREETED_MARKER" ] && DO_HELLO=1

  # Las 5-6 llamadas de arranque son INDEPENDIENTES entre sí → se disparan en PARALELO (curl en
  # background a archivos temporales) y se espera a todas juntas con `wait`. Antes eran secuenciales
  # (hasta 6×8s de espera acumulada en el peor caso); ahora el arranque tarda lo que la MÁS lenta
  # (~8s tope), no la suma. Silencioso ante fallo, igual que antes.
  OB_TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/ob-start-$$")
  mkdir -p "$OB_TMP" 2>/dev/null

  # -w '\n%{http_code}': el body y el http status quedan en el mismo archivo (código al final),
  # así detectamos un token vencido/inválido (401/403) sin una llamada extra. Se separan abajo,
  # DESPUÉS del wait — ver Task 8 (fail-loud de token vencido).
  curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" -H "x-plugin-version: $PLUGIN_VERSION" -H "x-hook-ok: $HOOK_OK" -w '\n%{http_code}' "$URL/api/context"   > "$OB_TMP/context.raw"   2>/dev/null &
  # ?peek=1: sólo pregunta si hay día sin sintetizar. Sin peek, este GET TOMA el candado del
  # día y se trae ~24 KB de material — se hacía en cada arranque, casi nunca se usaba, y ese
  # peso era lo que hacía que Claude Code truncara todo el contexto de arranque.
  feat_on daily-synthesis && curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/synthesis?peek=1" > "$OB_TMP/synthesis" 2>/dev/null &
  # Continuidad: el handoff más reciente del PROPIO usuario (≤3 días), para retomar donde quedó.
  curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/resume"    > "$OB_TMP/resume"    2>/dev/null &
  # Menciones pendientes que te dejó un compañero (string ya formateado, o "" si no hay).
  # También tiene efecto: marca las resoluciones como vistas. Mismo criterio que arriba.
  feat_on menciones && curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/mentions"  > "$OB_TMP/mentions"  2>/dev/null &
  # Features del usuario (toggles). Silencioso ante fallo → se conserva el features.json anterior.
  curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/features"  > "$OB_TMP/features"  2>/dev/null &
  # First-run "el cerebro habla primero" (#21): SOLO la primera vez que este usuario conecta.
  [ "$DO_HELLO" = 1 ] && curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/hello" > "$OB_TMP/hello" 2>/dev/null &

  wait  # esperar a que TODAS las llamadas en background terminen antes de parsear

  # Separar body/http_code de /api/context ANTES de parsear nada (Task 8). El orden importa:
  # $OB_TMP/context tiene que quedar como el BODY puro para que ob_json_field (Task 9) lo lea bien.
  CTX_CODE=$(tail -n1 "$OB_TMP/context.raw" 2>/dev/null)
  sed '$d' "$OB_TMP/context.raw" > "$OB_TMP/context" 2>/dev/null
  TOKENWARN=$(ob_token_warning "$CTX_CODE")

  # Parser ESTRUCTURAL (ob_json_field), no sed: el sed line-oriented anterior rompía con
  # pretty-print o comillas escapadas adentro del valor (mismo bug de fondo que ob_json_field
  # ya resuelve para el input del hook). ob_json_field recibe un STRING, no un archivo.
  BRIEF=$(ob_json_field brief "$(cat "$OB_TMP/context" 2>/dev/null)")
  # De la síntesis sólo viene el día pendiente. El material se pide recién cuando la persona
  # dice que sí — con la orden concreta que va en el aviso de abajo.
  SYN_DAY=$(ob_json_field period_key "$(cat "$OB_TMP/synthesis" 2>/dev/null)")
  [ -n "$SYN_DAY" ] && SYN="One Brain: el día $SYN_DAY quedó sin sintetizar. Si el usuario quiere que la hagas, traé el material con: curl -s -H \"Authorization: Bearer \$(cat ~/.config/one-brain/token)\" $URL/api/synthesis"
  RESUME=$(ob_json_field resume "$(cat "$OB_TMP/resume" 2>/dev/null)")
  MENTIONS=$(ob_json_field mentions "$(cat "$OB_TMP/mentions" 2>/dev/null)")

  # First-run: parsear el saludo y apagar el marker para siempre (exista o no la respuesta).
  if [ "$DO_HELLO" = 1 ]; then
    HELLO=$(sed -n 's/.*"hello":"\(.*\)"}/\1/p' "$OB_TMP/hello" 2>/dev/null)
    mkdir -p "$HOME/.config/one-brain" 2>/dev/null
    printf '' > "$GREETED_MARKER" 2>/dev/null
  fi

  # Cachear features solo si la respuesta trae el objeto (si no responde, se conserva el anterior).
  FEATURES=$(cat "$OB_TMP/features" 2>/dev/null)
  case "$FEATURES" in
    *'"features"'*)
      mkdir -p "$HOME/.config/one-brain" 2>/dev/null
      printf '%s' "$FEATURES" \
        | sed -n 's/.*"features":[[:space:]]*\({.*}\)}/\1/p' \
        > "$HOME/.config/one-brain/features.json" ;;
  esac

  rm -rf "$OB_TMP" 2>/dev/null
fi

# Segundo gate, ahora sobre el contenido: el de arriba evitó la llamada, éste evita mostrarlo
# (cubre el caso de que el features.json haya cambiado en esta misma corrida).
feat_on team-digest || BRIEF=""
feat_on daily-synthesis || SYN=""
feat_on session-resume || RESUME=""
feat_on menciones || MENTIONS=""

# Aviso de reuniones sin sincronizar (feature 'reuniones', máx 1×/día). No llama a API/MCP:
# solo invita a activar la skill. Idempotente por día vía marker en el pending-dir.
# SOLO con token (instalación onboardeada) — sin token el plugin no está conectado y no debe
# emitir NADA (mismo criterio que SAVEBIN); antes disparaba igual porque feat_on da default ON
# sin features.json, y esta llamada no dependía del gate de token como el resto del bloque.
REUNMSG=""
if [ "$HAS_TOKEN" = "1" ] && feat_on reuniones; then
  RDAY=$(date +%Y%m%d 2>/dev/null)
  RMARK="$(ob_pending_dir)/reuniones-reminded-$RDAY"
  if [ -n "$RDAY" ] && [ ! -e "$RMARK" ]; then
    mkdir -p "$(ob_pending_dir)" 2>/dev/null
    printf '' > "$RMARK" 2>/dev/null
    REUNMSG="Puede que tengas reuniones nuevas de Granola sin sincronizar al cerebro. Si querés, activá la skill reuniones: trae las nuevas, las guarda y te ofrece destilar decisiones/avances."
  fi
fi

# Fallback de captura: marker pending-* de una sesión DISTINTA de la actual, INACTIVA
# (ob_is_stale). NO borra la marca al avisar — antes sí lo hacía y, si el modelo no actuaba
# ese único aviso, el trabajo se perdía para siempre. Ahora la marca se borra SOLO cuando
# session-capture confirma el guardado (ob_resolve_pending), y este aviso INSISTE en cada
# arranque hasta que eso pase.
PENDMSG=$(ob_pending_message "$SESSION")

# Aviso de captura degradada (Capa 3): si el self-test falló, la captura automática NO va a
# funcionar en este entorno. Se avisa arriba de todo, es lo más urgente.
HOOKWARN=""
if [ "$HOOK_OK" != "1" ]; then
  HOOKWARN="⚠️ One Brain: la captura automática NO está operativa en este entorno — el hook no puede parsear el input de Claude Code (instalá jq o python3, o actualizá el plugin one-brain). Mientras tanto, tus avances NO se guardan solos: guardá manualmente con brain_save. Mostrale este aviso al usuario."
fi

# --- Ensamblado -------------------------------------------------------------------------
#
# Dos reglas, las dos aprendidas a los golpes (medido sobre 24 sesiones reales: sólo el 29%
# recibía el contexto entero):
#
# 1) SALIDA EN TEXTO PLANO. Antes esto se emitía como JSON armado con printf, y el brief trae
#    comillas y saltos de línea REALES (ob_json_field los decodifica): el JSON quedaba
#    inválido y Claude Code lo descartaba, o peor, mostraba el andamiaje crudo en pantalla.
#    Para SessionStart, lo que el hook escribe en stdout se agrega al contexto tal cual. Sin
#    escapado no hay nada que romper.
#
# 2) PRESUPUESTO. Si el bloque pasa de ~9 KB, Claude Code lo reemplaza por un preview de 2 KB
#    y un puntero a un archivo que nadie lee — o sea, el contexto del equipo desaparece sin
#    que nadie se entere. Cada bloque grande tiene su tope y el total tiene un techo. Los
#    avisos cortos (token vencido, captura rota, trabajo sin guardar) nunca se recortan:
#    son justamente los que no pueden perderse.
OB_MAX_TOTAL=8000
NL='
'
CONTEXT=""
ob_append() { [ -n "$1" ] || return 0; if [ -n "$CONTEXT" ]; then CONTEXT="$CONTEXT$NL$NL$1"; else CONTEXT="$1"; fi; }
ob_append_clipped() { # <texto> <max_chars>
  [ -n "$1" ] || return 0
  ob_append "$(printf '%s' "$1" | ob_clip "$2")"
}

ob_append "$TOKENWARN"                 # token vencido: sin esto nada funciona
ob_append "$HOOKWARN"                  # captura rota en este entorno
ob_append_clipped "$RESUME" 2500       # dónde quedaste
ob_append_clipped "$MENTIONS" 800      # lo que te dejó un compañero
ob_append_clipped "$HELLO" 1200        # bienvenida (sólo la primera vez)
[ -n "$BRIEF" ] && ob_append_clipped "# One Brain — contexto del equipo$NL$BRIEF" 3500
ob_append "$SYN"                       # una línea: hay día sin sintetizar
ob_append "$PENDMSG"                   # quedó trabajo sin guardar
ob_append "$REUNMSG"
ob_append "$SAVEBIN"
[ -n "$CONTEXT" ] || exit 0

# Techo final, por si la suma de los topes se pasa igual (varios bloques grandes a la vez).
printf '%s\n' "$CONTEXT" | ob_clip "$OB_MAX_TOTAL"
printf '\n'
exit 0
