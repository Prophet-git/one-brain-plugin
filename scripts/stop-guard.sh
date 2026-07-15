#!/bin/sh
# Stop hook (corre cada turno): estado de captura + recordatorio suave.
# - Mantiene el marker pending-<session> si hay trabajo posterior al último brain_save.
# - Recuerda UNA vez por sesión que la captura se va a ofrecer al cerrar.
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Gate por feature: si el usuario desactivó "Captura automática" (auto-capture:false
# explícito en features.json), salir sin marcar nada. Si el bin no existe o no es
# ejecutable (instalación rota), NO desactivamos la captura por default — solo
# salimos cuando el helper responde exit 1 explícito.
FEATURE_BIN="$DIR/../bin/onebrain-feature"
if [ -x "$FEATURE_BIN" ]; then
  "$FEATURE_BIN" auto-capture
  [ "$?" -eq 1 ] && exit 0
fi

[ -r "$DIR/capture-lib.sh" ] || exit 0
. "$DIR/capture-lib.sh"

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | sed -n 's/.*"transcript_path":"\([^"]*\)".*/\1/p')
SESSION=$(printf '%s' "$INPUT" | sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p')
CWD=$(printf '%s' "$INPUT" | sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p')
[ -r "$TRANSCRIPT" ] || exit 0
[ -n "$SESSION" ] || exit 0

PDIR=$(ob_pending_dir)
PEND="$PDIR/pending-$SESSION"
UNSAVED=$(ob_has_unsaved_work "$TRANSCRIPT")

mkdir -p "$PDIR" 2>/dev/null
if [ "$UNSAVED" = "1" ]; then
  # marker con lo que el fallback necesita para destilar la sesión anterior
  { printf 'transcript=%s\n' "$TRANSCRIPT"; printf 'cwd=%s\n' "$CWD"; } > "$PEND"
else
  rm -f "$PEND" 2>/dev/null
  exit 0
fi

# recordatorio suave, una vez por sesión
MARK="$PDIR/reminded-$SESSION"
[ -e "$MARK" ] && exit 0
printf '' > "$MARK" 2>/dev/null
printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"Hay trabajo en esta sesión sin registrar en One Brain. Cuando cierres (o si decís algo tipo \\"listo/gracias\\"), activá la skill session-capture: destilá el avance, proponémelo y guardalo con brain_save."}}'
exit 0
