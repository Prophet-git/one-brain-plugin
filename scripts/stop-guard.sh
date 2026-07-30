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
TRANSCRIPT=$(ob_json_field transcript_path "$INPUT")
SESSION=$(ob_json_field session_id "$INPUT")
CWD=$(ob_json_field cwd "$INPUT")

# FAIL-LOUD: si LLEGÓ input pero no pudimos sacar session/transcript, la captura automática
# está ROTA (cambio de formato de Claude Code, o falta jq/python3/perl en el entorno). NO salir
# en silencio — así fue como un cambio de formato tumbó la red de seguridad sin que nadie se
# enterara. Avisamos visible (1×/día para no spamear) para que el usuario/operador lo note.
if [ -n "$INPUT" ] && { [ -z "$SESSION" ] || [ -z "$TRANSCRIPT" ]; }; then
  PDIR=$(ob_pending_dir); mkdir -p "$PDIR" 2>/dev/null
  DAY=$(date +%Y%m%d 2>/dev/null)
  WARN="$PDIR/degraded-$DAY"
  if [ -n "$DAY" ] && [ ! -e "$WARN" ]; then
    printf '' > "$WARN" 2>/dev/null
    printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"⚠️ One Brain: la captura automática NO está funcionando — no pude leer el input del hook (posible cambio de formato de Claude Code, o falta jq/python3/perl en este entorno). Tus avances NO se están registrando solos. Decíselo al usuario de forma visible AHORA y guardá manualmente con brain_save al cerrar; avisale al operador de One Brain para que lo arregle."}}'
  fi
  exit 0
fi
[ -r "$TRANSCRIPT" ] || exit 0
[ -n "$SESSION" ] || exit 0

PDIR=$(ob_pending_dir)
PEND="$PDIR/pending-$SESSION"
# KIND ("edits" | "conversacion" | ""): el motivo queda ANOTADO en el marker. El aviso de
# arranque lo necesita para no gritar por una sesión que guardó y después siguió charlando.
KIND=$(ob_unsaved_kind "$TRANSCRIPT")
[ -n "$KIND" ] && UNSAVED=1 || UNSAVED=0

CNT_FILE="$PDIR/unsaved-count-$SESSION"
mkdir -p "$PDIR" 2>/dev/null
if [ "$UNSAVED" = "1" ]; then
  # marker con lo que el fallback necesita para destilar la sesión anterior
  { printf 'transcript=%s\n' "$TRANSCRIPT"; printf 'cwd=%s\n' "$CWD"; printf 'reason=%s\n' "$KIND"; } > "$PEND"
else
  # se guardó (o no hay trabajo): se reinicia el ciclo de recordatorio para la próxima vez.
  rm -f "$PEND" "$PDIR/reminded-$SESSION" "$CNT_FILE" 2>/dev/null
  exit 0
fi

# Recordatorio: la primera vez por sesión (marker reminded-), y de ahí en más REINSISTE cada 5
# turnos con trabajo sin guardar (ob_should_renag) — un aviso único al arrancar se pierde de
# vista en sesiones largas y el trabajo queda sin registrar más tiempo del necesario.
MARK="$PDIR/reminded-$SESSION"
CNT=$(cat "$CNT_FILE" 2>/dev/null); [ -n "$CNT" ] || CNT=0
CNT=$((CNT + 1))
printf '%s' "$CNT" > "$CNT_FILE" 2>/dev/null

REMIND=0
if [ ! -e "$MARK" ]; then
  printf '' > "$MARK" 2>/dev/null
  REMIND=1
elif [ "$(ob_should_renag "$CNT")" = "1" ]; then
  REMIND=1
fi
[ "$REMIND" = "1" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"Hay trabajo en esta sesión sin registrar en One Brain. Al cerrar (o si decís algo tipo \\"listo/gracias\\"): (1) guardá los avances/decisiones con la skill session-capture (destilá, proponé, guardá con brain_save); (2) si quedó trabajo a medio hacer, dejá un handoff con la skill handoff para retomarlo en la próxima sesión."}}'
exit 0
