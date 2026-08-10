#!/bin/sh
# Batería del RITMO del recordatorio de captura: cada cuánto el hook Stop pide guardar.
#
# El problema que existe para arreglar (medido el 9-ago-2026 sobre esta máquina): el aviso
# salía cada tres mensajes y guardar lo reiniciaba, así que aparecía de nuevo al turno
# siguiente. Resultado real: 8 memorias en una sola conversación, 4 de ellas versiones
# sucesivas de una idea que después se descartó. Una memoria de más no es gratis: le mete
# ruido a la búsqueda de todo el equipo, que es justo lo que el producto vende.
#
# Las dos reglas que se testean acá:
#   1. CHARLAR NO ES TRABAJAR. Tres mensajes sin tocar un archivo no son trabajo sin guardar.
#      Sólo cuenta como conversación pendiente una charla larga (12 turnos) en una sesión que
#      NO guardó nada todavía — si ya guardó, lo que se dijo después está cubierto.
#   2. GUARDAR NO REINICIA EL CICLO. Después de un guardado hay un piso de turnos antes del
#      próximo aviso; si no, el hook felicita el guardado pidiendo otro.
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/.." && pwd)
REPO=$(CDPATH= cd -- "$ROOT/.." && pwd)

# La fuente única es core/ de la raíz cuando esto corre desde el checkout; en el repo público
# el plugin vive solo y su copia vendorizada es lo único que hay.
LIB="$REPO/core/scripts/capture-lib.sh"
[ -r "$LIB" ] || LIB="$ROOT/core/scripts/capture-lib.sh"
. "$LIB"

PASS=0; FAIL=0
check() { # <desc> <esperado> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); printf 'FAIL: %s\n  esperado=[%s]\n  actual  =[%s]\n' "$1" "$2" "$3"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# --- fabricantes de transcript ----------------------------------------------------------------
# Formato de Claude Code, recortado a las líneas que el lector mira. El promptId es lo que
# distingue un TURNO real del usuario de los mensajes derivados (tool_results, adjuntos).
turnos() { # <archivo> <cuántos> [prefijo del promptId]
  _i=1
  while [ "$_i" -le "$2" ]; do
    printf '{"type":"user","message":{"role":"user","content":"mensaje %s"},"promptId":"%s%s"}\n' \
      "$_i" "${3:-p}" "$_i" >> "$1"
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}\n' >> "$1"
    _i=$((_i + 1))
  done
}
guardado() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"brain_save"}]}}\n' >> "$1"; }
ediciones() { # <archivo> <cuántas>
  _i=1
  while [ "$_i" -le "$2" ]; do
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}\n' >> "$1"
    _i=$((_i + 1))
  done
}

# --- 1. El lector: qué cuenta como pendiente ---------------------------------------------------

T="$TMP/guardado-y-charla.jsonl"; guardado "$T"; turnos "$T" 3
check "guardado + 3 mensajes de charla => nada pendiente" "" "$(ob_unsaved_kind "$T")"

T="$TMP/guardado-y-charla-larga.jsonl"; guardado "$T"; turnos "$T" 15
check "guardado + charla larga => nada pendiente (lo de antes ya está guardado)" "" "$(ob_unsaved_kind "$T")"

T="$TMP/charla-corta.jsonl"; turnos "$T" 3
check "3 mensajes sin guardar nada => nada pendiente (charlar no es trabajar)" "" "$(ob_unsaved_kind "$T")"

T="$TMP/charla-larga.jsonl"; turnos "$T" 12
check "12 mensajes sin ningún guardado => conversación pendiente" "conversacion" "$(ob_unsaved_kind "$T")"

T="$TMP/guardado-y-edits.jsonl"; guardado "$T"; ediciones "$T" 3; turnos "$T" 1
check "guardado + 3 ediciones => edits (el trabajo real sigue contando)" "edits" "$(ob_unsaved_kind "$T")"

# --- 2. El hook: cuántas veces avisa -----------------------------------------------------------
avisos=0
correr() { # <session> <transcript> <home>  → suma 1 a $avisos si el hook avisó
  _out=$(printf '{"session_id":"%s","transcript_path":"%s","cwd":"/proj"}' "$1" "$2" \
    | HOME="$3" sh "$ROOT/scripts/stop-guard.sh" 2>/dev/null)
  case "$_out" in *additionalContext*) avisos=$((avisos + 1)) ;; esac
}

# (a) Después de un guardado, tres mensajes de charla no disparan nada.
HOME_A=$(mktemp -d)
T="$TMP/a.jsonl"; guardado "$T"; turnos "$T" 3
avisos=0; correr sesA "$T" "$HOME_A"; correr sesA "$T" "$HOME_A"; correr sesA "$T" "$HOME_A"
check "(a) charla después de guardar => 0 avisos en 3 turnos" 0 "$avisos"

# (b) Después de un guardado, trabajo de verdad sí lo dispara.
HOME_B=$(mktemp -d)
T="$TMP/b.jsonl"; guardado "$T"; ediciones "$T" 3; turnos "$T" 1
avisos=0; correr sesB "$T" "$HOME_B"
check "(b) ediciones después de guardar => avisa" 1 "$avisos"

# (c) Sin guardar nada, el aviso no aparece más de una vez cada 5 turnos.
HOME_C=$(mktemp -d)
T="$TMP/c.jsonl"; ediciones "$T" 3; turnos "$T" 1
avisos=0; _i=1
while [ "$_i" -le 12 ]; do correr sesC "$T" "$HOME_C"; _i=$((_i + 1)); done
check "(c) 12 turnos con trabajo sin guardar => 3 avisos (1, 5 y 10)" 3 "$avisos"

# (d) El corazón del arreglo: guardar NO reinicia el ciclo.
#     Trabajo → aviso → se guarda → vuelve a haber trabajo. Los turnos siguientes tienen que
#     quedarse callados: si el hook vuelve a pedir guardar dos turnos después del guardado,
#     la sesión termina con cinco versiones de la misma idea adentro del cerebro.
HOME_D=$(mktemp -d)
T_EDITS="$TMP/d-edits.jsonl"; ediciones "$T_EDITS" 3; turnos "$T_EDITS" 1
T_SAVED="$TMP/d-saved.jsonl"; ediciones "$T_SAVED" 3; turnos "$T_SAVED" 1; guardado "$T_SAVED"
T_MAS="$TMP/d-mas-edits.jsonl"; cat "$T_SAVED" > "$T_MAS"; ediciones "$T_MAS" 3; turnos "$T_MAS" 1

avisos=0
correr sesD "$T_EDITS" "$HOME_D"                       # turno 1: avisa (primera vez)
check "(d) el primer turno con trabajo avisa" 1 "$avisos"

correr sesD "$T_SAVED" "$HOME_D"                       # turno 2: se guardó, no hay nada pendiente
avisos=0
_i=1; while [ "$_i" -le 3 ]; do correr sesD "$T_MAS" "$HOME_D"; _i=$((_i + 1)); done
check "(d) 3 turnos con trabajo nuevo justo después de guardar => 0 avisos" 0 "$avisos"

_i=1; while [ "$_i" -le 10 ]; do correr sesD "$T_MAS" "$HOME_D"; _i=$((_i + 1)); done
[ "$avisos" -ge 1 ] && vuelve=1 || vuelve=0
check "(d) pasados ~10 turnos más, el aviso vuelve" 1 "$vuelve"

printf '\nstop-guard-ritmo: %d PASS, %d FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
