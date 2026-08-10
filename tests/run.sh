#!/bin/sh
# Runner de tests del plugin. No usa dependencias externas.
# Uso: sh plugin/tests/run.sh
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/.." && pwd)
# Raíz del repo fuente. Solo existe cuando esto corre desde el checkout de one-brain: en el
# repo público el plugin vive en la raíz, así que REPO apunta afuera y no tiene ni core/ ni
# tests/. El assert de sincronía de abajo usa eso para saber dónde está corriendo.
REPO=$(CDPATH= cd -- "$ROOT/.." && pwd)
FIX="$DIR/fixtures"
. "$ROOT/core/scripts/capture-lib.sh"

PASS=0; FAIL=0
assert_eq() { # <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s (esperado=%s actual=%s)\n' "$1" "$2" "$3"; fi
}

# --- ob_has_unsaved_work ---
assert_eq "work-no-save => 1"     1 "$(ob_has_unsaved_work "$FIX/work-no-save.jsonl")"
assert_eq "saved => 0"            0 "$(ob_has_unsaved_work "$FIX/saved.jsonl")"
assert_eq "no-work => 0"          0 "$(ob_has_unsaved_work "$FIX/no-work.jsonl")"
assert_eq "work-after-save => 1"  1 "$(ob_has_unsaved_work "$FIX/work-after-save.jsonl")"
assert_eq "missing file => 0"     0 "$(ob_has_unsaved_work "$FIX/does-not-exist.jsonl")"
# El umbral de charla subió de 3 turnos a 12 (9-ago-2026): con 3, el hook pedía guardar cada
# tres mensajes y la sesión terminaba con cinco versiones de una idea sin cerrar adentro del
# cerebro. Charlar no es trabajar; una charla LARGA sin ningún guardado, sí vale rescatarla.
assert_eq "charla de 3 turnos => 0 (charlar no es trabajar)" 0 "$(ob_has_unsaved_work "$FIX/conversational.jsonl")"
assert_eq "charla larga sin ningún guardado => 1" 1 "$(ob_has_unsaved_work "$FIX/conversational-larga.jsonl")"

# --- BUGS de review (formato REAL de transcript, no sintético) ---
# Bug 1: cada tool_result se loguea como type:user+role:user (mismo shape que un mensaje humano
# genuino). Sin excluirlos, cualquier sesión con >=3 tool calls da falso positivo.
assert_eq "solo tool_results (1 humano genuino, 0 edits) => 0" 0 "$(ob_has_unsaved_work "$FIX/tool-results-only.jsonl")"
# Bug 2: el guardado real por el canal Bash (bin/onebrain-save) debe resetear igual que brain_save.
assert_eq "guardado via bin/onebrain-save (Bash) => 0" 0 "$(ob_has_unsaved_work "$FIX/saved-via-bin.jsonl")"
# Bug 2 (inverso): una MENCIÓN de /api/entry (ej. leyendo capture-lib.sh, o en el content de un
# tool_result) NO es un guardado real y NO debe resetear el contador de trabajo.
assert_eq "mención de /api/entry sin guardado real => 1" 1 "$(ob_has_unsaved_work "$FIX/mention-api-entry.jsonl")"
# Bug 3: el reset por "Bash + onebrain-save" disparaba con CUALQUIER mención (ej. `cat
# .../bin/onebrain-save` al leer el archivo), no solo con el uso real (que siempre lleva flags,
# ej. `onebrain-save --type ...`). Se ancla a "onebrain-save --" (requiere un flag).
assert_eq "Bash 'cat .../onebrain-save' (sin flags) NO resetea => 1" 1 "$(ob_has_unsaved_work "$FIX/mention-onebrain-save-no-flags.jsonl")"
assert_eq "Bash 'onebrain-save --type ...' (uso real) SÍ resetea => 0" 0 "$(ob_has_unsaved_work "$FIX/saved-via-bin.jsonl")"

# --- ob_token_warning: fail-loud si el token venció/es inválido ---
# El grep va contra "reconectá" CON TILDE, que es como lo dice el aviso real. Estos dos asserts
# estuvieron en rojo buscando "reconecta" sin tilde: el mensaje se corrigió ortográficamente y
# los tests quedaron atrás, así que fallaban por la á aunque el aviso saliera perfecto.
assert_eq "401 => aviso de reconexión" "reconectá" "$(ob_token_warning 401 | grep -o reconectá | head -n1)"
assert_eq "403 => aviso de reconexión" "reconectá" "$(ob_token_warning 403 | grep -o reconectá | head -n1)"
assert_eq "200 => sin aviso" "" "$(ob_token_warning 200)"

# --- ob_json_field: parseo robusto del input del hook (regresión del bug pretty-print) ---
JF_COMPACT='{"session_id":"s1","transcript_path":"/c/t.jsonl","cwd":"/proj"}'
assert_eq "compacto: transcript_path" "/c/t.jsonl" "$(ob_json_field transcript_path "$JF_COMPACT")"
assert_eq "compacto: session_id"      "s1"         "$(ob_json_field session_id "$JF_COMPACT")"
# pretty-printed (espacios tras los ":", multilínea) + campo gigante last_assistant_message
# que CONTIENE un "transcript_path" falso: un parser line-oriented sacaría vacío o el falso.
JF_PRETTY='{
  "session_id": "sess-9",
  "transcript_path": "/real/t.jsonl",
  "cwd": "/proj",
  "last_assistant_message": "texto con \"transcript_path\": \"/FAKE\" adentro"
}'
assert_eq "pretty: transcript_path REAL (no el falso)" "/real/t.jsonl" "$(ob_json_field transcript_path "$JF_PRETTY")"
assert_eq "pretty: session_id"                          "sess-9"       "$(ob_json_field session_id "$JF_PRETTY")"
assert_eq "campo ausente => vacío"                      ""             "$(ob_json_field noexiste "$JF_COMPACT")"
assert_eq "self-test del parser pasa en este entorno"   1              "$(ob_selftest)"

# Contrato robusto que session-start.sh ahora usa (Task 9) para parsear brief/synthesis/
# resume/mentions del server: un valor con comillas adentro no corta el parseo a mitad de
# camino (el sed anterior sí lo hacía).
RESP='{
  "resume": "retomá donde quedaste con \"comillas\" adentro"
}'
assert_eq "resume con comillas se parsea entero" 'retomá donde quedaste con "comillas" adentro' "$(ob_json_field resume "$RESP")"

# --- ob_should_renag: el recordatorio reinsiste cada 5 turnos con trabajo sin guardar ---
assert_eq "reinsiste al 5º turno" 1 "$(ob_should_renag 5)"
assert_eq "no reinsiste al 3º" 0 "$(ob_should_renag 3)"
assert_eq "no reinsiste al 0" 0 "$(ob_should_renag 0)"

# --- ob_pending_dir: carpeta ESTABLE (no /tmp / no CLAUDE_PLUGIN_DATA) ---
# subshell vía command substitution: aísla el HOME fake sin ensuciar el $HOME del runner.
assert_eq "pending-dir estable en config" "/home/tester/.config/one-brain/pending" \
  "$(unset CLAUDE_PLUGIN_DATA; HOME=/home/tester; ob_pending_dir)"

# --- ob_is_stale: guard de concurrencia (solo rescatar sesiones inactivas) ---
export HOME="$(mktemp -d)"; T="$HOME/t.jsonl"; : > "$T"
assert_eq "recién tocado => NO stale (ret 1)" 1 "$(ob_is_stale "$T"; echo $?)"
OLD="$HOME/old.jsonl"; : > "$OLD"; touch -t 202001010000 "$OLD"
assert_eq "mtime viejo => stale (ret 0)" 0 "$(ob_is_stale "$OLD"; echo $?)"

# --- ob_pending_message / ob_resolve_pending: el rescate NO borra la marca hasta guardar ---
export HOME="$(mktemp -d)"; PD=$(ob_pending_dir); mkdir -p "$PD"
TRABC="$HOME/abc.jsonl"; : > "$TRABC"; touch -t 202001010000 "$TRABC"
printf 'transcript=%s\ncwd=/x\nreason=edits\n' "$TRABC" > "$PD/pending-SESSABC"
ob_pending_message "SESS-ACTUAL" >/dev/null
assert_eq "el aviso NO borra la marca" 1 "$([ -e "$PD/pending-SESSABC" ] && echo 1 || echo 0)"
ob_resolve_pending "SESSABC"
assert_eq "resolve borra la marca" 0 "$([ -e "$PD/pending-SESSABC" ] && echo 1 || echo 0)"

# --- ob_resolve_pending: limpia TODO el cruft de markers de la sesión (no solo pending-), evita
# huérfanos reminded-/unsaved-count- de sesiones ya cerradas ---
printf '' > "$PD/pending-SESSCRUFT"
printf '' > "$PD/reminded-SESSCRUFT"
printf '3' > "$PD/unsaved-count-SESSCRUFT"
ob_resolve_pending "SESSCRUFT"
assert_eq "resolve borra pending-<id>" 0 "$([ -e "$PD/pending-SESSCRUFT" ] && echo 1 || echo 0)"
assert_eq "resolve borra reminded-<id> (cruft)" 0 "$([ -e "$PD/reminded-SESSCRUFT" ] && echo 1 || echo 0)"
assert_eq "resolve borra unsaved-count-<id> (cruft)" 0 "$([ -e "$PD/unsaved-count-SESSCRUFT" ] && echo 1 || echo 0)"

# --- onebrain-resolve-pending: el bin equivalente que usa la skill session-capture ---
RESB="$ROOT/core/bin/onebrain-resolve-pending"
[ -x "$RESB" ]; assert_eq "onebrain-resolve-pending existe y es ejecutable" 0 "$?"
export HOME="$(mktemp -d)"; PD2=$(ob_pending_dir); mkdir -p "$PD2"
printf 'transcript=/x/t.jsonl\n' > "$PD2/pending-SESSXYZ"
env HOME="$HOME" "$RESB" SESSXYZ
assert_eq "onebrain-resolve-pending borra la marca" 0 "$([ -e "$PD2/pending-SESSXYZ" ] && echo 1 || echo 0)"

# --- ob_unsaved_kind: QUÉ quedó sin guardar, no sólo si quedó algo -------------------------
# El aviso imperativo de arranque ("antes de seguir con lo que te pida el usuario") sólo se
# justifica con trabajo REAL sin guardar. Una sesión que guardó y después siguió conversando
# no perdió nada, y gritarle igual convierte el aviso en ruido de fondo permanente.
#
# Y hay un tercer estado, "cola": uno o dos edits DESPUÉS de haber guardado. Nadie guarda como
# último acto de la sesión — se guarda y después se hace el commit, se toca un archivo, se
# cierra. Contar eso como "trabajo sin guardar" es lo que hacía gritar al arranque incluso
# después de un handoff bien hecho. Medido sobre los 9 transcripts reales de esta máquina, la
# separación es nítida: las colas de cierre traen 0-1 edits post-guardado; las sesiones con
# trabajo genuinamente sin registrar traen 13, 21, 32, 34, 40 y 43. El umbral (3) cae en ese
# hueco con margen para dos edits de cierre.
assert_eq "kind: trabajo sustancial sin guardar => edits" "edits"       "$(ob_unsaved_kind "$FIX/work-substantial-after-save.jsonl")"
assert_eq "kind: 2 edits sin guardar => cola"            "cola"         "$(ob_unsaved_kind "$FIX/work-no-save.jsonl")"
assert_eq "kind: 1 edit después de guardar => cola"      "cola"         "$(ob_unsaved_kind "$FIX/work-after-save.jsonl")"
assert_eq "kind: charla larga sin guardar => conversacion" "conversacion" "$(ob_unsaved_kind "$FIX/conversational-larga.jsonl")"
assert_eq "kind: charla corta => vacío"                  ""             "$(ob_unsaved_kind "$FIX/conversational.jsonl")"
assert_eq "kind: todo guardado => vacío"                 ""             "$(ob_unsaved_kind "$FIX/saved.jsonl")"
assert_eq "kind: sin trabajo => vacío"                   ""             "$(ob_unsaved_kind "$FIX/no-work.jsonl")"
assert_eq "kind: transcript inexistente => vacío"        ""             "$(ob_unsaved_kind "$FIX/does-not-exist.jsonl")"
# ob_has_unsaved_work queda como wrapper: mismo contrato de siempre para el recordatorio suave.
assert_eq "has_unsaved_work sigue siendo 1 con charla larga" 1 "$(ob_has_unsaved_work "$FIX/conversational-larga.jsonl")"

# --- ob_gc_pending: ningún marker vive para siempre ----------------------------------------
# Sin esto, cerrar Claude Code deja el marker huérfano PARA SIEMPRE: nada lo borra cuando la
# sesión ya murió (el Stop hook necesita la sesión viva; ob_resolve_pending, que alguien lo
# corra a mano). Se acumulaban ~3/día y el arranque siempre encontraba uno.
export HOME="$(mktemp -d)"; PDG=$(ob_pending_dir); mkdir -p "$PDG"
: > "$PDG/pending-VIEJO";  touch -t 202001010000 "$PDG/pending-VIEJO"
: > "$PDG/reminded-VIEJO"; touch -t 202001010000 "$PDG/reminded-VIEJO"
: > "$PDG/reuniones-reminded-20200101"; touch -t 202001010000 "$PDG/reuniones-reminded-20200101"
: > "$PDG/pending-RECIENTE"
ob_gc_pending
assert_eq "gc: borra el pending vencido"        0 "$([ -e "$PDG/pending-VIEJO" ] && echo 1 || echo 0)"
assert_eq "gc: borra el cruft vencido"          0 "$([ -e "$PDG/reminded-VIEJO" ] && echo 1 || echo 0)"
assert_eq "gc: borra markers de reuniones viejos" 0 "$([ -e "$PDG/reuniones-reminded-20200101" ] && echo 1 || echo 0)"
assert_eq "gc: NO toca el marker reciente"      1 "$([ -e "$PDG/pending-RECIENTE" ] && echo 1 || echo 0)"
assert_eq "gc: sin carpeta no explota"          0 "$(HOME=/no/existe; ob_gc_pending; echo $?)"

# --- ob_pending_message: el aviso deja de insistir ------------------------------------------
# "Se repite en cada arranque hasta que se guarde" convierte un aviso urgente en ruido de
# fondo, que es exactamente cómo se pierde. Tres arranques y se descarta, avisando que es la
# última vez — no desaparece en silencio.
export HOME="$(mktemp -d)"; PDN=$(ob_pending_dir); mkdir -p "$PDN"
TRN="$HOME/nag.jsonl"; : > "$TRN"; touch -t 202001010000 "$TRN"
printf 'transcript=%s\ncwd=/proj\nreason=edits\n' "$TRN" > "$PDN/pending-KNAG"
assert_eq "nag 1: avisa"              1 "$(ob_pending_message ACTUAL | grep -c 'SIN GUARDAR')"
assert_eq "nag 2: sigue avisando"     1 "$(ob_pending_message ACTUAL | grep -c 'SIN GUARDAR')"
assert_eq "nag 3: avisa por última vez" 1 "$(ob_pending_message ACTUAL | grep -c 'última vez')"
assert_eq "nag 4: ya no avisa"        0 "$(ob_pending_message ACTUAL | grep -c 'SIN GUARDAR')"
assert_eq "nag: y el marker quedó descartado" 0 "$([ -e "$PDN/pending-KNAG" ] && echo 1 || echo 0)"

# --- stop-guard.sh: markers pending ---
# NOTA: ob_pending_dir ya NO depende de CLAUDE_PLUGIN_DATA (ver arriba) — vive en
# $HOME/.config/one-brain/pending. Estos tests aíslan con HOME temporal (no CLAUDE_PLUGIN_DATA).
pend_path() { printf '%s/.config/one-brain/pending/pending-%s' "$1" "$2"; } # <home> <session>

run_stop() { # <fixture> <session_id> ; usa un HOME temporal aislado
  TMP=$(mktemp -d)
  printf '{"transcript_path":"%s","session_id":"%s","cwd":"/tmp/proj"}' "$1" "$2" \
    | HOME="$TMP" sh "$ROOT/scripts/stop-guard.sh" >/dev/null 2>&1
  printf '%s' "$TMP"
}
T=$(run_stop "$FIX/work-no-save.jsonl" "s1")
[ -e "$(pend_path "$T" s1)" ]; assert_eq "work-no-save crea pending" 0 "$?"
T=$(run_stop "$FIX/saved.jsonl" "s2")
[ -e "$(pend_path "$T" s2)" ]; assert_eq "saved NO crea pending" 1 "$?"
T=$(run_stop "$FIX/work-after-save.jsonl" "s3")
[ -e "$(pend_path "$T" s3)" ]; assert_eq "work-after-save crea pending" 0 "$?"
# pending se limpia cuando una corrida posterior ya está guardada:
TMP=$(mktemp -d)
printf '{"transcript_path":"%s","session_id":"s4","cwd":"/tmp/proj"}' "$FIX/work-no-save.jsonl" | HOME="$TMP" sh "$ROOT/scripts/stop-guard.sh" >/dev/null 2>&1
printf '{"transcript_path":"%s","session_id":"s4","cwd":"/tmp/proj"}' "$FIX/saved.jsonl"        | HOME="$TMP" sh "$ROOT/scripts/stop-guard.sh" >/dev/null 2>&1
[ -e "$(pend_path "$TMP" s4)" ]; assert_eq "pending se limpia tras guardar" 1 "$?"

# El marker guarda el MOTIVO: sin eso, el arranque no puede distinguir "perdí trabajo" de
# "seguí conversando después de guardar", que es lo que hacía gritar el aviso siempre.
T=$(run_stop "$FIX/work-substantial-after-save.jsonl" "s5")
assert_eq "marker de edits anota reason=edits" "edits" \
  "$(sed -n 's/^reason=//p' "$(pend_path "$T" s5)" 2>/dev/null)"
T=$(run_stop "$FIX/work-no-save.jsonl" "s7")
assert_eq "marker de cola de cierre anota reason=cola" "cola" \
  "$(sed -n 's/^reason=//p' "$(pend_path "$T" s7)" 2>/dev/null)"
# El recordatorio SUAVE de fin de turno sigue disparando con cualquiera de los tres: es barato
# y estar dentro de la sesión es el mejor momento para guardar. El que se vuelve selectivo es
# el grito de arranque.
[ -e "$(pend_path "$T" s7)" ]; assert_eq "cola igual crea marker (el recordatorio suave sigue)" 0 "$?"

# reason=cola NO justifica el aviso imperativo del arranque.
export HOME="$(mktemp -d)"; PDC=$(ob_pending_dir); mkdir -p "$PDC"
TRC="$HOME/cola.jsonl"; : > "$TRC"; touch -t 202001010000 "$TRC"
printf 'transcript=%s\ncwd=/proj\nreason=cola\n' "$TRC" > "$PDC/pending-KCOLA"
assert_eq "reason=cola NO avisa al arrancar" 0 "$(ob_pending_message ACTUAL | grep -c 'SIN GUARDAR')"
assert_eq "y el marker de cola se limpia" 0 "$([ -e "$PDC/pending-KCOLA" ] && echo 1 || echo 0)"
T=$(run_stop "$FIX/conversational-larga.jsonl" "s6")
assert_eq "marker de sólo-charla anota reason=conversacion" "conversacion" \
  "$(sed -n 's/^reason=//p' "$(pend_path "$T" s6)" 2>/dev/null)"

# --- ob_pending_message: el grito de arranque SÓLO por trabajo real ------------------------
export HOME="$(mktemp -d)"; PDK=$(ob_pending_dir); mkdir -p "$PDK"
TRK="$HOME/viejo.jsonl"; : > "$TRK"; touch -t 202001010000 "$TRK"
printf 'transcript=%s\ncwd=/proj\nreason=edits\n' "$TRK" > "$PDK/pending-KEDITS"
assert_eq "reason=edits SÍ avisa" 1 \
  "$(ob_pending_message ACTUAL | grep -c 'SIN GUARDAR')"
rm -f "$PDK/pending-KEDITS"
printf 'transcript=%s\ncwd=/proj\nreason=conversacion\n' "$TRK" > "$PDK/pending-KCONV"
assert_eq "reason=conversacion NO avisa" 0 \
  "$(ob_pending_message ACTUAL | grep -c 'SIN GUARDAR')"
assert_eq "y el marker de sólo-charla se limpia solo" 0 \
  "$([ -e "$PDK/pending-KCONV" ] && echo 1 || echo 0)"
# Markers del formato viejo (sin reason): los escribió la versión con el bug, con el criterio
# que medimos 89% falso positivo. Se descartan en vez de propagarse.
printf 'transcript=%s\ncwd=/proj\n' "$TRK" > "$PDK/pending-KLEGACY"
assert_eq "marker sin reason (formato viejo) NO avisa" 0 \
  "$(ob_pending_message ACTUAL | grep -c 'SIN GUARDAR')"
assert_eq "y el marker viejo se descarta" 0 \
  "$([ -e "$PDK/pending-KLEGACY" ] && echo 1 || echo 0)"

# --- ob_pending_message: transcript que ya no existe ---------------------------------------
# ob_is_stale trata "no existe" como inactivo, así que un transcript borrado por retención
# seguía gritando — y mandaba a destilar un archivo que no está. No hay nada que rescatar.
printf 'transcript=%s/fantasma.jsonl\ncwd=/proj\nreason=edits\n' "$HOME" > "$PDK/pending-KGHOST"
assert_eq "transcript inexistente NO avisa" 0 \
  "$(ob_pending_message ACTUAL | grep -c 'SIN GUARDAR')"
assert_eq "y el marker huérfano se limpia" 0 \
  "$([ -e "$PDK/pending-KGHOST" ] && echo 1 || echo 0)"

# --- ob_should_renag wireado en stop-guard.sh: reinsiste cada 5 turnos con trabajo sin guardar ---
run_stop_turn() { # <home> ; corre stop-guard.sh una vez sobre la misma sesión, con trabajo sin guardar
  printf '{"transcript_path":"%s","session_id":"s-renag","cwd":"/tmp/proj"}' "$FIX/work-no-save.jsonl" \
    | HOME="$1" sh "$ROOT/scripts/stop-guard.sh" 2>/dev/null
}
TMPR=$(mktemp -d)
OUT1=$(run_stop_turn "$TMPR")
printf '%s' "$OUT1" | grep -q 'Hay trabajo en esta sesión'; assert_eq "renag: turno 1 avisa (primera vez)" 0 "$?"
OUT2=$(run_stop_turn "$TMPR")
printf '%s' "$OUT2" | grep -q 'Hay trabajo en esta sesión'; assert_eq "renag: turno 2 NO avisa" 1 "$?"
OUT3=$(run_stop_turn "$TMPR")
printf '%s' "$OUT3" | grep -q 'Hay trabajo en esta sesión'; assert_eq "renag: turno 3 NO avisa" 1 "$?"
OUT4=$(run_stop_turn "$TMPR")
printf '%s' "$OUT4" | grep -q 'Hay trabajo en esta sesión'; assert_eq "renag: turno 4 NO avisa" 1 "$?"
OUT5=$(run_stop_turn "$TMPR")
printf '%s' "$OUT5" | grep -q 'Hay trabajo en esta sesión'; assert_eq "renag: turno 5 REINSISTE" 0 "$?"
# Guardar NO reinicia el ciclo: hay un piso de turnos antes del próximo aviso. Antes se borraban
# el contador y el marker de "ya avisé", así que el turno siguiente al guardado volvía a pedir —
# el hook felicitaba el guardado pidiendo otro, y de ahí salían las versiones intermedias que
# ensucian la búsqueda de todo el equipo. Ver plugin/tests/stop-guard-ritmo-test.sh.
printf '{"transcript_path":"%s","session_id":"s-renag","cwd":"/tmp/proj"}' "$FIX/saved.jsonl" \
  | HOME="$TMPR" sh "$ROOT/scripts/stop-guard.sh" >/dev/null 2>&1
OUT6=$(run_stop_turn "$TMPR")
printf '%s' "$OUT6" | grep -q 'Hay trabajo en esta sesión'; assert_eq "renag: tras guardar NO vuelve a pedir enseguida" 1 "$?"

# --- REGRESIÓN del bug: input pretty-printed + campos falsos en last_assistant_message ---
run_stop_pretty() { # <fixture> <session_id> ; input pretty-printed con un "transcript_path"/"session_id" FALSO adentro
  TMP=$(mktemp -d)
  printf '{\n  "session_id": "%s",\n  "transcript_path": "%s",\n  "cwd": "/tmp/proj",\n  "last_assistant_message": "ojo con \\"transcript_path\\": \\"/FAKE\\" y \\"session_id\\": \\"FAKE\\" en el texto"\n}\n' "$2" "$1" \
    | HOME="$TMP" sh "$ROOT/scripts/stop-guard.sh" >/dev/null 2>&1
  printf '%s' "$TMP"
}
T=$(run_stop_pretty "$FIX/work-no-save.jsonl" "sp1")
[ -e "$(pend_path "$T" sp1)" ];   assert_eq "pretty-print: crea pending con el session REAL" 0 "$?"
[ -e "$(pend_path "$T" FAKE)" ];  assert_eq "pretty-print: NO usa el session_id falso"       1 "$?"

# --- FAIL-LOUD: input presente pero SIN session/transcript => aviso + marker degraded ---
TMP=$(mktemp -d)
OUTFL=$(printf '{"algo":"otra cosa","sin_session":true}' | HOME="$TMP" sh "$ROOT/scripts/stop-guard.sh" 2>/dev/null)
printf '%s' "$OUTFL" | grep -q 'NO está funcionando'; assert_eq "fail-loud: grita si no puede parsear" 0 "$?"
ls "$TMP/.config/one-brain/pending"/degraded-* >/dev/null 2>&1; assert_eq "fail-loud: deja marker degraded" 0 "$?"
# input VACÍO (no llegó nada) NO debe gritar: es un caso normal, no una falla
TMP=$(mktemp -d)
OUTEMPTY=$(printf '' | HOME="$TMP" sh "$ROOT/scripts/stop-guard.sh" 2>/dev/null)
printf '%s' "$OUTEMPTY" | grep -q 'NO está funcionando'; assert_eq "input vacío no gatilla fail-loud" 1 "$?"

# --- skill session-capture ---
SK="$ROOT/skills/session-capture/SKILL.md"
[ -f "$SK" ]; assert_eq "skill existe" 0 "$?"
grep -q '^description:' "$SK" 2>/dev/null; assert_eq "skill tiene description" 0 "$?"
grep -q 'brain_save' "$SK" 2>/dev/null; assert_eq "skill referencia brain_save" 0 "$?"
grep -q 'onebrain-save' "$SK" 2>/dev/null; assert_eq "skill referencia onebrain-save (canal a prueba de deferred)" 0 "$?"
grep -q 'onebrain-resolve-pending' "$SK" 2>/dev/null; assert_eq "skill referencia onebrain-resolve-pending" 0 "$?"
grep -qE '\.jsonl' "$SK" 2>/dev/null; assert_eq "skill aclara cómo sacar el session-id del transcript (aviso solo trae la ruta)" 0 "$?"
# La skill decía "onebrain-save no expone supersedes, usá la tool MCP": mientras eso siga
# escrito, el flag nuevo no existe para el modelo (y la tool MCP suele estar deferred, que es
# justamente por lo que existe el bin). Una instrucción desactualizada pesa más que el binario.
grep -q 'no los expone' "$SK" 2>/dev/null; assert_eq "session-capture ya NO dice que el bin no expone supersedes" 1 "$?"
grep -q -- '--supersedes' "$SK" 2>/dev/null; assert_eq "session-capture enseña --supersedes en el bin" 0 "$?"
# Drift con A-5 (tanda 0) y con el dead-letter: la skill enseñaba que CUALQUIER fallo del bin
# deja la memoria "encolada, pendiente, no perdida". Desde que un 4xx ya no se encola eso es
# falso justo en el caso que necesita acción inmediata — y el modelo, siguiendo la doc, le
# informa al usuario que su memoria está a salvo cuando en realidad se descartó.
grep -q 'rechazó la memoria' "$SK" 2>/dev/null
assert_eq "session-capture distingue el rechazo del server (4xx) del encolado" 0 "$?"
grep -qi 'reintent' "$SK" 2>/dev/null
assert_eq "session-capture dice que ante un rechazo hay que corregir y reintentar en el momento" 0 "$?"

# --- session-start.sh: fallback de pending anterior ---
# NOTA: aísla con HOME (ya no CLAUDE_PLUGIN_DATA) — mismo motivo que arriba.
run_start() { # <session_id_actual> <home_dir>
  printf '{"session_id":"%s","source":"startup"}' "$1" \
    | HOME="$2" ONE_BRAIN_URL="http://127.0.0.1:9" sh "$ROOT/scripts/session-start.sh" 2>/dev/null
}
# --- session-start.sh: el GC corre en el arranque (si no se wirea, no limpia nada) ---------
# Se usan markers de reuniones a propósito: ob_pending_message ni los mira, así que si
# desaparecen fue el GC y no otra limpieza — el test aísla lo que dice medir.
TMPGC=$(mktemp -d); GCP="$TMPGC/.config/one-brain/pending"; mkdir -p "$GCP"
: > "$GCP/reuniones-reminded-20200101"; touch -t 202001010000 "$GCP/reuniones-reminded-20200101"
: > "$GCP/reuniones-reminded-hoy"
run_start "current" "$TMPGC" >/dev/null
assert_eq "arranque: caduca el marker vencido" 0 \
  "$([ -e "$GCP/reuniones-reminded-20200101" ] && echo 1 || echo 0)"
assert_eq "arranque: no toca el marker fresco" 1 \
  "$([ -e "$GCP/reuniones-reminded-hoy" ] && echo 1 || echo 0)"

# --- session-start.sh: inyecta el path del bin onebrain-save, pero SOLO con token (instalación
# ya onboardeada) — REGRESIÓN de review: antes se emitía también SIN token, lo cual sugería
# falsamente que guardar funciona (sin token, onebrain-save solo encola, nunca guarda de verdad).
TMPTOK=$(mktemp -d); mkdir -p "$TMPTOK/.config/one-brain"
printf 'ob_token_fake_de_test' > "$TMPTOK/.config/one-brain/token"
OUTBIN=$(run_start "any" "$TMPTOK")
printf '%s' "$OUTBIN" | grep -q 'onebrain-save'; assert_eq "CON token: session-start inyecta el path de onebrain-save" 0 "$?"

TMPNOTOK=$(mktemp -d); mkdir -p "$TMPNOTOK/.config/one-brain"
# apaga el aviso de reuniones (independiente del token, 1×/día) para aislar SOLO el efecto del
# token sobre el recordatorio de onebrain-save — si no, el primer arranque del día siempre
# dispara REUNMSG y ensucia el repro de "sin nada pendiente".
printf '{"reuniones":false}' > "$TMPNOTOK/.config/one-brain/features.json"
OUTNOTOK=$(run_start "any" "$TMPNOTOK")
printf '%s' "$OUTNOTOK" | grep -q 'onebrain-save'; assert_eq "SIN token: NO menciona onebrain-save" 1 "$?"
# Sin token el arranque YA NO se calla: desde eb37eb7 invita a conectar, porque una instalación
# muda no le decía a nadie por qué el cerebro no aparecía. Lo que sí se mantiene —y es lo que
# este assert cuida— es que ése sea el ÚNICO bloque: sin token no se emite ningún otro aviso.
printf '%s' "$OUTNOTOK" | grep -q 'todavía no está conectado'; assert_eq "SIN token: session-start invita a conectar" 0 "$?"
printf '%s' "$OUTNOTOK" | grep -qE 'session-capture|reunion'; assert_eq "SIN token y sin nada pendiente: no sale ningún otro aviso" 1 "$?"

# con un pending de OTRA sesión => el output menciona la captura pendiente
TMP=$(mktemp -d); mkdir -p "$TMP/.config/one-brain/pending"
TROLD="$TMP/old.jsonl"; : > "$TROLD"; touch -t 202001010000 "$TROLD"
printf 'transcript=%s\ncwd=/tmp/proj\nreason=edits\n' "$TROLD" > "$(pend_path "$TMP" old)"
OUT=$(run_start "current" "$TMP")
printf '%s' "$OUT" | grep -q 'session-capture'; assert_eq "avisa pending anterior" 0 "$?"
[ -e "$(pend_path "$TMP" old)" ]; assert_eq "el aviso NO consume la marca (insiste hasta guardar)" 0 "$?"
# sin ningún pending => no menciona captura
TMP2=$(mktemp -d)
OUT=$(run_start "current" "$TMP2")
printf '%s' "$OUT" | grep -q 'session-capture'; assert_eq "sin pending no avisa" 1 "$?"
# un pending de la MISMA sesión no se auto-levanta
TMP3=$(mktemp -d); mkdir -p "$TMP3/.config/one-brain/pending"
printf 'transcript=/tmp/x.jsonl\n' > "$(pend_path "$TMP3" current)"
OUT=$(run_start "current" "$TMP3")
printf '%s' "$OUT" | grep -q 'session-capture'; assert_eq "pending de misma sesión no dispara" 1 "$?"
# REGRESIÓN: con input PRETTY-PRINTED, session_id se parsea bien => el pending propio se auto-skipea
TMP4=$(mktemp -d); mkdir -p "$TMP4/.config/one-brain/pending"
printf 'transcript=/tmp/x.jsonl\n' > "$(pend_path "$TMP4" cur9)"
OUT=$(printf '{\n  "session_id": "cur9",\n  "source": "startup"\n}' | HOME="$TMP4" ONE_BRAIN_URL="http://127.0.0.1:9" sh "$ROOT/scripts/session-start.sh" 2>/dev/null)
printf '%s' "$OUT" | grep -q 'session-capture'; assert_eq "pretty: pending de misma sesión no dispara (session_id parseado)" 1 "$?"

# --- skill handoff ---
HK="$ROOT/skills/handoff/SKILL.md"
[ -f "$HK" ]; assert_eq "skill handoff existe" 0 "$?"
grep -q '^description:' "$HK" 2>/dev/null; assert_eq "handoff tiene description" 0 "$?"
grep -q 'brain_save' "$HK" 2>/dev/null; assert_eq "handoff referencia brain_save" 0 "$?"

# --- skill resume ---
RK="$ROOT/skills/resume/SKILL.md"
[ -f "$RK" ]; assert_eq "skill resume existe" 0 "$?"
grep -q '^description:' "$RK" 2>/dev/null; assert_eq "resume tiene description" 0 "$?"
grep -q 'brain_search' "$RK" 2>/dev/null; assert_eq "resume referencia brain_search" 0 "$?"

# --- skill status ---
STK="$ROOT/skills/status/SKILL.md"
[ -f "$STK" ]; assert_eq "skill status existe" 0 "$?"
grep -q '^name:' "$STK" 2>/dev/null; assert_eq "status tiene name" 0 "$?"
grep -q '^description:' "$STK" 2>/dev/null; assert_eq "status tiene description" 0 "$?"
grep -qE 'onebrain-token|verify' "$STK" 2>/dev/null; assert_eq "status menciona onebrain-token/verify" 0 "$?"

# --- onebrain-feature ---
FEAT="$ROOT/core/bin/onebrain-feature"
[ -x "$FEAT" ]; assert_eq "onebrain-feature existe y es ejecutable" 0 "$?"

HOME_T=$(mktemp -d)
env HOME="$HOME_T" "$FEAT" auto-capture
assert_eq "sin features.json => exit 0 (default ON)" 0 "$?"

mkdir -p "$HOME_T/.config/one-brain"
printf '{"auto-capture":false,"team-digest":true}' > "$HOME_T/.config/one-brain/features.json"

env HOME="$HOME_T" "$FEAT" auto-capture
assert_eq "feature en false => exit 1" 1 "$?"

env HOME="$HOME_T" "$FEAT" team-digest
assert_eq "feature en true => exit 0" 0 "$?"

env HOME="$HOME_T" "$FEAT" daily-synthesis
assert_eq "feature ausente del json => exit 0 (default ON)" 0 "$?"

# --- doctor: cada chequeo diagnostica el entorno REAL que se le pasa (HOME aislado) ---
# doctor-lib NO es autosuficiente: llama a ob_host / ob_skill_cmd, que las define capture-lib.
# Igual que en producción, donde el adaptador carga capture-lib primero (ver la cabecera de
# session-start-lib.sh), acá hay que tenerla cargada ANTES. En este shell ya lo está —se sourcea
# arriba de todo—, pero cada `sh -c` de abajo abre un shell NUEVO donde nada de eso existe: por
# eso todos sourcean las DOS libs. Sin capture-lib el chequeo igual devuelve algo, con el nombre
# del host o del comando comido a la mitad, y el test pasa midiendo un mensaje incompleto.
. "$ROOT/core/scripts/doctor-lib.sh"
estado() { printf '%s' "$1" | cut -d'|' -f2; }

DOC_HOME=$(mktemp -d)
mkdir -p "$DOC_HOME/.config/one-brain"

# sin token
assert_eq "doctor: sin token => falla" "falla" \
  "$(estado "$(env ONE_BRAIN_TOKEN_FILE="$DOC_HOME/.config/one-brain/token" sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_token')")"

# token corto (pegado a medias)
printf 'ob_123' > "$DOC_HOME/.config/one-brain/token"
assert_eq "doctor: token truncado => falla" "falla" \
  "$(estado "$(env ONE_BRAIN_TOKEN_FILE="$DOC_HOME/.config/one-brain/token" sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_token')")"

# token válido
printf 'ob_una_clave_larga_de_verdad_1234567890' > "$DOC_HOME/.config/one-brain/token"
assert_eq "doctor: token presente => ok" "ok" \
  "$(estado "$(env ONE_BRAIN_TOKEN_FILE="$DOC_HOME/.config/one-brain/token" sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_token')")"

# hooks apagados a nivel Claude Code
printf '{"disableAllHooks": true}' > "$DOC_HOME/settings.json"
assert_eq "doctor: disableAllHooks => falla" "falla" \
  "$(estado "$(env CLAUDE_SETTINGS_FILE="$DOC_HOME/settings.json" sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_hooks_activos')")"
printf '{"model": "opus"}' > "$DOC_HOME/settings.json"
assert_eq "doctor: hooks habilitados => ok" "ok" \
  "$(estado "$(env CLAUDE_SETTINGS_FILE="$DOC_HOME/settings.json" sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_hooks_activos')")"

# --- doctor / carpeta: el chequeo mira los DOS caminos de alta ---
# El de la terminal deja el CLAUDE.md en la carpeta fija que arma setup.sh; el de la app deja
# las mismas reglas en la carpeta que la persona eligió. Buscando sólo la fija, a esta segunda
# le daba "no existe" para siempre, y la skill le indicaba correr el instalador — el `curl |
# bash` que justamente no tiene dónde pegar.
#
# Todos estos casos corren desde un cwd AISLADO: ob_doc_carpeta ahora mira el directorio actual
# y sus padres, así que sin aislar, el CLAUDE.md del repo (o el de cualquier ancestro de quien
# corra los tests) decidiría el resultado.
carpeta_desde() { # <cwd> [env extra...] -> imprime el estado del chequeo
  _cwd=$1; shift
  ( cd "$_cwd" || exit; env "$@" sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_carpeta' )
}
NEUTRO=$(mktemp -d) # cwd sin ningún CLAUDE.md arriba
# (mktemp -d cuelga de /var/folders en Mac y /tmp en Linux: ningún CLAUDE.md en el camino)

mkdir -p "$DOC_HOME/one-brain"
assert_eq "doctor: carpeta sin CLAUDE.md => aviso" "aviso" \
  "$(estado "$(carpeta_desde "$NEUTRO" ONE_BRAIN_DIR="$DOC_HOME/one-brain")")"
printf '# reglas' > "$DOC_HOME/one-brain/CLAUDE.md"
assert_eq "doctor: carpeta con CLAUDE.md => ok" "ok" \
  "$(estado "$(carpeta_desde "$NEUTRO" ONE_BRAIN_DIR="$DOC_HOME/one-brain")")"

# CAMINO DE LA APP: la carpeta fija NO existe (nunca corrió el instalador), pero la persona
# tiene sus reglas donde trabaja. Eso es una instalación sana, no un problema.
APP_DIR=$(mktemp -d)
printf '## One Brain\nLlamá `brain_context` al arrancar y proponé `brain_save` al cerrar.\n' \
  > "$APP_DIR/CLAUDE.md"
assert_eq "doctor: reglas en la carpeta donde trabaja (sin carpeta fija) => ok" "ok" \
  "$(estado "$(carpeta_desde "$APP_DIR" ONE_BRAIN_DIR="$DOC_HOME/no-existe")")"
printf '%s' "$(carpeta_desde "$APP_DIR" ONE_BRAIN_DIR="$DOC_HOME/no-existe")" | grep -q "$APP_DIR/CLAUDE.md"
assert_eq "doctor: el detalle dice DÓNDE están las reglas que encontró" 0 "$?"

# Vale también desde un subdirectorio: Claude Code carga el CLAUDE.md del directorio abierto y
# los de sus padres, así que trabajar en una subcarpeta del espacio sigue estando configurado.
mkdir -p "$APP_DIR/sub/proyecto"
assert_eq "doctor: reglas en una carpeta padre => ok" "ok" \
  "$(estado "$(carpeta_desde "$APP_DIR/sub/proyecto" ONE_BRAIN_DIR="$DOC_HOME/no-existe")")"

# Un CLAUDE.md cualquiera NO alcanza: sin las tools nombradas, Claude no va a usar el cerebro.
# (Es el falso positivo inverso — decirle "está todo bien" a quien no tiene nada configurado.)
OTRO=$(mktemp -d)
printf '# Mi proyecto\nUsá pnpm, no npm.\n' > "$OTRO/CLAUDE.md"
assert_eq "doctor: CLAUDE.md sin reglas de One Brain no cuenta => aviso" "aviso" \
  "$(estado "$(carpeta_desde "$OTRO" ONE_BRAIN_DIR="$DOC_HOME/no-existe")")"
# Y el aviso NO puede mandar a correr el instalador como si fuera la única salida.
printf '%s' "$(carpeta_desde "$OTRO" ONE_BRAIN_DIR="$DOC_HOME/no-existe")" | grep -qi 'curl'
assert_eq "doctor: el aviso no le tira un curl a quien quizá no usa terminal" 1 "$?"

# ob_doc_claudemd_cerca sale 1 (y no imprime) cuando no hay nada: el que llama distingue.
( cd "$NEUTRO" || exit; sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_claudemd_cerca' >/dev/null 2>&1 )
assert_eq "ob_doc_claudemd_cerca: sin CLAUDE.md con reglas => exit 1" 1 "$?"

# el parser del hook anda en este entorno (misma señal que ob_selftest)
assert_eq "doctor: parser del hook => ok" "ok" "$(estado "$(ob_doc_parser)")"

# --- doctor: la versión que reporta es la INSTALADA, no la del bin que corrió ---
# Bug real (24-jul): al actualizar el plugin con Claude Code abierto, la versión vieja queda
# huérfana pero el PATH de la sesión sigue apuntando a su bin/. El doctor leía el plugin.json de
# su propio directorio, así que reportaba la vieja: el cliente actualiza, corre el doctor, ve la
# versión de antes y cree que el update falló. Y encima los binarios nuevos (onebrain-save) no
# están en el PATH hasta reiniciar. El doctor tiene que decir la verdad y avisar del desfasaje.
V_HOME=$(mktemp -d)
mkdir -p "$V_HOME/.claude/plugins" "$V_HOME/vieja/.claude-plugin" "$V_HOME/nueva/.claude-plugin"
printf '{"name":"one-brain","version":"0.1.271"}' > "$V_HOME/vieja/.claude-plugin/plugin.json"
printf '{"name":"one-brain","version":"0.1.305"}' > "$V_HOME/nueva/.claude-plugin/plugin.json"
V_PLUGINS="$V_HOME/.claude/plugins/installed_plugins.json"
cat > "$V_PLUGINS" <<'JSON'
{
  "version": 2,
  "plugins": {
    "vercel@claude-plugins-official": [
      { "scope": "user", "version": "0.43.0" }
    ],
    "one-brain@prophet": [
      {
        "scope": "user",
        "installPath": "/Users/x/.claude/plugins/cache/prophet/one-brain/0.1.305",
        "version": "0.1.305"
      }
    ],
    "telegram@claude-plugins-official": [
      { "scope": "user", "version": "0.0.6" }
    ]
  }
}
JSON
version_de() { # <root del plugin que "corre"> [archivo installed_plugins]
  env CLAUDE_PLUGINS_FILE="${2-$V_PLUGINS}" sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_version "$1"' _ "$1"
}
detalle() { printf '%s' "$1" | cut -d'|' -f3; }

assert_eq "doctor: bin viejo en el PATH => aviso" "aviso" "$(estado "$(version_de "$V_HOME/vieja")")"
printf '%s' "$(detalle "$(version_de "$V_HOME/vieja")")" | grep -q '0\.1\.305'
assert_eq "doctor: el aviso nombra la versión INSTALADA" 0 "$?"
printf '%s' "$(detalle "$(version_de "$V_HOME/vieja")")" | grep -qi 'reinici'
assert_eq "doctor: el aviso dice cómo destrabarlo (reiniciar)" 0 "$?"

assert_eq "doctor: instalada == la que corre => ok" "ok" "$(estado "$(version_de "$V_HOME/nueva")")"
printf '%s' "$(detalle "$(version_de "$V_HOME/nueva")")" | grep -q '0\.1\.305'
assert_eq "doctor: en ok reporta la versión" 0 "$?"

# sin registro de Claude Code (otro instalador, o el archivo no está): no inventa nada, cae a la
# versión del directorio que corre — el comportamiento de antes, que sigue siendo el correcto acá.
assert_eq "doctor: sin installed_plugins.json => ok con la del directorio" "ok" \
  "$(estado "$(version_de "$V_HOME/vieja" "$V_HOME/no-existe.json")")"
printf '%s' "$(detalle "$(version_de "$V_HOME/vieja" "$V_HOME/no-existe.json")")" | grep -q '0\.1\.271'
assert_eq "doctor: sin registro reporta la del directorio" 0 "$?"

# el ejecutable existe y nunca imprime el token en claro
DOC="$ROOT/core/bin/onebrain-doctor"
[ -x "$DOC" ]; assert_eq "onebrain-doctor existe y es ejecutable" 0 "$?"
SALIDA=$(env HOME="$DOC_HOME" ONE_BRAIN_TOKEN_FILE="$DOC_HOME/.config/one-brain/token" ONE_BRAIN_URL="http://127.0.0.1:9" "$DOC" 2>&1)
printf '%s' "$SALIDA" | grep -q 'ob_una_clave_larga'; assert_eq "doctor NUNCA imprime el token" 1 "$?"
printf '%s' "$SALIDA" | grep -q 'token'; assert_eq "doctor reporta el chequeo de token" 0 "$?"

# --- headers.sh: el helper que le pasa el token al MCP, incluido Windows ---
HDR="$ROOT/scripts/headers.sh"
H_HOME=$(mktemp -d)
mkdir -p "$H_HOME/.config/one-brain"
printf 'ob_token_normal' > "$H_HOME/.config/one-brain/token"
assert_eq "headers: token normal" '{"Authorization":"Bearer ob_token_normal"}' \
  "$(env HOME="$H_HOME" sh "$HDR" 2>/dev/null)"

# Windows sin HOME: Git Bash a veces solo expone USERPROFILE y el helper quedaba mudo,
# el usuario caía al login por email y creía que el token no servía.
assert_eq "headers: sin HOME usa USERPROFILE" '{"Authorization":"Bearer ob_token_normal"}' \
  "$(env -u HOME USERPROFILE="$H_HOME" sh "$HDR" 2>/dev/null)"

# Token pegado desde un editor de Windows: CRLF y BOM UTF-8 adelante.
printf '\357\273\277ob_token_bom\r\n' > "$H_HOME/.config/one-brain/token"
assert_eq "headers: tolera BOM y CRLF" '{"Authorization":"Bearer ob_token_bom"}' \
  "$(env HOME="$H_HOME" sh "$HDR" 2>/dev/null)"

# Sin archivo pero con la variable de entorno (útil en máquinas donde no se puede escribir
# en el perfil, y en CI).
rm -f "$H_HOME/.config/one-brain/token"
assert_eq "headers: cae a ONE_BRAIN_TOKEN" '{"Authorization":"Bearer ob_desde_env"}' \
  "$(env HOME="$H_HOME" ONE_BRAIN_TOKEN=ob_desde_env sh "$HDR" 2>/dev/null)"

assert_eq "headers: sin nada => objeto vacío" '{}' "$(env HOME="$H_HOME" sh "$HDR" 2>/dev/null)"

# Windows nativo real (no la ruta ya traducida por MSYS/Git Bash): USERPROFILE con backslashes.
# Antes de normalizar, "$BASE/.config/..." mezclaba \ y / y podía no resolver el archivo.
printf 'ob_token_normal' > "$H_HOME/.config/one-brain/token"
H_WIN=$(printf '%s' "$H_HOME" | tr '/' '\\')
assert_eq "headers: USERPROFILE con backslashes se normaliza" '{"Authorization":"Bearer ob_token_normal"}' \
  "$(env -u HOME USERPROFILE="$H_WIN" sh "$HDR" 2>/dev/null)"

# Ni HOME ni USERPROFILE: antes armaba una ruta rota ("/.config/...") y buscaba ahí en
# silencio. Ahora avisa la razón concreta en vez de fallar mudo.
SALIDA=$(env -u HOME -u USERPROFILE -u ONE_BRAIN_TOKEN_FILE -u ONE_BRAIN_TOKEN sh "$HDR" 2>&1 >/dev/null)
printf '%s' "$SALIDA" | grep -q 'HOME ni USERPROFILE'
assert_eq "headers: sin HOME ni USERPROFILE avisa la razón" 0 "$?"

# Archivo sin permiso de lectura: antes cualquier motivo de "no pude leer el token" caía en el
# mismo "sin token" genérico y no distinguía "no conectaste" de "hay un archivo pero no puedo
# abrirlo". root puede leer cualquier archivo igual, así que el chequeo no aplica corriendo así.
if [ "$(id -u)" != "0" ]; then
  printf 'ob_token_normal' > "$H_HOME/.config/one-brain/token"
  chmod 000 "$H_HOME/.config/one-brain/token"
  SALIDA=$(env HOME="$H_HOME" sh "$HDR" 2>&1 >/dev/null)
  printf '%s' "$SALIDA" | grep -q 'no se puede leer'
  assert_eq "headers: archivo sin permiso de lectura avisa por qué" 0 "$?"
  chmod 600 "$H_HOME/.config/one-brain/token"
fi

# Archivo vacío (0 bytes): distinto de "no existe" -- indica que algo escribió mal, no que
# todavía no se conectó.
: > "$H_HOME/.config/one-brain/token"
SALIDA=$(env HOME="$H_HOME" sh "$HDR" 2>&1 >/dev/null)
printf '%s' "$SALIDA" | grep -q 'vacío'
assert_eq "headers: archivo de token vacío avisa por qué" 0 "$?"

# UTF-16LE con BOM (FF FE) y un byte NUL intercalado entre cada caracter: así queda un archivo
# de token si se crea con redirección de PowerShell 5.1 (Out-File es UTF-16 ahí por default).
# Sin este caso, el token salía con basura y el server daba 401 sin ninguna pista de por qué.
printf '\377\376o\000b\000_\000t\000o\000k\000e\000n\000_\000u\000t\000f\0001\0006\000' \
  > "$H_HOME/.config/one-brain/token"
assert_eq "headers: tolera UTF-16LE con BOM (NUL intercalado)" '{"Authorization":"Bearer ob_token_utf16"}' \
  "$(env HOME="$H_HOME" sh "$HDR" 2>/dev/null)"

# Token corrupto que sobrevive a la limpieza (ej. una comilla en el medio): mandado tal cual
# rompe el JSON del header en silencio. Se descarta con aviso en vez de eso.
printf 'ob_token"raro' > "$H_HOME/.config/one-brain/token"
assert_eq "headers: token con caracteres inválidos => objeto vacío" '{}' \
  "$(env HOME="$H_HOME" sh "$HDR" 2>/dev/null)"
SALIDA=$(env HOME="$H_HOME" sh "$HDR" 2>&1 >/dev/null)
printf '%s' "$SALIDA" | grep -q 'caracteres inválidos'
assert_eq "headers: token corrupto avisa por qué" 0 "$?"

rm -f "$H_HOME/.config/one-brain/token"

# --- skill onboard: el onboarding tiene que dejar el cerebro CON ALGO ADENTRO (T1.1) ---
# Causa raíz de que 3 de los 4 cerebros vivos estén en CERO memorias: la persona escribía su
# constitución y quedaba con un cerebro vacío, así que su primera consulta no devolvía nada y
# abandonaba. Estos chequeos son sobre el TEXTO de la skill porque quien la ejecuta es el
# modelo: acá se defiende que las instrucciones que gobiernan esa ejecución sigan estando.
OBK="$ROOT/skills/onboard/SKILL.md"
[ -f "$OBK" ]; assert_eq "skill onboard existe" 0 "$?"
grep -q '^description:' "$OBK" 2>/dev/null; assert_eq "onboard tiene description" 0 "$?"
grep -q 'onebrain-constitution' "$OBK" 2>/dev/null; assert_eq "onboard guarda la constitución con el bin" 0 "$?"
grep -q 'onebrain-save' "$OBK" 2>/dev/null; assert_eq "onboard siembra memorias con onebrain-save" 0 "$?"
grep -qE '8 (a|y|-)+ ?12|8-12' "$OBK" 2>/dev/null; assert_eq "onboard fija el rango 8-12 hechos" 0 "$?"
grep -q -- '--entities' "$OBK" 2>/dev/null; assert_eq "la siembra pasa entidades (sin grafo no hay recuperación)" 0 "$?"
# Las tres defensas contra fabricar datos, que es el riesgo que introduce pedir volumen:
grep -qi 'no inventes' "$OBK" 2>/dev/null; assert_eq "onboard prohíbe inventar" 0 "$?"
grep -qi 'señalar la frase' "$OBK" 2>/dev/null; assert_eq "onboard exige poder señalar la frase que dijo la persona" 0 "$?"
grep -qi 'rellen' "$OBK" 2>/dev/null; assert_eq "onboard prohíbe rellenar para llegar al número" 0 "$?"
grep -qiE 'antes de guardar' "$OBK" 2>/dev/null; assert_eq "onboard muestra la lista ANTES de guardar (la persona corrige)" 0 "$?"
grep -qiE 'menos de 8' "$OBK" 2>/dev/null; assert_eq "onboard dice qué hacer si no hay material para 8" 0 "$?"
# El cierre: que la persona VEA que el cerebro ya devuelve algo (y que hay escalera para leer la
# memoria entera, no solo el recorte de 300 chars que devuelve la búsqueda).
grep -q 'brain_search' "$OBK" 2>/dev/null; assert_eq "onboard verifica con brain_search que el cerebro devuelve algo" 0 "$?"
grep -q 'brain_get' "$OBK" 2>/dev/null; assert_eq "onboard nombra brain_get (leer la memoria entera)" 0 "$?"
# Si no es admin, la constitución da 403 — pero sembrar NO requiere admin. Antes, un 403 dejaba
# a esa persona con el cerebro igual de vacío que si no hubiera hecho el onboarding.
grep -q '403' "$OBK" 2>/dev/null; assert_eq "onboard contempla el 403 de constitución sin abortar la siembra" 0 "$?"

# El comando de ejemplo de la skill se EJECUTA de verdad, no se lee. Es la clase de drift que ya
# nos pasó: session-capture le enseñó al modelo durante meses un dato falso sobre este mismo bin.
# Un flag mal escrito en la doc = exit 2 y la siembra entera cae sin que nadie lo note hasta que
# un cliente hace el onboarding. Sin token => el payload termina en la cola, no toca ningún
# cerebro real, y así se puede inspeccionar lo que se habría mandado.
CMD_SIEMBRA=$(sed -n '/onebrain-save --type/,/--entities/p' "$OBK")
export HOME="$(mktemp -d)"
( export PATH="$ROOT/bin:$PATH"; eval "$CMD_SIEMBRA" ) >/dev/null 2>&1
assert_eq "el comando de siembra que documenta la skill corre (exit 0)" 0 "$?"
QFILE_SIEMBRA=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | head -n1)
grep -q '"type":"conocimiento"' "$QFILE_SIEMBRA" 2>/dev/null
assert_eq "el ejemplo produce un payload con el type documentado" 0 "$?"
grep -q '"entities":\["cliente","persona","tema"\]' "$QFILE_SIEMBRA" 2>/dev/null
assert_eq "el ejemplo linkea entidades de verdad (no las pierde en el parseo)" 0 "$?"

# --- skill doctor ---
DTK="$ROOT/skills/doctor/SKILL.md"
[ -f "$DTK" ]; assert_eq "skill doctor existe" 0 "$?"
grep -q '^name:' "$DTK" 2>/dev/null; assert_eq "doctor tiene name" 0 "$?"
grep -q 'onebrain-doctor' "$DTK" 2>/dev/null; assert_eq "doctor invoca el ejecutable" 0 "$?"
# Drift de doc: la skill enumera los chequeos para el modelo, y la regla que tiene escrita es
# "no inventes chequeos que el comando no hizo". El inverso también aplica — un chequeo nuevo
# que la skill no nombra es un chequeo que nadie va a explicar. Ya nos pasó con session-capture.
for _chk in token curl parser hooks carpeta entrega conexion version; do
  grep -q "\*\*$_chk\*\*" "$DTK" 2>/dev/null
  assert_eq "la skill doctor documenta el chequeo '$_chk'" 0 "$?"
done

# El consejo del chequeo `carpeta` mandaba a "correr el instalador de la carpeta de trabajo",
# que es el `curl … | bash` del camino de la terminal. A quien se dio de alta desde la app —el
# que eligió explícitamente no tocar la consola— eso no es un arreglo: es una instrucción que
# no puede seguir, encima para un problema que probablemente no tiene.
sed -n '/^| `carpeta`/p' "$DTK" | grep -qi 'app'
assert_eq "el consejo de 'carpeta' contempla a quien usa la app de escritorio" 0 "$?"
sed -n '/^| `carpeta`/p' "$DTK" | grep -qi 'terminal'
assert_eq "el consejo de 'carpeta' distingue el caso de la terminal" 0 "$?"

# Actualizar el plugin: la instrucción de la terminal se queda (es la corta para quien ya vive
# ahí), pero tiene que existir la alternativa de que lo corra Claude Code, que tiene Bash.
grep -qi 'Bash' "$DTK"
assert_eq "la skill doctor ofrece correr el update por Bash (para quien no usa terminal)" 0 "$?"
grep -q 'claude plugin update one-brain@prophet' "$DTK"
assert_eq "la skill doctor sigue dando el comando de terminal" 0 "$?"

# --- ONBOARDING.md y README.md: el ORDEN de instalación ---
# Los dos listaban marketplace add → install → connect seguidos, con el reinicio recién al
# final. Sin reiniciar entre install y connect la skill `connect` todavía no está cargada y
# Claude Code contesta "unknown skill": la persona cree que su token no sirve.
orden_instalacion() { # <archivo> -> "ok" si install < reinicio < connect
  _f=$1
  _i=$(grep -n '/plugin install' "$_f" | head -n1 | cut -d: -f1)
  _c=$(grep -n '/one-brain:connect' "$_f" | head -n1 | cut -d: -f1)
  # El README del paquete está en español, pero el que termina siendo la portada del repo
  # PÚBLICO es README.public.md, en inglés. Buscando sólo en español, la suite pasaba acá y
  # fallaba corriendo desde el repo publicado — o sea, justo donde lo lee un cliente nuevo.
  _r=$(grep -niE 'cerr[áa] claude code|volv[ée] a abrirlo|close claude code|open it again|reopen' "$_f" | awk -F: -v i="${_i:-0}" '$1 > i {print $1; exit}')
  if [ -n "$_i" ] && [ -n "$_c" ] && [ -n "$_r" ] && [ "$_i" -lt "$_r" ] && [ "$_r" -lt "$_c" ]; then
    printf 'ok'
  else
    printf 'mal (install=%s reinicio=%s connect=%s)' "$_i" "$_r" "$_c"
  fi
}
assert_eq "ONBOARDING.md: reinicio ENTRE install y connect" "ok" "$(orden_instalacion "$ROOT/ONBOARDING.md")"
assert_eq "README.md del plugin: reinicio ENTRE install y connect" "ok" "$(orden_instalacion "$ROOT/README.md")"
# README.public.md es el que publish-plugin.sh copia como README del repo público: la primera
# página que ve alguien que llega al plugin sin conocernos. Quedaba fuera del assert, así que
# el orden se custodiaba en las dos versiones internas y no en la que efectivamente se publica.
if [ -f "$ROOT/README.public.md" ]; then
  assert_eq "README.public.md (portada del repo público): reinicio ENTRE install y connect" "ok" "$(orden_instalacion "$ROOT/README.public.md")"
fi

# --- ONBOARDING.md: jq ya NO es requisito ---
# onebrain-constitution y capture-lib.sh prueban jq → python3 → perl, y el propio doctor lo
# trata como opcional. Pedirlo como requisito frenaba altas por una dependencia que no existe.
sed -n '/^## Requisitos/,/^## /p' "$ROOT/ONBOARDING.md" | grep -q 'jq` instalado'
assert_eq "ONBOARDING.md ya no exige jq en los requisitos" 1 "$?"
grep -q 'jq' "$ROOT/core/bin/onebrain-constitution" && grep -q 'python3' "$ROOT/core/bin/onebrain-constitution"
assert_eq "…porque el bin de la constitución tiene fallback a python3" 0 "$?"

# --- ONBOARDING.md: actualizar sin abrir una consola ---
grep -qi 'Bash' "$ROOT/ONBOARDING.md"
assert_eq "ONBOARDING.md ofrece pedirle el update a Claude Code (Bash)" 0 "$?"
grep -q 'claude plugin update one-brain@prophet' "$ROOT/ONBOARDING.md"
assert_eq "ONBOARDING.md conserva el comando de terminal" 0 "$?"

# --- ob_enqueue: si el guardado falla, el entry queda en cola (no se pierde) ---
export HOME="$(mktemp -d)"
PAYLOAD='{"type":"avance","title":"T","content_md":"C"}'
ob_enqueue "$PAYLOAD"
CNT=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "enqueue crea 1 archivo en la cola" 1 "$CNT"
QFILE=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | head -n1)
assert_eq "el payload encolado se preserva" "$PAYLOAD" "$(cat "$QFILE")"

# --- ob_enqueue: concurrencia — N invocaciones EN PARALELO no deben pisarse (TOCTOU) ---
# Repro del review: naming secuencial (queued-$_n con while [ -e ]) es check-then-act, no
# atómico. 30 procesos compitiendo por el mismo contador colisionan y se pierden escrituras.
export HOME="$(mktemp -d)"
i=1
while [ "$i" -le 30 ]; do
  ob_enqueue "payload-$i" &
  i=$((i+1))
done
wait
CNTC=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "enqueue concurrente: 30 llamadas en paralelo => 30 archivos (cero colisiones)" 30 "$CNTC"

# --- ob_flush_queue: reintenta la cola; borra los que guardan OK, deja los que fallan ---
export HOME="$(mktemp -d)"
mkdir -p "$(ob_queue_dir)"; printf '{"type":"avance","title":"T","content_md":"C"}' > "$(ob_queue_dir)/queued-1"
# stub de guardado: OK si ONEBRAIN_TEST_SAVE=ok, si no falla (pisa la def real de capture-lib)
ob_try_save() { [ "$ONEBRAIN_TEST_SAVE" = "ok" ]; }
ONEBRAIN_TEST_SAVE=ok ob_flush_queue
LEFT=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "flush borra los guardados OK" 0 "$LEFT"
# el que falla NO se pierde: queda en la cola para el próximo intento
printf '{"type":"avance","title":"T2","content_md":"C2"}' > "$(ob_queue_dir)/queued-2"
ONEBRAIN_TEST_SAVE=no ob_flush_queue
LEFT2=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "flush conserva los que fallan" 1 "$LEFT2"

# --- ob_flush_queue: tope de items por corrida (una cola gigante no debe loopear sin fin) ---
export HOME="$(mktemp -d)"
mkdir -p "$(ob_queue_dir)"
i=1
while [ "$i" -le 25 ]; do
  printf '{"type":"avance","title":"T%s","content_md":"C"}' "$i" > "$(ob_queue_dir)/queued-item-$i"
  i=$((i+1))
done
ob_try_save() { [ "$ONEBRAIN_TEST_SAVE" = "ok" ]; }
ONEBRAIN_TEST_SAVE=ok ob_flush_queue
LEFT3=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "flush procesa como máx 20 por corrida (cola de 25 => quedan 5)" 5 "$LEFT3"

# --- ob_flush_queue: idempotente (claim-by-rename) — 2 arranques concurrentes sobre la MISMA
# cola no deben procesar el mismo item dos veces (memoria DUPLICADA en el server) ---
export HOME="$(mktemp -d)"
mkdir -p "$(ob_queue_dir)"
i=1
while [ "$i" -le 10 ]; do
  printf '{"type":"avance","title":"T%s","content_md":"C"}' "$i" > "$(ob_queue_dir)/queued-race-$i"
  i=$((i+1))
done
CALLLOG="$HOME/calls.log"; : > "$CALLLOG"
# stub: SIEMPRE guarda OK, pero deja registro de cada llamada (para contar duplicados)
ob_try_save() { printf '%s\n' "$1" >> "$CALLLOG"; return 0; }
ob_flush_queue &
ob_flush_queue &
wait
CALLS=$(wc -l < "$CALLLOG" | tr -d ' ')
assert_eq "flush concurrente: cada item se procesa EXACTAMENTE 1 vez (sin duplicados)" 10 "$CALLS"
LEFT4=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "flush concurrente: la cola queda vacía (todo se guardó)" 0 "$LEFT4"
LEFTIN=$(ls "$(ob_queue_dir)"/inflight-* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "flush concurrente: no quedan inflight-* colgados" 0 "$LEFTIN"

# --- ob_try_save: timeout acotado a 8s (consistente con las otras llamadas de session-start,
# que ya usan --max-time 8) para no colgar el arranque con un server caído/lento ---
grep -q -- '--max-time 8' "$ROOT/core/scripts/capture-lib.sh"
assert_eq "ob_try_save usa --max-time 8 (no 15)" 0 "$?"

# --- arranque: el flush de la cola corre BACKGROUNDEADO (no bloquea el arranque) ---
# Se chequea en el core, que es donde vive el arranque desde que lo comparten los dos programas
# (el adaptador de acá ya no tiene lógica). Sigue protegiendo lo mismo: si alguien le saca el
# "( ... & )", un flush lento cuelga el arranque de todos los clientes, de los dos hosts.
# El ^ tolera indentación: adentro de la función el paréntesis ya no arranca en la columna 0.
grep -qE '^[[:space:]]*\( *ob_flush_queue\b.*& *\)' "$ROOT/core/scripts/session-start-lib.sh"
assert_eq "el arranque backgroundea ob_flush_queue" 0 "$?"

# Medición end-to-end: con un curl FAKE que tarda 3s, el arranque no debe sumar ese tiempo
# por el flush (el propio bloque principal de session-start ya está acotado a ~3s en paralelo;
# si el flush bloqueara ANTES de ese bloque, sumaría otros ~3s => total ~6s).
FAKEBIN=$(mktemp -d)
cat > "$FAKEBIN/curl" <<'FAKECURL'
#!/bin/sh
sleep 3
printf '000'
FAKECURL
chmod +x "$FAKEBIN/curl"
TMPQ=$(mktemp -d)
mkdir -p "$TMPQ/.config/one-brain/queue"
printf '{"type":"avance","title":"T","content_md":"C"}' > "$TMPQ/.config/one-brain/queue/queued-block"
printf 'ob_token_fake_de_test' > "$TMPQ/.config/one-brain/token"
T0=$(date +%s)
printf '{"session_id":"blk1","source":"startup"}' \
  | HOME="$TMPQ" PATH="$FAKEBIN:$PATH" ONE_BRAIN_URL="http://127.0.0.1:9" sh "$ROOT/scripts/session-start.sh" >/dev/null 2>&1
T1=$(date +%s)
ELAPSED=$((T1 - T0))
[ "$ELAPSED" -lt 5 ]; assert_eq "session-start no bloquea por el flush (curl fake 3s, total < 5s)" 0 "$?"

# --- onebrain-save: sin --area, el payload NO debe forzar "area":"" (rompe la herencia de
# area del autor en el server, que usa `input.area ?? user.area` — ?? no cae sobre "").
# Se prueba con el bin REAL, sin token, así el payload se puede inspeccionar en la cola en
# vez de mockear un server.
SAVEBIN="$ROOT/core/bin/onebrain-save"
export HOME="$(mktemp -d)"
"$SAVEBIN" --type avance --title "T" --content "C" >/dev/null 2>&1
QFILE_NOAREA=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | head -n1)
grep -q '"area"' "$QFILE_NOAREA"
assert_eq "onebrain-save sin --area: el payload NO incluye la clave area" 1 "$?"

export HOME="$(mktemp -d)"
"$SAVEBIN" --type avance --title "T" --content "C" --area ventas >/dev/null 2>&1
QFILE_AREA=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | head -n1)
grep -q '"area":"ventas"' "$QFILE_AREA"
assert_eq "onebrain-save con --area ventas: el payload incluye area:ventas" 0 "$?"

# --- onebrain-save: --supersedes (P.3) ---
# De 529 entradas en prod hay CERO invalidadas: el server soporta `supersedes` desde siempre
# (brainSave marca la vieja con invalidated_at/invalidated_by) pero el bin —el canal que usan
# las skills— no lo exponía, así que el cerebro acumula decisiones contradictorias sin ninguna
# señal de cuál vale. Misma técnica que los tests de --area: sin token, el payload se inspecciona
# en la cola en vez de montar un server.
SUP_UUID="8f3d0a1e-2b4c-4d6e-9f01-23456789abcd"
export HOME="$(mktemp -d)"
"$SAVEBIN" --type decision --title "T" --content "C" --supersedes "$SUP_UUID" >/dev/null 2>&1
QFILE_SUP=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | head -n1)
grep -q "\"supersedes\":\"$SUP_UUID\"" "$QFILE_SUP" 2>/dev/null
assert_eq "onebrain-save --supersedes <uuid>: el payload lo incluye" 0 "$?"

# Sin el flag, la clave NO va: el server valida `supersedes` como uuid, así que mandar "" sería
# un 400 en cada guardado normal (mismo razonamiento que --area, distinto motivo).
export HOME="$(mktemp -d)"
"$SAVEBIN" --type avance --title "T" --content "C" >/dev/null 2>&1
QFILE_NOSUP=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | head -n1)
grep -q '"supersedes"' "$QFILE_NOSUP" 2>/dev/null
assert_eq "onebrain-save sin --supersedes: el payload NO incluye la clave" 1 "$?"

# Un id que no es uuid se rechaza ACÁ, no allá: el server contesta 400 y (desde A-5) un 4xx no
# se encola, así que el usuario perdería la memoria entera por un id mal copiado. Fallar antes
# de armar el payload deja la memoria intacta para reintentar con el id bueno.
export HOME="$(mktemp -d)"
ERR_SUP=$("$SAVEBIN" --type decision --title "T" --content "C" --supersedes "la-decision-vieja" 2>&1 >/dev/null)
assert_eq "--supersedes con valor que no es uuid => exit 2" 2 "$?"
printf '%s' "$ERR_SUP" | grep -qi 'uuid'
assert_eq "el error explica que se espera un uuid (no 'opción desconocida')" 0 "$?"
CNT_SUP=$(ls "$(ob_queue_dir)"/queued-* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "uuid inválido: no encola nada (no se guarda a medias)" 0 "$CNT_SUP"

# El server contesta 200 con `warning` cuando el id existe pero no invalidó nada (no es una
# decisión, o es de otro cerebro). Tragarse ese warning es exactamente el bug que estamos
# arreglando: el usuario creería que reemplazó la decisión vieja y quedarían las dos vigentes.
FAKE_W=$(mktemp -d)
cat > "$FAKE_W/curl" <<'FAKEWARN'
#!/bin/sh
printf '{"entry_id":"entry-nuevo-1","linked_entities":[],"warning":"supersedes: no se encontró una decisión con ese id en este cerebro; nada fue reemplazado."}\n200'
FAKEWARN
chmod +x "$FAKE_W/curl"
H_W=$(mktemp -d); mkdir -p "$H_W/.config/one-brain"
printf 'ob_token_fake_de_test' > "$H_W/.config/one-brain/token"
ERR_W=$(env HOME="$H_W" PATH="$FAKE_W:$PATH" "$SAVEBIN" --type decision --title "T" --content "C" --supersedes "$SUP_UUID" 2>&1 >/dev/null)
printf '%s' "$ERR_W" | grep -q 'nada fue reemplazado'
assert_eq "el warning del server (no invalidó nada) se muestra, no se traga" 0 "$?"
OUT_W=$(env HOME="$H_W" PATH="$FAKE_W:$PATH" "$SAVEBIN" --type decision --title "T" --content "C" --supersedes "$SUP_UUID" 2>/dev/null)
assert_eq "con warning, igual imprime el entry_id (el save fue OK)" "entry-nuevo-1" "$OUT_W"
env HOME="$H_W" PATH="$FAKE_W:$PATH" "$SAVEBIN" --type decision --title "T" --content "C" --supersedes "$SUP_UUID" >/dev/null 2>&1
assert_eq "guardado con warning => exit 0 (el aviso no convierte el éxito en falla)" 0 "$?"

# Y el camino normal (200 sin warning) sigue mudo en stderr y con exit 0: el aviso nuevo no
# puede empezar a hablar en cada guardado.
FAKE_OK=$(mktemp -d)
cat > "$FAKE_OK/curl" <<'FAKEOK'
#!/bin/sh
printf '{"entry_id":"entry-limpio-2","linked_entities":[]}\n200'
FAKEOK
chmod +x "$FAKE_OK/curl"
ERR_OK=$(env HOME="$H_W" PATH="$FAKE_OK:$PATH" "$SAVEBIN" --type avance --title "T" --content "C" 2>&1 >/dev/null)
assert_eq "guardado normal => exit 0" 0 "$?"
assert_eq "guardado normal => stderr vacío" "" "$ERR_OK"

# --- ob_flush_queue: reapea inflight-* huérfanos (proceso murió entre el claim-by-rename y el
# save) — sin esto quedaban en inflight-* PARA SIEMPRE, el glob del loop solo toma queued-*.
# Se stubea ob_try_save para que SIEMPRE falle: así el resultado observado ("terminó como
# queued-<orig>, no como inflight-*") depende únicamente del reaper, no de si el reintento
# posterior (dentro del mismo ob_flush_queue) tuvo éxito o no — aísla lo que se está probando.
# NOTA: un test anterior en este archivo ya dejó ob_try_save permanentemente stubeado (sin
# restore) — redefinirla acá explícitamente es obligatorio, no defensivo de más.
export HOME="$(mktemp -d)"
mkdir -p "$(ob_queue_dir)"
Q_REAP=$(ob_queue_dir)
printf '{"type":"avance","title":"T","content_md":"C"}' > "$Q_REAP/inflight-999-queued-orphan"
touch -t 202001010000 "$Q_REAP/inflight-999-queued-orphan"
printf '{"type":"avance","title":"T2","content_md":"C2"}' > "$Q_REAP/inflight-888-queued-fresh"
ob_try_save() { return 1; }
ob_flush_queue >/dev/null 2>&1
[ -e "$Q_REAP/queued-orphan" ]
assert_eq "inflight viejo huérfano vuelve a queued-<orig>" 0 "$?"
[ -e "$Q_REAP/inflight-999-queued-orphan" ]
assert_eq "el inflight viejo ya no existe con ese nombre" 1 "$?"
[ -e "$Q_REAP/inflight-888-queued-fresh" ]
assert_eq "inflight reciente NO se toca (sesión probablemente viva)" 0 "$?"
# restaura la implementación real (no dejar el stub contaminando tests que se agreguen después)
. "$ROOT/core/scripts/capture-lib.sh"

# --- bin/onebrain-save: parseo de flags ---
# Regresión: `shift 2` con un solo argumento restante NO baja $# en POSIX sh, así que el while
# giraba PARA SIEMPRE. Se dispara cuando el modelo arma el comando y un flag queda sin valor
# (una comilla que rompe el quoting alcanza) — justo al cerrar la sesión, colgando el Bash de
# Claude Code hasta su timeout. Por eso estos casos corren con límite: si el bug vuelve, el
# test devuelve 124 en vez de colgar el runner entero.
run_limited() { # <segundos> <cmd...> -> imprime el exit code, o 124 si hubo que matarlo
  _lim=$1; shift
  "$@" >/dev/null 2>&1 &
  _pid=$!; _n=0
  while [ "$_n" -lt "$_lim" ]; do
    kill -0 "$_pid" 2>/dev/null || break
    sleep 1; _n=$((_n+1))
  done
  if kill -0 "$_pid" 2>/dev/null; then
    kill -9 "$_pid" 2>/dev/null; wait "$_pid" 2>/dev/null; printf '124'
  else
    wait "$_pid"; printf '%s' "$?"
  fi
}
# --- ob_clip: recorte por CARACTERES, no por bytes ---
# Cortar por bytes parte los acentos al medio y deja mojibake, en un producto que escribe todo
# en español. "ñandúes" tiene 7 caracteres y 9 bytes: si el recorte fuera por bytes, cortar en
# 7 devolvería un carácter roto.
assert_eq "texto corto pasa entero"      "hola" "$(printf 'hola' | ob_clip 100)"
assert_eq "recorta a N caracteres"       "abcde" "$(printf 'abcdefghij' | ob_clip 5 | head -n1)"
assert_eq "avisa que recortó"            1 "$(printf 'abcdefghij' | ob_clip 5 | grep -c 'recortado')"
# El aviso tiene que decir QUÉ HACER, no sólo que pasó. Un "[...recortado...]" a secas deja a la
# sesión con medio handoff y sin manera de pedir el resto: pasó de verdad el 29-jul, y se
# resolvió sólo porque a alguien se le ocurrió ir a buscarlo. El id viaja al principio del
# bloque (ver src/lib/resume.ts), así que sobrevive al corte y esta línea lo puede referenciar.
assert_eq "el aviso de recorte dice cómo recuperar lo que falta" 1 \
  "$(printf 'abcdefghij' | ob_clip 5 | grep -c 'brain_get')"
assert_eq "no parte los acentos"         "ñandúes" "$(printf 'ñandúes migrando' | ob_clip 7 | head -n1)"
assert_eq "UTF-8 sigue válido tras recortar" 0 "$(printf 'áéíóú ñandúes' | ob_clip 8 | python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8"); print(0)' 2>/dev/null || echo 1)"

# --- arranque: salida en TEXTO PLANO y con presupuesto ---
# El JSON armado a mano quedaba inválido en cuanto el brief traía comillas o saltos de línea
# reales (que es siempre), y Claude Code lo descartaba o mostraba el andamiaje en pantalla.
# Se mira el CAMINO ENTERO de Claude Code —el core compartido y su adaptador—, no un archivo:
# el sobre JSON existe en el paquete de Codex (su host lo pide), y lo que hay que defender es
# que no se filtre a este lado. Con los dos archivos en el mismo grep, alcanza con que aparezca
# en cualquiera de los dos para que esto se ponga en rojo.
SS_SRC="$ROOT/core/scripts/session-start-lib.sh"
grep -q 'hookSpecificOutput' "$SS_SRC" "$ROOT/scripts/session-start.sh"
assert_eq "el camino de Claude Code NO arma JSON a mano (texto plano)" 1 "$?"
grep -q 'ob_clip "$OB_MAX_TOTAL"' "$SS_SRC"
assert_eq "la salida pasa por el techo de presupuesto" 0 "$?"
# El material de síntesis pesa ~24 KB: pedirlo en cada arranque es lo que hacía que Claude Code
# truncara TODO el contexto. El hook sólo puede espiar.
grep -q 'api/synthesis?peek=1' "$SS_SRC"
assert_eq "la síntesis se consulta con ?peek=1 (no reclama ni trae el material)" 0 "$?"

# --- arranque: los curls CON EFECTO van detrás del gate de features ---
# /api/synthesis toma el candado atómico del día y /api/mentions marca resoluciones como vistas.
# Llamarlos y descartar el resultado después (como se hacía) le bloquea el día al equipo entero
# y come avisos en silencio. El gate tiene que estar en la MISMA línea del curl.
SS="$SS_SRC"
grep -q 'ob_feat_on daily-synthesis && curl .*api/synthesis' "$SS"
assert_eq "el curl a /api/synthesis va detrás de ob_feat_on" 0 "$?"
grep -q 'ob_feat_on menciones && curl .*api/mentions' "$SS"
assert_eq "el curl a /api/mentions va detrás de ob_feat_on" 0 "$?"

SAVE_BIN="$ROOT/core/bin/onebrain-save"
TMP_HOME=$(mktemp -d)
assert_eq "--title sin valor => error 2, no cuelga"  2 "$(run_limited 3 env HOME="$TMP_HOME" "$SAVE_BIN" --title)"
assert_eq "--content sin valor => error 2, no cuelga" 2 "$(run_limited 3 env HOME="$TMP_HOME" "$SAVE_BIN" --type avance --title T --content)"
assert_eq "--entities sin valor => error 2, no cuelga" 2 "$(run_limited 3 env HOME="$TMP_HOME" "$SAVE_BIN" --title T --content C --entities)"
# Un flag mal escrito perdía datos en silencio (`*) shift`): la memoria se guardaba igual, sin
# las entidades o sin el área que el modelo creía haber pasado.
assert_eq "flag desconocido => error 2 (no se traga el dato)" 2 "$(run_limited 3 env HOME="$TMP_HOME" "$SAVE_BIN" --title T --content C --entidades a,b)"
# --supersedes hereda el mismo guard: es un flag NUEVO, y el `shift 2` sin valor cuelga igual
# que colgaba en los otros cinco. Sin este caso, el bug de P.2 volvía a entrar por la puerta nueva.
assert_eq "--supersedes sin valor => error 2, no cuelga" 2 "$(run_limited 3 env HOME="$TMP_HOME" "$SAVE_BIN" --title T --content C --supersedes)"
rm -rf "$TMP_HOME"

# --- T1.3: hacer VISIBLE el retorno del cerebro (quién lo escribió y cuándo) ---------------
# Todo lo que trae el cerebro entra como additionalContext de un hook: lo consume el MODELO y
# la persona nunca ve que eso que Claude "ya sabe" lo escribió un compañero. El momento "ajá"
# del producto es justamente el cruce entre dos personas — hoy sólo pasa en la reunión de
# venta, nunca adentro del producto. Lo que no se atribuye, no se renueva.
#
# El material SÍ trae los datos: buildTeamBrief formatea cada entrada como
# "- **Título** ([[Autor]] · 24/07/2026): ..." (src/tools/brain-context.ts, fmt()). Lo que
# faltaba era pedirle a Claude que lo dijera. Estos tests corren el hook DE VERDAD contra un
# curl falso que devuelve un brief con autor, y verifican la instrucción en la salida real.
# El fake lee el body de un ARCHIVO en vez de tenerlo incrustado: el JSON pasa por un solo
# nivel de escapado en vez de tres (heredoc → printf → JSON), que es donde se cuela el bug de
# test que hace pasar un caso por el motivo equivocado.
fake_curl_brief() { # <archivo-curl-destino> <archivo-con-el-json>
  cat > "$1" <<FAKEB
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    */api/context) printf '%s\n200' "\$(cat '$2')"; exit 0 ;;
    */api/*) exit 0 ;;
  esac
done
FAKEB
  chmod +x "$1"
}
run_start_con_brief() { # <archivo-con-el-json> -> imprime la salida REAL del hook
  _fb=$(mktemp -d); fake_curl_brief "$_fb/curl" "$1"
  _hb=$(mktemp -d); mkdir -p "$_hb/.config/one-brain"
  printf 'ob_token_fake_de_test' > "$_hb/.config/one-brain/token"
  # apaga el aviso de reuniones (1×/día, independiente de todo esto) para no ensuciar la salida
  printf '{"reuniones":false}' > "$_hb/.config/one-brain/features.json"
  printf '{"session_id":"t13","source":"startup"}' \
    | HOME="$_hb" PATH="$_fb:$PATH" ONE_BRAIN_URL="http://127.0.0.1:9" sh "$ROOT/scripts/session-start.sh" 2>/dev/null
}

JSON_DIR=$(mktemp -d)
# Con autor Y con comillas dobles adentro del valor: el brief real las trae, y son lo que
# rompía el JSON armado a mano antes de P.1.
printf '{"brief":"## Decisiones vigentes\\n- **Pasamos la carga a Postgres** ([[Fran]] · 24/07/2026): la planilla no aguanta el volumen, dijo \\"no da mas\\""}' > "$JSON_DIR/con-autor.json"
OUT_T13=$(run_start_con_brief "$JSON_DIR/con-autor.json")
printf '%s' "$OUT_T13" | grep -q 'Fran'
assert_eq "T1.3: el brief con autor llega al contexto (precondición)" 0 "$?"
printf '%s' "$OUT_T13" | grep -qi 'antes de responder'
assert_eq "T1.3: pide decirlo ANTES de contestar lo primero que le pidan" 0 "$?"
printf '%s' "$OUT_T13" | grep -qi 'una .*línea'
assert_eq "T1.3: pide UNA línea (no un resumen que se coma el turno)" 0 "$?"
printf '%s' "$OUT_T13" | grep -qiE 'quién lo escribió|persona.*fecha|autor.*fecha'
assert_eq "T1.3: exige nombrar a la persona y la fecha" 0 "$?"
printf '%s' "$OUT_T13" | grep -qi 'no.*invent'
assert_eq "T1.3: prohíbe inventar la atribución" 0 "$?"
# Probado con el brief real: sin decírselo, el modelo copia la firma tal cual y le escribe
# "[[Bauti]]" a la persona. El wikilink es sintaxis interna del cerebro, no algo para leer.
printf '%s' "$OUT_T13" | grep -qi 'sin los corchetes'
assert_eq "T1.3: pide el nombre sin los corchetes del wikilink" 0 "$?"

# Un brief SIN autor (entradas cuyo users.name es null: fmt() emite sólo la fecha) NO puede
# disparar el pedido de nombrar a una persona — pedir atribución que no está en el material es
# pedirle al modelo que la invente, y una atribución falsa es peor que ninguna.
printf '{"brief":"## Ultimo movimiento del equipo\\n- **Se migro el scraper** (24/07/2026): sin firma de autor"}' > "$JSON_DIR/sin-autor.json"
OUT_T13S=$(run_start_con_brief "$JSON_DIR/sin-autor.json")
printf '%s' "$OUT_T13S" | grep -q 'scraper'
assert_eq "T1.3: el brief sin autor igual llega (precondición)" 0 "$?"
printf '%s' "$OUT_T13S" | grep -qi 'quién lo escribió'
assert_eq "T1.3: sin autor en el material, NO pide nombrar a la persona" 1 "$?"
printf '%s' "$OUT_T13S" | grep -qi 'antes de responder'
assert_eq "T1.3: sin autor igual pide decir qué trajo (y de cuándo)" 0 "$?"

# Trampa: los cuerpos de las memorias están LLENOS de wikilinks (así escribe el equipo), así que
# "el brief contiene [[" no significa "el brief está firmado". La firma que emite fmt() es
# exactamente "([[Autor]] · fecha)": si se detecta sólo por los corchetes, un brief sin autor con
# un [[link]] en el texto hace que le pidamos al modelo atribuir a una nota, no a una persona.
printf '{"brief":"## Ultimo movimiento\\n- **Se migro el scraper** (24/07/2026): ver [[playwright-cli]] y [[self-scraper]] para el detalle"}' > "$JSON_DIR/wikilink-sin-autor.json"
OUT_T13W=$(run_start_con_brief "$JSON_DIR/wikilink-sin-autor.json")
printf '%s' "$OUT_T13W" | grep -q 'playwright-cli'
assert_eq "T1.3: el brief con wikilinks en el cuerpo llega (precondición)" 0 "$?"
printf '%s' "$OUT_T13W" | grep -qi 'quién lo escribió'
assert_eq "T1.3: wikilinks en el cuerpo NO se confunden con firma de autor" 1 "$?"

# --- Aviso de update: el server lo redacta, el hook lo MUESTRA ---
# Hasta acá el aviso de "estás atrasado" vivía sólo en el banner del panel web, que la gente que
# trabaja adentro de Claude Code no abre nunca. Caso real (27-jul): sesión corriendo la 0.1.271
# con la 0.1.376 publicada, sin un solo aviso. El texto viene armado del server (campo `update`
# de /api/context) para no meter comparación de semver en bash y para poder corregirlo sin que
# nadie actualice nada; el hook solo tiene que no comérselo.
printf '{"brief":"## Algo\\n- **Una decisión** (24/07/2026): cuerpo","update":"⚠️ One Brain: esta sesión está corriendo el plugin 0.1.271 y la última publicada es 0.1.376. Actualizalo con: claude plugin marketplace update prophet && claude plugin update one-brain@prophet — y después REINICIÁ Claude Code. Mostrale este aviso al usuario."}' > "$JSON_DIR/con-update.json"
OUT_UPD=$(run_start_con_brief "$JSON_DIR/con-update.json")
printf '%s' "$OUT_UPD" | grep -q 'Una decisión'
assert_eq "update: el brief sigue llegando (precondición)" 0 "$?"
printf '%s' "$OUT_UPD" | grep -q '0.1.376'
assert_eq "update: el aviso del server llega a la salida del hook" 0 "$?"
printf '%s' "$OUT_UPD" | grep -q 'claude plugin update one-brain@prophet'
assert_eq "update: el comando llega ENTERO (con el && y la arroba)" 0 "$?"
printf '%s' "$OUT_UPD" | grep -qi 'REINICI'
assert_eq "update: dice que hay que reiniciar (sin eso, actualizar no cambia nada)" 0 "$?"

# Un cerebro al día no manda el campo: ni una línea de ruido en el arranque.
printf '{"brief":"## Algo\\n- **Una decisión** (24/07/2026): cuerpo"}' > "$JSON_DIR/sin-update.json"
OUT_NOUPD=$(run_start_con_brief "$JSON_DIR/sin-update.json")
printf '%s' "$OUT_NOUPD" | grep -qi 'claude plugin update'
assert_eq "update: sin campo update, el arranque no menciona ningún update" 1 "$?"

# Sin brief no hay nada que atribuir: la instrucción no debe aparecer (gasta presupuesto y le
# pide al modelo que anuncie algo que no recibió).
printf '{"brief":""}' > "$JSON_DIR/vacio.json"
OUT_T13N=$(run_start_con_brief "$JSON_DIR/vacio.json")
printf '%s' "$OUT_T13N" | grep -qi 'antes de responder'
assert_eq "T1.3: sin brief no se emite la instrucción" 1 "$?"

# El techo de 8000 sigue mandando DESPUÉS de sumar la instrucción (P.1: pasarse de ~9 KB hace
# que Claude Code reemplace todo por un preview de 2 KB y el contexto del equipo desaparezca).
# ~40.000 caracteres de brief con acentos, ñ y comillas escapadas, como el brief real.
awk 'BEGIN{
  printf "{\"brief\":\"";
  for(i=0;i<400;i++) printf "- **Decisión %d** ([[Fran]] · 24/07/2026): texto largo con acentos ñandúes y \\\"comillas\\\" adentro. ", i;
  printf "\"}";
}' > "$JSON_DIR/gigante.json"
OUT_T13G=$(run_start_con_brief "$JSON_DIR/gigante.json")
CHARS_T13G=$(printf '%s' "$OUT_T13G" | ob_chars)
[ "$CHARS_T13G" -le 8000 ]
assert_eq "T1.3: con brief gigante la salida sigue bajo el techo de 8000" 0 "$?"
printf '%s' "$OUT_T13G" | grep -qi 'antes de responder'
assert_eq "T1.3: con brief gigante la instrucción NO se pierde en el recorte" 0 "$?"

# El presupuesto se reparte por bloque, pero el TECHO global recorta por el final — así que el
# orden de ensamblado decide quién sobrevive cuando varios bloques grandes coinciden. Encontrado
# ejecutando el hook de verdad contra un server con el brief REAL de prod (5.431 chars) + un
# resume largo + menciones: la salida pegó el techo y se comió el aviso de "trabajo SIN GUARDAR",
# el recordatorio del canal de guardado y media orden de curl de la síntesis. El comentario del
# propio script promete que esos avisos cortos "nunca se recortan: son los que no pueden
# perderse" — la promesa no se estaba cumpliendo. Lo que puede recortarse es MATERIAL (el brief
# se vuelve a pedir en el próximo arranque); una instrucción operativa perdida no se recupera.
JSON_BIG=$(mktemp -d)
awk 'BEGIN{
  printf "{\"brief\":\"";
  for(i=0;i<200;i++) printf "- **Decisión %d** ([[Fran]] · 24/07/2026): cuerpo de la decisión con acentos ñandúes. ", i;
  printf "\", \"resume\":\"";
  for(i=0;i<200;i++) printf "Retomá donde quedaste, detalle largo del handoff número %d. ", i;
  printf "\", \"mentions\":\"";
  for(i=0;i<40;i++) printf "Fran te mencionó en el hilo %d y pidió que revises el DSN. ", i;
  printf "\", \"period_key\":\"2026-07-25\", \"hello\":\"";
  for(i=0;i<30;i++) printf "Bienvenido a One Brain, la memoria del equipo (parrafo %d). ", i;
  printf "\"}";
}' > "$JSON_BIG/todo.json"
FBB=$(mktemp -d)
cat > "$FBB/curl" <<FAKEALL
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    */api/context) printf '%s\n200' "\$(cat '$JSON_BIG/todo.json')"; exit 0 ;;
    */api/features) exit 0 ;;
    */api/*) cat '$JSON_BIG/todo.json'; exit 0 ;;
  esac
done
FAKEALL
chmod +x "$FBB/curl"
HBB=$(mktemp -d); mkdir -p "$HBB/.config/one-brain/pending"
printf 'ob_token_fake_de_test' > "$HBB/.config/one-brain/token"
TRVIEJA="$HBB/vieja.jsonl"; : > "$TRVIEJA"; touch -t 202001010000 "$TRVIEJA"
printf 'transcript=%s\ncwd=/proj\nreason=edits\n' "$TRVIEJA" > "$HBB/.config/one-brain/pending/pending-anterior"
OUT_FULL=$(printf '{"session_id":"presu","source":"startup"}' \
  | HOME="$HBB" PATH="$FBB:$PATH" ONE_BRAIN_URL="http://127.0.0.1:9" sh "$ROOT/scripts/session-start.sh" 2>/dev/null)
CHARS_FULL=$(printf '%s' "$OUT_FULL" | ob_chars)
[ "$CHARS_FULL" -le 8100 ]
assert_eq "presupuesto: el peor caso sigue acotado (techo 8000 + marca de recorte)" 0 "$?"
printf '%s' "$OUT_FULL" | grep -q 'trabajo SIN GUARDAR'
assert_eq "presupuesto: el aviso de trabajo sin guardar sobrevive al techo" 0 "$?"
printf '%s' "$OUT_FULL" | grep -q 'onebrain-save'
assert_eq "presupuesto: el canal de guardado sobrevive al techo" 0 "$?"
printf '%s' "$OUT_FULL" | grep -q 'api/synthesis$'
assert_eq "presupuesto: la orden de curl de la síntesis llega ENTERA (no cortada al medio)" 0 "$?"
printf '%s' "$OUT_FULL" | grep -qi 'antes de responder'
assert_eq "presupuesto: la instrucción de atribución sobrevive al techo" 0 "$?"
printf '%s' "$OUT_FULL" | grep -q 'Decisión 0'
assert_eq "presupuesto: el brief igual llega (lo que se recorta es material, no instrucciones)" 0 "$?"

# --- Telemetría de ENTREGA del hook --------------------------------------------------------
# La deuda decía "bytes emitidos, truncado sí/no, JSON válido sí/no". Después de P.1 la salida
# ya NO es JSON, así que el "JSON válido" no aplica; lo que importa sigue igual: poder contestar
# "¿lo que el hook emitió salió entero o se recortó?" sin adivinar. Se registra en un archivo
# local, NUNCA en stdout: stdout es el contexto que consume el modelo y no puede llevar ruido.
assert_eq "ob_chars cuenta CARACTERES, no bytes (ñandúes = 7)" 7 "$(printf 'ñandúes' | ob_chars)"
assert_eq "ob_chars de vacío = 0" 0 "$(printf '' | ob_chars)"

export HOME="$(mktemp -d)"
ob_log_delivery "sess-tel" 1234 1300 "brief" "no"
DLOG="$(ob_config_dir)/delivery.log"
[ -s "$DLOG" ]; assert_eq "telemetría: escribe el log de entrega" 0 "$?"
grep -q 'chars=1234' "$DLOG"; assert_eq "telemetría: registra los caracteres emitidos" 0 "$?"
grep -q 'bytes=1300' "$DLOG"; assert_eq "telemetría: registra los bytes emitidos" 0 "$?"
grep -q 'recortes=brief' "$DLOG"; assert_eq "telemetría: registra QUÉ bloque se recortó" 0 "$?"
grep -q 'techo=no' "$DLOG"; assert_eq "telemetría: registra si pegó el techo global" 0 "$?"
# Un log que crece sin fin en la máquina del cliente es deuda: se rota solo.
i=0; while [ "$i" -lt 450 ]; do ob_log_delivery "s$i" 10 10 "" "no"; i=$((i+1)); done
LOGLINES=$(wc -l < "$DLOG" | tr -d ' ')
[ "$LOGLINES" -le 400 ]; assert_eq "telemetría: el log se rota (no crece sin fin)" 0 "$?"

# End-to-end: el hook REAL deja la medición de lo que emitió, y no la mete en el contexto.
printf '{"brief":"brief corto sin recortes"}' > "$JSON_DIR/corto.json"
FBT=$(mktemp -d); fake_curl_brief "$FBT/curl" "$JSON_DIR/corto.json"
HBT=$(mktemp -d); mkdir -p "$HBT/.config/one-brain"
printf 'ob_token_fake_de_test' > "$HBT/.config/one-brain/token"
printf '{"reuniones":false}' > "$HBT/.config/one-brain/features.json"
OUT_TEL=$(printf '{"session_id":"tel-1","source":"startup"}' \
  | HOME="$HBT" PATH="$FBT:$PATH" ONE_BRAIN_URL="http://127.0.0.1:9" sh "$ROOT/scripts/session-start.sh" 2>/dev/null)
DLOG2="$HBT/.config/one-brain/delivery.log"
[ -s "$DLOG2" ]; assert_eq "telemetría e2e: el hook registra su entrega" 0 "$?"
grep -q 'session=tel-1' "$DLOG2"; assert_eq "telemetría e2e: la línea identifica la sesión" 0 "$?"
CHARS_REALES=$(printf '%s' "$OUT_TEL" | ob_chars)
CHARS_LOG=$(sed -n 's/.*chars=\([0-9]*\).*/\1/p' "$DLOG2" | head -n1)
# El log mide lo que el hook escribe en stdout, incluidos los DOS saltos de cierre; el
# command substitution que captura la salida acá se come los trailing newlines. De ahí los 2
# exactos de diferencia: se exige la igualdad con ese offset, no una tolerancia difusa.
assert_eq "telemetría e2e: los chars registrados son los REALMENTE emitidos" "$CHARS_LOG" "$((CHARS_REALES + 2))"
printf '%s' "$OUT_TEL" | grep -qE 'chars=|delivery\.log'
assert_eq "telemetría e2e: NO ensucia el contexto que consume el modelo" 1 "$?"

# Con un brief gigante, la telemetría tiene que decir QUÉ se recortó — es justamente el caso
# que dejaba al equipo sin contexto sin que nadie se enterara.
FBG=$(mktemp -d); fake_curl_brief "$FBG/curl" "$JSON_DIR/gigante.json"
HBG=$(mktemp -d); mkdir -p "$HBG/.config/one-brain"
printf 'ob_token_fake_de_test' > "$HBG/.config/one-brain/token"
printf '{"reuniones":false}' > "$HBG/.config/one-brain/features.json"
printf '{"session_id":"tel-2","source":"startup"}' \
  | HOME="$HBG" PATH="$FBG:$PATH" ONE_BRAIN_URL="http://127.0.0.1:9" sh "$ROOT/scripts/session-start.sh" >/dev/null 2>&1
grep -q 'recortes=.*brief' "$HBG/.config/one-brain/delivery.log"
assert_eq "telemetría: con brief gigante marca el recorte del brief" 0 "$?"

# El doctor es el único lugar donde alguien mira el estado del plugin: una telemetría que vive
# en un archivo que nadie sabe que existe no contesta nada. El chequeo traduce la última entrega.
DOC_E=$(mktemp -d); mkdir -p "$DOC_E/.config/one-brain"
assert_eq "doctor: sin telemetría todavía => aviso" "aviso" \
  "$(estado "$(env HOME="$DOC_E" sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_entrega')")"
printf '2026-07-26T14:00:00Z session=s1 chars=4200 bytes=4300 recortes=ninguno techo=no\n' > "$DOC_E/.config/one-brain/delivery.log"
assert_eq "doctor: última entrega completa => ok" "ok" \
  "$(estado "$(env HOME="$DOC_E" sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_entrega')")"
printf '2026-07-26T15:00:00Z session=s2 chars=8018 bytes=8200 recortes=resume,brief techo=si\n' >> "$DOC_E/.config/one-brain/delivery.log"
SAL_E=$(env HOME="$DOC_E" sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_entrega')
assert_eq "doctor: última entrega recortada => aviso" "aviso" "$(estado "$SAL_E")"
printf '%s' "$(detalle "$SAL_E")" | grep -q 'resume,brief'
assert_eq "doctor: el aviso nombra los bloques recortados" 0 "$?"

# --- doctor: estado de la cola de captura --------------------------------------------------
# El aviso de "quedó trabajo sin guardar" salía en TODOS los arranques y no había forma de ver
# por qué: los markers viven en un directorio que nadie sabe que existe. Sin esta línea, la
# única manera de responder "¿por qué me grita?" era leerse el código del hook.
doc_cap() { env HOME="$1" sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_captura'; }
DOC_C=$(mktemp -d); mkdir -p "$DOC_C/.config/one-brain/pending"
assert_eq "doctor: sin pendientes => ok" "ok" "$(estado "$(doc_cap "$DOC_C")")"
TRD="$DOC_C/d.jsonl"; : > "$TRD"; touch -t 202001010000 "$TRD"
printf 'transcript=%s\ncwd=/proj\nreason=edits\n' "$TRD" > "$DOC_C/.config/one-brain/pending/pending-D1"
printf 'transcript=%s\ncwd=/proj\nreason=cola\n'  "$TRD" > "$DOC_C/.config/one-brain/pending/pending-D2"
SAL_C=$(doc_cap "$DOC_C")
assert_eq "doctor: con trabajo real pendiente => aviso" "aviso" "$(estado "$SAL_C")"
printf '%s' "$(detalle "$SAL_C")" | grep -q '1'
assert_eq "doctor: cuenta sólo los que van a avisar (no la cola de cierre)" 0 "$?"

# --- Falso positivo de "trabajo sin guardar" -----------------------------------------------
# Repro con formato REAL (sacado de un transcript de verdad, ~/.claude/projects): el usuario
# escribe UN "hola" después de un /clear y ya son TRES líneas type:user+role:user sin
# tool_result — el caveat isMeta que Claude Code inyecta, el eco del /clear y el "hola". El
# contador viejo llega a u=3 y avisa "quedó trabajo sin guardar" de una sesión donde no se
# tocó un solo archivo. Medido sobre 123 transcripts reales: 10 falsos positivos, 0 falsos
# negativos. La señal correcta es el promptId (uno por turno REAL del usuario, compartido por
# todos los tool_results de ese turno), excluyendo los isMeta.
assert_eq "falso positivo: /clear + 'hola' NO es trabajo sin guardar" 0 \
  "$(ob_has_unsaved_work "$FIX/falso-positivo-hola.jsonl")"
# Mismo caso con imágenes: un solo prompt con 2 adjuntas mete 4 mensajes isMeta.
assert_eq "falso positivo: un prompt con imágenes adjuntas NO es trabajo sin guardar" 0 \
  "$(ob_has_unsaved_work "$FIX/falso-positivo-imagenes.jsonl")"
# Y del otro lado: 3 turnos REALES (3 promptId distintos) sin edits tampoco alcanzan desde que
# el umbral de charla es 12. El promptId sigue siendo la señal correcta —lo que cambió es cuánta
# charla hace falta para que valga la pena rescatarla—, así que el fixture se queda como
# regresión del parseo, con el resultado que corresponde hoy.
assert_eq "3 turnos reales del usuario (3 promptId) => ya no alcanza" 0 \
  "$(ob_has_unsaved_work "$FIX/conversational-promptid.jsonl")"
# Un turno con 20 tool_results comparte el promptId del turno: no infla el contador.
assert_eq "1 turno con muchos tool_results => 0 (el promptId es el mismo)" 0 \
  "$(ob_has_unsaved_work "$FIX/un-turno-muchos-tools.jsonl")"
# Un Edit sigue siendo trabajo sin guardar aunque haya UN solo turno.
assert_eq "1 turno con Edit => sigue siendo trabajo sin guardar" 1 \
  "$(ob_has_unsaved_work "$FIX/falso-positivo-hola-con-edit.jsonl")"

# --- Dead-letter en la cola de reintento ---------------------------------------------------
# P.2 cerró la mitad: onebrain-save ya no ENCOLA un 4xx. Pero el otro camino seguía abierto —
# ob_flush_queue reintenta lo que YA está en la cola sin mirar el código, así que un payload
# que el server rechaza (encolado antes del fix, o encolado sin token, donde nadie lo validó)
# vuelve a la cola en CADA arranque, para siempre: segundos de curl inútil por arranque y una
# memoria que la skill reporta como "pendiente, no perdida" y nunca va a entrar.
export HOME="$(mktemp -d)"
mkdir -p "$(ob_queue_dir)"
printf '{"type":"avance","title":"","content_md":"C"}' > "$(ob_queue_dir)/queued-rechazado"
FAKE_400=$(mktemp -d)
cat > "$FAKE_400/curl" <<'FAKE400'
#!/bin/sh
printf '400'
FAKE400
chmod +x "$FAKE_400/curl"
printf 'ob_token_fake_de_test' > "$(ob_config_dir)/token"
# OJO con el save/restore: `VAR=x funcion` NO es temporal cuando lo que se llama es una FUNCIÓN
# de shell — en POSIX (y en el bash 3.2 que es /bin/sh en macOS) la asignación QUEDA en el
# entorno después de que la función retorna. Sin restaurar, este curl falso se le colaba a todo
# test agregado más abajo, en silencio: lo cazó el test de caracterización de session-start.sh,
# que arrancaba sin brief ni menciones porque su curl era este stub que imprime "400".
OB_PATH_ORIG=$PATH
PATH="$FAKE_400:$PATH" ob_flush_queue
PATH=$OB_PATH_ORIG
[ -e "$(ob_queue_dir)/queued-rechazado" ]
assert_eq "dead-letter: un 400 NO vuelve a la cola de reintento" 1 "$?"
ls "$(ob_queue_dir)"/dead-* >/dev/null 2>&1
assert_eq "dead-letter: el payload rechazado se conserva (no se borra en silencio)" 0 "$?"

# Un 500 (o la red caída) SÍ tiene que volver a la cola: es transitorio, reintentar es correcto.
export HOME="$(mktemp -d)"
mkdir -p "$(ob_queue_dir)"
printf '{"type":"avance","title":"T","content_md":"C"}' > "$(ob_queue_dir)/queued-transitorio"
FAKE_500=$(mktemp -d)
cat > "$FAKE_500/curl" <<'FAKE500'
#!/bin/sh
printf '503'
FAKE500
chmod +x "$FAKE_500/curl"
printf 'ob_token_fake_de_test' > "$(ob_config_dir)/token"
OB_PATH_ORIG=$PATH
PATH="$FAKE_500:$PATH" ob_flush_queue
PATH=$OB_PATH_ORIG
[ -e "$(ob_queue_dir)/queued-transitorio" ]
assert_eq "dead-letter: un 503 SÍ vuelve a la cola (falla transitoria)" 0 "$?"
ls "$(ob_queue_dir)"/dead-* >/dev/null 2>&1
assert_eq "dead-letter: un 503 no se manda a dead-letter" 1 "$?"

# 429 es rate limit, no "tu payload está mal": reintentar es lo correcto (mismo criterio que
# onebrain-save, que encola 429 y rechaza el resto de los 4xx).
export HOME="$(mktemp -d)"
mkdir -p "$(ob_queue_dir)"
printf '{"type":"avance","title":"T","content_md":"C"}' > "$(ob_queue_dir)/queued-429"
FAKE_429=$(mktemp -d)
cat > "$FAKE_429/curl" <<'FAKE429'
#!/bin/sh
printf '429'
FAKE429
chmod +x "$FAKE_429/curl"
printf 'ob_token_fake_de_test' > "$(ob_config_dir)/token"
OB_PATH_ORIG=$PATH
PATH="$FAKE_429:$PATH" ob_flush_queue
PATH=$OB_PATH_ORIG
[ -e "$(ob_queue_dir)/queued-429" ]
assert_eq "dead-letter: un 429 vuelve a la cola (rate limit, no payload malo)" 0 "$?"

# Una memoria que quedó en dead-letter no puede desaparecer en silencio: el arranque lo dice,
# con la ruta, para que el modelo la corrija y la reguarde.
export HOME="$(mktemp -d)"
mkdir -p "$(ob_queue_dir)"
printf '{"type":"avance","title":"T","content_md":"C"}' > "$(ob_queue_dir)/dead-1"
MSG_DEAD=$(ob_dead_message)
printf '%s' "$MSG_DEAD" | grep -qi 'rechaz'
assert_eq "dead-letter: hay aviso de memoria rechazada" 0 "$?"
printf '%s' "$MSG_DEAD" | grep -q "$(ob_queue_dir)"
assert_eq "dead-letter: el aviso dice DÓNDE quedó el payload" 0 "$?"
export HOME="$(mktemp -d)"
assert_eq "dead-letter: sin dead-* no hay aviso" "" "$(ob_dead_message)"

# EL MOTIVO DEL RECHAZO SE GUARDA Y SE DICE (5-ago-2026). El tablero de uso mostró 14 guardados
# muertos en producción con "400 body inválido" —seis de Fran en 29 segundos, reintentando a
# ciegas— porque `ob_try_save` mandaba el cuerpo de la respuesta a /dev/null. Sin el motivo, el
# aviso de dead-letter tenía que adivinar qué campo estaba mal, y cada uno de esos 400 es una
# memoria perdida.
export HOME="$(mktemp -d)"
mkdir -p "$(ob_queue_dir)"
printf '{"type":"avance","title":"T","content_md":"C"}' > "$(ob_queue_dir)/queued-conmotivo"
FAKE_400B=$(mktemp -d)
cat > "$FAKE_400B/curl" <<'FAKE400B'
#!/bin/sh
printf '{"error":"No se pudo guardar, el payload está mal: content_md: se pasa del máximo de 20000 caracteres"}\n400'
FAKE400B
chmod +x "$FAKE_400B/curl"
printf 'ob_token_fake_de_test' > "$(ob_config_dir)/token"
OB_PATH_ORIG=$PATH
PATH="$FAKE_400B:$PATH" ob_flush_queue
PATH=$OB_PATH_ORIG
grep -q 'content_md' "$(ob_queue_dir)/dead-queued-conmotivo.motivo" 2>/dev/null
assert_eq "dead-letter: el motivo del rechazo queda junto al payload" 0 "$?"
MSG_MOTIVO=$(ob_dead_message)
printf '%s' "$MSG_MOTIVO" | grep -q 'content_md'
assert_eq "dead-letter: el aviso dice QUÉ campo rechazó el server" 0 "$?"
# El .motivo no es una memoria: contarlo diría "2 memorias rechazadas" cuando hay una sola.
printf '%s' "$MSG_MOTIVO" | grep -q 'rechazó 1 memoria'
assert_eq "dead-letter: el .motivo no se cuenta como memoria rechazada" 0 "$?"

# --- onebrain-token set: avisa antes de pisar el token de otro cerebro ---
# El token vive en UN archivo por máquina. Conectarse a un segundo cerebro pisaba el primero en
# silencio: la persona quedaba afuera del cerebro anterior sin enterarse, y el síntoma aparecía
# después, lejos de la causa.
TMPHOME=$(mktemp -d)
mkdir -p "$TMPHOME/.config/one-brain"
printf 'ob_viejo_123' > "$TMPHOME/.config/one-brain/token"

SALIDA=$(HOME="$TMPHOME" "$ROOT/core/bin/onebrain-token" set "ob_nuevo_456" 2>&1)
case "$SALIDA" in
  *reemplaz*) PASS=$((PASS+1)) ;;
  *) FAIL=$((FAIL+1)); printf 'FAIL: set sobre un token distinto no avisa que lo reemplaza (salida=%s)\n' "$SALIDA" ;;
esac
assert_eq "set igual pisa el token" "ob_nuevo_456" "$(cat "$TMPHOME/.config/one-brain/token")"

# Reconectar al MISMO cerebro es rutina (se rota la llave, se reinstala): no hay nada que avisar.
SALIDA=$(HOME="$TMPHOME" "$ROOT/core/bin/onebrain-token" set "ob_nuevo_456" 2>&1)
case "$SALIDA" in
  *reemplaz*) FAIL=$((FAIL+1)); printf 'FAIL: avisa de reemplazo guardando el MISMO token (salida=%s)\n' "$SALIDA" ;;
  *) PASS=$((PASS+1)) ;;
esac

# Primera conexión de la máquina: tampoco hay nada que avisar.
TMPHOME2=$(mktemp -d)
SALIDA=$(HOME="$TMPHOME2" "$ROOT/core/bin/onebrain-token" set "ob_primero" 2>&1)
case "$SALIDA" in
  *reemplaz*) FAIL=$((FAIL+1)); printf 'FAIL: avisa de reemplazo en la primera conexión (salida=%s)\n' "$SALIDA" ;;
  *) PASS=$((PASS+1)) ;;
esac
rm -rf "$TMPHOME" "$TMPHOME2"

# --- coherencia del dominio: .mcp.json y los scripts tienen que apuntar al MISMO lado ---
# El 28-jul-2026 la conexion del MCP estaba escrita fija mientras los scripts leian
# ONE_BRAIN_URL. Un cliente que seteara esa variable movia todo MENOS el MCP, o sea las tools:
# quedaba hablando con dos dominios a la vez sin ninguna senal. Ahora los dos usan la misma
# variable con el mismo default, y esto lo custodia.
DEFAULT_MCP=$(sed -n 's|.*"url": "\${ONE_BRAIN_URL:-\([^}]*\)}/api/mcp".*|\1|p' "$ROOT/.mcp.json")
case "$DEFAULT_MCP" in
  https://*) PASS=$((PASS+1)) ;;
  *) FAIL=$((FAIL+1)); printf 'FAIL: .mcp.json no usa ${ONE_BRAIN_URL:-...} en la url (leido=%s)\n' "$DEFAULT_MCP" ;;
esac
for f in core/scripts/session-start-lib.sh core/scripts/capture-lib.sh core/scripts/doctor-lib.sh core/bin/onebrain-token core/bin/onebrain-save core/bin/onebrain-constitution; do
  D=$(sed -n 's|.*ONE_BRAIN_URL:-\([^}]*\)}.*|\1|p' "$ROOT/$f" | head -1)
  assert_eq "$f usa el mismo dominio por default que .mcp.json" "$DEFAULT_MCP" "$D"
done

# --- doctor: un 403 de challenge NO es un token vencido -------------------------------------
# El 29-jul-2026 la defensa automática de Vercel bloqueó el dominio propio y TODO devolvió 403.
# El doctor lo tradujo como "el cerebro rechazó el token: pedí uno nuevo", mandando a rotar una
# llave que estaba perfecta — y rotar, con el modelo de una llave por persona, rompe la máquina
# donde esa persona ya estaba trabajando. El 403 del challenge se distingue por su cabecera.
DOC_CH=$(mktemp -d); mkdir -p "$DOC_CH/.config/one-brain"
printf 'ob_token_de_prueba' > "$DOC_CH/.config/one-brain/token"
FCH=$(mktemp -d)
cat > "$FCH/curl" <<'FAKECH'
#!/bin/sh
# Emula el desafío de Vercel: 403 + la cabecera que lo delata.
for a in "$@"; do case "$a" in -D) _next=dump ;; *) if [ "$_next" = dump ]; then
  printf 'HTTP/2 403\r\nserver: Vercel\r\nx-vercel-mitigated: challenge\r\n\r\n' > "$a"; _next=""; fi ;;
esac; done
printf '403'
FAKECH
chmod +x "$FCH/curl"
SAL_CH=$(env HOME="$DOC_CH" PATH="$FCH:$PATH" sh -c '. '"$ROOT"'/core/scripts/capture-lib.sh; . '"$ROOT"'/core/scripts/doctor-lib.sh; ob_doc_conexion')
printf '%s' "$SAL_CH" | grep -qi 'token'
assert_eq "challenge: NO dice que el token esté mal" 1 "$?"
printf '%s' "$SAL_CH" | grep -qi 'bloque\|challenge\|defensa\|protec'
assert_eq "challenge: explica que el dominio está bloqueado" 0 "$?"

# --- puentes de bin/: las rutas viejas siguen llegando al bin real del core ------------------
# Al extraer el core, plugin/bin/* dejó de tener la implementación y pasó a ser un puente que
# hace exec al bin de core/bin/. Esas rutas viejas siguen circulando: session-start.sh imprime
# "$DIR/../bin/onebrain-save" en el aviso de arranque y las sesiones YA ABIERTAS lo tienen en su
# contexto, así que un puente roto = un cliente que no puede guardar. El resto de la batería
# apunta directo al core, o sea que sin esto nadie cazaría la rotura.
# Los bins con efecto NO se ejecutan (onebrain-save escribiría en el cerebro de producción): para
# los ocho se verifica el MECANISMO de resolución leyendo el destino del propio exec; los dos
# inocuos además se corren de verdad, con HOME aislado y sin red.
PB_BINDIR=$(CDPATH= cd -- "$ROOT/bin" && pwd)
PB_COREDIR=$(CDPATH= cd -- "$ROOT/core/bin" && pwd)
for PB_B in onebrain-save onebrain-doctor onebrain-feature onebrain-token onebrain-constitution onebrain-resolve-pending onebrain-project-pull onebrain-project-push; do
  PB_PUENTE="$PB_BINDIR/$PB_B"
  [ -x "$PB_PUENTE" ]
  assert_eq "puente $PB_B: existe y es ejecutable" 0 "$?"
  # El destino sale del exec del propio puente, no de una constante del test: si alguien lo
  # reapunta a otro lado, el test lo sigue hasta donde realmente apunta.
  PB_DEST=$(sed -n 's|^exec "\([^"]*\)".*|\1|p' "$PB_PUENTE" | head -1)
  PB_DEST_ABS=$(printf '%s' "$PB_DEST" | sed 's|^[$]DIR|'"$PB_BINDIR"'|')
  [ -n "$PB_DEST" ] && [ -x "$PB_DEST_ABS" ]
  assert_eq "puente $PB_B: su exec resuelve a un ejecutable que existe" 0 "$?"
  PB_DEST_REAL=$(CDPATH= cd -- "$(dirname -- "$PB_DEST_ABS")" 2>/dev/null && pwd)
  assert_eq "puente $PB_B: resuelve al bin del core" "$PB_COREDIR/$PB_B" "$PB_DEST_REAL/$(basename -- "$PB_DEST_ABS")"
done

# Los dos inocuos, ejecutados POR LA RUTA VIEJA: si el puente no llegara al bin real, la lógica
# del bin real (su mensaje, su exit code) no tendría cómo manifestarse.
PB_HOME=$(mktemp -d)
PB_SAL=$(HOME="$PB_HOME" "$PB_BINDIR/onebrain-token" get 2>&1); PB_RC=$?
assert_eq "puente onebrain-token: ejecutado por la ruta vieja corre el bin real" "sin token" "$PB_SAL"
assert_eq "puente onebrain-token: propaga el exit code del bin real" 1 "$PB_RC"
HOME="$PB_HOME" "$PB_BINDIR/onebrain-feature" auto-capture
assert_eq "puente onebrain-feature: sin features.json => exit 0 (default ON)" 0 "$?"
mkdir -p "$PB_HOME/.config/one-brain"
printf '{"auto-capture":false}' > "$PB_HOME/.config/one-brain/features.json"
HOME="$PB_HOME" "$PB_BINDIR/onebrain-feature" auto-capture
assert_eq "puente onebrain-feature: feature en false => exit 1 (llegó al bin real)" 1 "$?"

# --- El aviso de captura degradada nombra ESTE programa ---------------------------------------
# El texto lo arma core/, que ahora hospeda dos programas, y tenía el nombre de uno solo escrito
# a mano. Del lado de Codex nombraba el programa equivocado justo en el aviso que sale cuando
# algo se rompió; del lado de acá hay CUATRO instalaciones en producción leyendo esa frase, así
# que la frase de acá se congela LITERAL. El golden no la cubre: sólo se emite cuando el parser
# del hook está roto, y en el entorno del golden anda.
#
# Se rompe el parser sin desarmar el entorno: un `jq` falso que sale con error alcanza, porque
# ob_json_field lo prueba PRIMERO y se queda con su resultado (así lo descubriría un cliente con
# un jq viejo o mal instalado, que es el caso real). Sin token a propósito: este aviso vive fuera
# del gate de token.
#
# Se compara por CONTENIDO y no por igualdad: sin token el arranque también invita a conectar
# (eb37eb7), así que el aviso degradado ya no viaja solo. Lo que importa acá sigue siendo lo
# mismo —que la frase salga LETRA POR LETRA, porque hay instalaciones en producción leyéndola—
# y eso lo garantiza el grep -F contra el texto completo: si alguien le toca una coma, rojo.
DEG_BIN=$(mktemp -d)
printf '#!/bin/sh\nexit 1\n' > "$DEG_BIN/jq"; chmod +x "$DEG_BIN/jq"
printf '#!/bin/sh\nexit 0\n' > "$DEG_BIN/curl"; chmod +x "$DEG_BIN/curl"
DEG_HOME=$(mktemp -d); mkdir -p "$DEG_HOME/.config/one-brain"
DEG_OUT=$(printf '{"session_id":"degradado","source":"startup"}' \
  | HOME="$DEG_HOME" PATH="$DEG_BIN:$PATH" ONE_BRAIN_URL="http://127.0.0.1:9" sh "$ROOT/scripts/session-start.sh" 2>/dev/null)
printf '%s' "$DEG_OUT" | grep -qF '⚠️ One Brain: la captura automática NO está operativa en este entorno — el hook no puede parsear el input de Claude Code (instalá jq o python3, o actualizá el plugin one-brain). Mientras tanto, tus avances NO se guardan solos: guardá manualmente con brain_save. Mostrale este aviso al usuario.'
assert_eq "captura degradada: el aviso sale TAL CUAL lo viene leyendo producción" 0 "$?"
# Y la contracara, que es el bug que esto vino a cerrar: el core NO puede volver a tener el
# nombre de un host escrito a mano en un texto que lee una persona. La función se llama
# ob_host_name desde 71d3560 (antes ob_client_name); este assert quedó buscando el nombre viejo
# y por eso daba rojo aunque el core estuviera resolviéndolo en un solo lugar, como debe.
grep -qE 'ob_host_name' "$ROOT/core/scripts/session-start-lib.sh"
assert_eq "el core resuelve el nombre del programa host en un solo lugar" 0 "$?"

# Caracterización de session-start.sh (corre aparte: levanta un server mock).
if sh "$DIR/session-start-test.sh" >/dev/null 2>&1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: session-start-test.sh\n'; fi

# Sincronía de core/ con las copias vendorizadas. Vive en tests/ del repo, pero hasta ahora no
# lo invocaba NADIE —ni esta batería, ni CI, ni el publish— o sea que la garantía dependía de
# que alguien se acordara. El modo de falla dominante es el más tonto y el más silencioso:
# correr sh scripts/sync-core.sh, commitear core/ y olvidarse de git add plugin/core. Desde
# acá lo agarra la batería, que es lo que la gente sí corre.
# Si estamos en el checkout del repo (hay core/ arriba), el guard TIENE que existir: que el
# archivo desaparezca no puede volver a ser un skip silencioso.
if [ -d "$REPO/core" ]; then
  if [ ! -f "$REPO/tests/core-sync-test.sh" ]; then
    FAIL=$((FAIL+1)); printf 'FAIL: falta tests/core-sync-test.sh (desapareció el guard de sincronía del core)\n'
  elif sh "$REPO/tests/core-sync-test.sh" >/dev/null 2>&1; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); printf 'FAIL: core-sync-test.sh — core/ y las copias vendorizadas difieren (corré sh scripts/sync-core.sh)\n'
  fi
fi

# La batería de core/bin/onebrain-codex-config, el bin que escribe el token en la config de
# Codex. Se engancha acá por el mismo motivo que el guard de sincronía: vive en tests/ del repo
# y si no lo llama la batería no lo corre nadie. Y el bin es de core/, así que viaja adentro de
# LOS DOS paquetes — romperlo desde el paquete de Claude Code es perfectamente posible.
# Mismo criterio que arriba: solo cuando esto corre desde el checkout del repo (hay core/
# arriba), y si el archivo desapareció eso es una falla, no un skip silencioso.
if [ -d "$REPO/core" ]; then
  if [ ! -f "$REPO/tests/codex-config-test.sh" ]; then
    FAIL=$((FAIL+1)); printf 'FAIL: falta tests/codex-config-test.sh (desapareció la batería del bin de conexión de Codex)\n'
  elif sh "$REPO/tests/codex-config-test.sh" >/dev/null 2>&1; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); printf 'FAIL: codex-config-test.sh — corrélo suelto para ver el detalle: sh tests/codex-config-test.sh\n'
  fi
fi

# La batería del hook de arranque de Codex. Se engancha acá por la misma razón que las dos de
# arriba, y por una propia: desde que el arranque se comparte, el core que corre en la máquina de
# los cuatro clientes de Claude Code es EXACTAMENTE el que prueba ese test. Uno de sus casos
# compara la salida de los dos programas: si alguien toca el core mirando sólo un lado, se pone
# en rojo acá, que es la batería que la gente sí corre.
if [ -d "$REPO/core" ]; then
  if [ ! -f "$REPO/tests/codex-session-start-test.sh" ]; then
    FAIL=$((FAIL+1)); printf 'FAIL: falta tests/codex-session-start-test.sh (desapareció la batería del arranque de Codex)\n'
  elif sh "$REPO/tests/codex-session-start-test.sh" >/dev/null 2>&1; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); printf 'FAIL: codex-session-start-test.sh — corrélo suelto para ver el detalle: sh tests/codex-session-start-test.sh\n'
  fi
fi

# La batería del aviso de trabajo sin guardar de Codex. Mismo enganche y mismo motivo: el lector
# del rollout (core/scripts/capture-codex.sh) vive en core/, así que viaja adentro del paquete de
# Claude Code y se puede romper desde acá sin querer. Es la pieza que decide si el aviso sale:
# rota de más grita cuando no corresponde —y un aviso que sale siempre se lee como decorado—,
# rota de menos deja perder trabajo en silencio.
if [ -d "$REPO/core" ]; then
  if [ ! -f "$REPO/tests/codex-guard-test.sh" ]; then
    FAIL=$((FAIL+1)); printf 'FAIL: falta tests/codex-guard-test.sh (desapareció la batería del aviso de trabajo sin guardar de Codex)\n'
  elif sh "$REPO/tests/codex-guard-test.sh" >/dev/null 2>&1; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); printf 'FAIL: codex-guard-test.sh — corrélo suelto para ver el detalle: sh tests/codex-guard-test.sh\n'
  fi
fi

# El contrato de las skills del paquete de Codex: que no le nombren a la persona un programa ni
# un comando que en Codex no existen, y que todo ejecutable que le indican al modelo exista y se
# invoque por ruta completa (acá los bins NO están en el PATH). Se engancha en esta batería por
# la misma razón que las de arriba —vive en tests/ del repo y si no la llama nadie no corre—, y
# por una propia: las cinco skills salieron de las skills de ESTE paquete, así que el error que
# previene es justamente el de copiar de acá sin adaptar. Ninguna de las dos fallas hace ruido:
# la persona recibe una instrucción que no puede seguir, o el modelo un comando que no existe.
if [ -d "$REPO/core" ]; then
  if [ ! -f "$REPO/tests/codex-skills-test.sh" ]; then
    FAIL=$((FAIL+1)); printf 'FAIL: falta tests/codex-skills-test.sh (desapareció el contrato de las skills de Codex)\n'
  elif sh "$REPO/tests/codex-skills-test.sh" >/dev/null 2>&1; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); printf 'FAIL: codex-skills-test.sh — corrélo suelto para ver el detalle: sh tests/codex-skills-test.sh\n'
  fi
fi

# El activador del auto-update escribe en ~/.claude/settings.json, que es la configuración
# global de Claude Code de otra persona. Un merge mal hecho no le rompe One Brain: le rompe
# Claude Code entero. Sus casos son casi todos "NO tocar" (settings roto, autoUpdate apagado a
# mano, sin python), así que corren aparte con HOME falso.
if [ ! -f "$DIR/autoupdate-test.sh" ]; then
  FAIL=$((FAIL+1)); printf 'FAIL: falta tests/autoupdate-test.sh\n'
elif sh "$DIR/autoupdate-test.sh" >/dev/null 2>&1; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1)); printf 'FAIL: autoupdate-test.sh — corrélo suelto para ver el detalle: sh tests/autoupdate-test.sh\n'
fi

# El RITMO del recordatorio: cada cuánto el hook Stop pide guardar. Corre aparte porque necesita
# ejecutar el hook muchas veces seguidas con HOME falso para simular una sesión larga. Lo que
# protege es la calidad del cerebro: un aviso que aparece cada tres mensajes se contesta
# guardando, y así entran cinco versiones de una idea que todavía no cerró.
if [ ! -f "$DIR/stop-guard-ritmo-test.sh" ]; then
  FAIL=$((FAIL+1)); printf 'FAIL: falta tests/stop-guard-ritmo-test.sh (desapareció la batería del ritmo de captura)\n'
elif sh "$DIR/stop-guard-ritmo-test.sh" >/dev/null 2>&1; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1)); printf 'FAIL: stop-guard-ritmo-test.sh — corrélo suelto para ver el detalle: sh tests/stop-guard-ritmo-test.sh\n'
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
