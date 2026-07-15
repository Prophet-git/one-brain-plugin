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
BRIEF=""; SYN=""; HELLO=""; RESUME=""
if [ -r "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
  TOKEN=$(tr -d ' \t\r\n' < "$TOKEN_FILE")
  BRIEF=$(curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/context" \
    | sed -n 's/.*"brief":"\(.*\)"}/\1/p')
  SYN=$(curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/synthesis" \
    | sed -n 's/.*"prompt":"\(.*\)"}/\1/p')

  # Continuidad: el handoff más reciente del PROPIO usuario (≤3 días). Que retome donde
  # quedó en vez de arrancar de cero. `resume` es null (→ vacío) si no hay ninguno reciente.
  RESUME=$(curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/resume" \
    | sed -n 's/.*"resume":"\(.*\)"}/\1/p')

  # First-run "el cerebro habla primero" (#21): SOLO la primera vez que este usuario
  # conecta (sin marker greeted) pedimos /api/hello y lo inyectamos. El marker apaga
  # esto para siempre después de la 1ra corrida, exista o no la respuesta (silencioso
  # ante fallo, igual que el resto del hook).
  GREETED_MARKER="$HOME/.config/one-brain/greeted"
  if [ ! -e "$GREETED_MARKER" ]; then
    HELLO=$(curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/hello" \
      | sed -n 's/.*"hello":"\(.*\)"}/\1/p')
    mkdir -p "$HOME/.config/one-brain" 2>/dev/null
    printf '' > "$GREETED_MARKER" 2>/dev/null
  fi

  # Features del usuario (toggles). Silencioso ante fallo: si /api/features no
  # responde (timeout, error, red caída) se conserva el features.json anterior
  # (o su ausencia = todo ON, ver feat_on).
  FEATURES=$(curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/features")
  case "$FEATURES" in
    *'"features"'*)
      mkdir -p "$HOME/.config/one-brain" 2>/dev/null
      printf '%s' "$FEATURES" \
        | sed -n 's/.*"features":[[:space:]]*\({.*}\)}/\1/p' \
        > "$HOME/.config/one-brain/features.json" ;;
  esac
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
ob_append "$HELLO"
[ -n "$BRIEF" ] && ob_append "# One Brain — contexto del equipo\\n$BRIEF"
ob_append "$SYN"
ob_append "$PENDMSG"
ob_append "$REUNMSG"
[ -n "$CONTEXT" ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$CONTEXT"
exit 0
