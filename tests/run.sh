#!/bin/sh
# Runner de tests del plugin. No usa dependencias externas.
# Uso: sh plugin/tests/run.sh
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/.." && pwd)
FIX="$DIR/fixtures"
. "$ROOT/scripts/capture-lib.sh"

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
assert_eq "conversación sustancial sin guardar => 1" 1 "$(ob_has_unsaved_work "$FIX/conversational.jsonl")"

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
assert_eq "401 => aviso de reconexión" "reconecta" "$(ob_token_warning 401 | grep -o reconecta | head -n1)"
assert_eq "403 => aviso de reconexión" "reconecta" "$(ob_token_warning 403 | grep -o reconecta | head -n1)"
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
printf 'transcript=/x/t.jsonl\ncwd=/x\n' > "$PD/pending-SESSABC"
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
RESB="$ROOT/bin/onebrain-resolve-pending"
[ -x "$RESB" ]; assert_eq "onebrain-resolve-pending existe y es ejecutable" 0 "$?"
export HOME="$(mktemp -d)"; PD2=$(ob_pending_dir); mkdir -p "$PD2"
printf 'transcript=/x/t.jsonl\n' > "$PD2/pending-SESSXYZ"
env HOME="$HOME" "$RESB" SESSXYZ
assert_eq "onebrain-resolve-pending borra la marca" 0 "$([ -e "$PD2/pending-SESSXYZ" ] && echo 1 || echo 0)"

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
# guardar reinicia el ciclo: el próximo turno con trabajo sin guardar vuelve a avisar en el 1º
printf '{"transcript_path":"%s","session_id":"s-renag","cwd":"/tmp/proj"}' "$FIX/saved.jsonl" \
  | HOME="$TMPR" sh "$ROOT/scripts/stop-guard.sh" >/dev/null 2>&1
OUT6=$(run_stop_turn "$TMPR")
printf '%s' "$OUT6" | grep -q 'Hay trabajo en esta sesión'; assert_eq "renag: tras guardar, reinicia y avisa en el turno 1" 0 "$?"

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
# y si además no hay ningún otro aviso (pending/reuniones), el early-exit sigue vivo: NADA de output
assert_eq "SIN token y sin nada pendiente: session-start no emite additionalContext" "" "$OUTNOTOK"

# con un pending de OTRA sesión => el output menciona la captura pendiente
TMP=$(mktemp -d); mkdir -p "$TMP/.config/one-brain/pending"
printf 'transcript=/tmp/old.jsonl\ncwd=/tmp/proj\n' > "$(pend_path "$TMP" old)"
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
FEAT="$ROOT/bin/onebrain-feature"
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
. "$ROOT/scripts/doctor-lib.sh"
estado() { printf '%s' "$1" | cut -d'|' -f2; }

DOC_HOME=$(mktemp -d)
mkdir -p "$DOC_HOME/.config/one-brain"

# sin token
assert_eq "doctor: sin token => falla" "falla" \
  "$(estado "$(env ONE_BRAIN_TOKEN_FILE="$DOC_HOME/.config/one-brain/token" sh -c '. '"$ROOT"'/scripts/doctor-lib.sh; ob_doc_token')")"

# token corto (pegado a medias)
printf 'ob_123' > "$DOC_HOME/.config/one-brain/token"
assert_eq "doctor: token truncado => falla" "falla" \
  "$(estado "$(env ONE_BRAIN_TOKEN_FILE="$DOC_HOME/.config/one-brain/token" sh -c '. '"$ROOT"'/scripts/doctor-lib.sh; ob_doc_token')")"

# token válido
printf 'ob_una_clave_larga_de_verdad_1234567890' > "$DOC_HOME/.config/one-brain/token"
assert_eq "doctor: token presente => ok" "ok" \
  "$(estado "$(env ONE_BRAIN_TOKEN_FILE="$DOC_HOME/.config/one-brain/token" sh -c '. '"$ROOT"'/scripts/doctor-lib.sh; ob_doc_token')")"

# hooks apagados a nivel Claude Code
printf '{"disableAllHooks": true}' > "$DOC_HOME/settings.json"
assert_eq "doctor: disableAllHooks => falla" "falla" \
  "$(estado "$(env CLAUDE_SETTINGS_FILE="$DOC_HOME/settings.json" sh -c '. '"$ROOT"'/scripts/capture-lib.sh; . '"$ROOT"'/scripts/doctor-lib.sh; ob_doc_hooks_activos')")"
printf '{"model": "opus"}' > "$DOC_HOME/settings.json"
assert_eq "doctor: hooks habilitados => ok" "ok" \
  "$(estado "$(env CLAUDE_SETTINGS_FILE="$DOC_HOME/settings.json" sh -c '. '"$ROOT"'/scripts/capture-lib.sh; . '"$ROOT"'/scripts/doctor-lib.sh; ob_doc_hooks_activos')")"

# carpeta de trabajo sin CLAUDE.md
mkdir -p "$DOC_HOME/one-brain"
assert_eq "doctor: carpeta sin CLAUDE.md => aviso" "aviso" \
  "$(estado "$(env ONE_BRAIN_DIR="$DOC_HOME/one-brain" sh -c '. '"$ROOT"'/scripts/doctor-lib.sh; ob_doc_carpeta')")"
printf '# reglas' > "$DOC_HOME/one-brain/CLAUDE.md"
assert_eq "doctor: carpeta con CLAUDE.md => ok" "ok" \
  "$(estado "$(env ONE_BRAIN_DIR="$DOC_HOME/one-brain" sh -c '. '"$ROOT"'/scripts/doctor-lib.sh; ob_doc_carpeta')")"

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
  env CLAUDE_PLUGINS_FILE="${2-$V_PLUGINS}" sh -c '. '"$ROOT"'/scripts/doctor-lib.sh; ob_doc_version "$1"' _ "$1"
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
DOC="$ROOT/bin/onebrain-doctor"
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
grep -q -- '--max-time 8' "$ROOT/scripts/capture-lib.sh"
assert_eq "ob_try_save usa --max-time 8 (no 15)" 0 "$?"

# --- session-start.sh: el flush de la cola corre BACKGROUNDEADO (no bloquea el arranque) ---
grep -qE '^\( *ob_flush_queue\b.*& *\)' "$ROOT/scripts/session-start.sh"
assert_eq "session-start.sh backgroundea ob_flush_queue" 0 "$?"

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
SAVEBIN="$ROOT/bin/onebrain-save"
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
. "$ROOT/scripts/capture-lib.sh"

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
assert_eq "no parte los acentos"         "ñandúes" "$(printf 'ñandúes migrando' | ob_clip 7 | head -n1)"
assert_eq "UTF-8 sigue válido tras recortar" 0 "$(printf 'áéíóú ñandúes' | ob_clip 8 | python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8"); print(0)' 2>/dev/null || echo 1)"

# --- session-start.sh: salida en TEXTO PLANO y con presupuesto ---
# El JSON armado a mano quedaba inválido en cuanto el brief traía comillas o saltos de línea
# reales (que es siempre), y Claude Code lo descartaba o mostraba el andamiaje en pantalla.
SS_SRC="$ROOT/scripts/session-start.sh"
grep -q 'hookSpecificOutput' "$SS_SRC"
assert_eq "el hook NO arma JSON a mano (texto plano)" 1 "$?"
grep -q 'ob_clip "$OB_MAX_TOTAL"' "$SS_SRC"
assert_eq "la salida pasa por el techo de presupuesto" 0 "$?"
# El material de síntesis pesa ~24 KB: pedirlo en cada arranque es lo que hacía que Claude Code
# truncara TODO el contexto. El hook sólo puede espiar.
grep -q 'api/synthesis?peek=1' "$SS_SRC"
assert_eq "la síntesis se consulta con ?peek=1 (no reclama ni trae el material)" 0 "$?"

# --- session-start.sh: los curls CON EFECTO van detrás del gate de features ---
# /api/synthesis toma el candado atómico del día y /api/mentions marca resoluciones como vistas.
# Llamarlos y descartar el resultado después (como se hacía) le bloquea el día al equipo entero
# y come avisos en silencio. El gate tiene que estar en la MISMA línea del curl.
SS="$ROOT/scripts/session-start.sh"
grep -q 'feat_on daily-synthesis && curl .*api/synthesis' "$SS"
assert_eq "el curl a /api/synthesis va detrás de feat_on" 0 "$?"
grep -q 'feat_on menciones && curl .*api/mentions' "$SS"
assert_eq "el curl a /api/mentions va detrás de feat_on" 0 "$?"

SAVE_BIN="$ROOT/bin/onebrain-save"
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
printf 'transcript=/tmp/vieja.jsonl\ncwd=/proj\n' > "$HBB/.config/one-brain/pending/pending-anterior"
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
  "$(estado "$(env HOME="$DOC_E" sh -c '. '"$ROOT"'/scripts/capture-lib.sh; . '"$ROOT"'/scripts/doctor-lib.sh; ob_doc_entrega')")"
printf '2026-07-26T14:00:00Z session=s1 chars=4200 bytes=4300 recortes=ninguno techo=no\n' > "$DOC_E/.config/one-brain/delivery.log"
assert_eq "doctor: última entrega completa => ok" "ok" \
  "$(estado "$(env HOME="$DOC_E" sh -c '. '"$ROOT"'/scripts/capture-lib.sh; . '"$ROOT"'/scripts/doctor-lib.sh; ob_doc_entrega')")"
printf '2026-07-26T15:00:00Z session=s2 chars=8018 bytes=8200 recortes=resume,brief techo=si\n' >> "$DOC_E/.config/one-brain/delivery.log"
SAL_E=$(env HOME="$DOC_E" sh -c '. '"$ROOT"'/scripts/capture-lib.sh; . '"$ROOT"'/scripts/doctor-lib.sh; ob_doc_entrega')
assert_eq "doctor: última entrega recortada => aviso" "aviso" "$(estado "$SAL_E")"
printf '%s' "$(detalle "$SAL_E")" | grep -q 'resume,brief'
assert_eq "doctor: el aviso nombra los bloques recortados" 0 "$?"

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
# Y lo que SÍ tiene que seguir avisando: 3 turnos REALES (3 promptId distintos), sin edits.
assert_eq "3 turnos reales del usuario (3 promptId) => sigue avisando" 1 \
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
PATH="$FAKE_400:$PATH" ob_flush_queue
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
PATH="$FAKE_500:$PATH" ob_flush_queue
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
PATH="$FAKE_429:$PATH" ob_flush_queue
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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
