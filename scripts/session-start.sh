#!/bin/sh
# SessionStart: (1) brief del equipo, (2) síntesis pendiente, (3) fallback: si la
# sesión anterior quedó con trabajo sin guardar, ofrecer capturarlo ahora.
# Silencioso ante cualquier fallo (nunca bloquea el arranque).
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -r "$DIR/capture-lib.sh" ] || exit 0
. "$DIR/capture-lib.sh"

INPUT=$(cat 2>/dev/null)
SESSION=$(printf '%s' "$INPUT" | sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p')

TOKEN_FILE="$HOME/.config/one-brain/token"
URL="${ONE_BRAIN_URL:-https://one-brain-kappa.vercel.app}"
BRIEF=""; SYN=""; HELLO=""; RESUME=""; MENTIONS=""
if [ -r "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
  TOKEN=$(tr -d ' \t\r\n' < "$TOKEN_FILE")
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

  curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" -H "x-plugin-version: $PLUGIN_VERSION" "$URL/api/context"   > "$OB_TMP/context"   2>/dev/null &
  curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/synthesis" > "$OB_TMP/synthesis" 2>/dev/null &
  # Continuidad: el handoff más reciente del PROPIO usuario (≤3 días), para retomar donde quedó.
  curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/resume"    > "$OB_TMP/resume"    2>/dev/null &
  # Menciones pendientes que te dejó un compañero (string ya formateado, o "" si no hay).
  curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/mentions"  > "$OB_TMP/mentions"  2>/dev/null &
  # Features del usuario (toggles). Silencioso ante fallo → se conserva el features.json anterior.
  curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/features"  > "$OB_TMP/features"  2>/dev/null &
  # First-run "el cerebro habla primero" (#21): SOLO la primera vez que este usuario conecta.
  [ "$DO_HELLO" = 1 ] && curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/hello" > "$OB_TMP/hello" 2>/dev/null &

  wait  # esperar a que TODAS las llamadas en background terminen antes de parsear

  BRIEF=$(sed -n 's/.*"brief":"\(.*\)"}/\1/p' "$OB_TMP/context" 2>/dev/null)
  SYN=$(sed -n 's/.*"prompt":"\(.*\)"}/\1/p' "$OB_TMP/synthesis" 2>/dev/null)
  RESUME=$(sed -n 's/.*"resume":"\(.*\)"}/\1/p' "$OB_TMP/resume" 2>/dev/null)
  MENTIONS=$(sed -n 's/.*"mentions":"\(.*\)"}/\1/p' "$OB_TMP/mentions" 2>/dev/null)

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

# feat_on <slug>: 0 (on) si el feature no está explícitamente en false, o si no
# hay features.json cacheado (default ON). Misma lógica que plugin/bin/onebrain-feature.
feat_on() {
  FFILE="$HOME/.config/one-brain/features.json"
  [ -r "$FFILE" ] || return 0
  ! grep -qE "\"$1\"[[:space:]]*:[[:space:]]*false" "$FFILE" 2>/dev/null
}
feat_on team-digest || BRIEF=""
feat_on daily-synthesis || SYN=""
feat_on session-resume || RESUME=""
feat_on menciones || MENTIONS=""

# Aviso de reuniones sin sincronizar (feature 'reuniones', máx 1×/día). No llama a API/MCP:
# solo invita a activar la skill. Idempotente por día vía marker en el pending-dir.
REUNMSG=""
if feat_on reuniones; then
  RDAY=$(date +%Y%m%d 2>/dev/null)
  RMARK="$(ob_pending_dir)/reuniones-reminded-$RDAY"
  if [ -n "$RDAY" ] && [ ! -e "$RMARK" ]; then
    mkdir -p "$(ob_pending_dir)" 2>/dev/null
    printf '' > "$RMARK" 2>/dev/null
    REUNMSG="Puede que tengas reuniones nuevas de Granola sin sincronizar al cerebro. Si querés, activá la skill reuniones: trae las nuevas, las guarda y te ofrece destilar decisiones/avances."
  fi
fi

# Fallback de captura: marker pending-* de una sesión DISTINTA de la actual.
PDIR=$(ob_pending_dir)
PENDMSG=""
for f in "$PDIR"/pending-*; do
  [ -e "$f" ] || continue
  base=$(basename "$f")
  [ "$base" = "pending-$SESSION" ] && continue
  tp=$(sed -n 's/^transcript=//p' "$f" | head -n1)
  PENDMSG="La sesión anterior quedó con trabajo sin guardar en One Brain (transcript: $tp). Si querés, activá la skill session-capture: destilá ese transcript, proponémelo y guardalo. Para no re-avisar, este aviso se muestra una sola vez."
  rm -f "$f" 2>/dev/null
  break
done

# Ensamblado. El RESUME (retomá donde quedaste) va PRIMERO: es lo más accionable al
# abrir. Luego bienvenida first-run, contexto del equipo, síntesis y avisos.
CONTEXT=""
ob_append() { [ -n "$1" ] || return 0; if [ -n "$CONTEXT" ]; then CONTEXT="$CONTEXT\\n\\n$1"; else CONTEXT="$1"; fi; }
ob_append "$RESUME"
ob_append "$MENTIONS"
ob_append "$HELLO"
[ -n "$BRIEF" ] && ob_append "# One Brain — contexto del equipo\\n$BRIEF"
ob_append "$SYN"
ob_append "$PENDMSG"
ob_append "$REUNMSG"
[ -n "$CONTEXT" ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$CONTEXT"
exit 0
