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

# --- skill doctor ---
DTK="$ROOT/skills/doctor/SKILL.md"
[ -f "$DTK" ]; assert_eq "skill doctor existe" 0 "$?"
grep -q '^name:' "$DTK" 2>/dev/null; assert_eq "doctor tiene name" 0 "$?"
grep -q 'onebrain-doctor' "$DTK" 2>/dev/null; assert_eq "doctor invoca el ejecutable" 0 "$?"

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
rm -rf "$TMP_HOME"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
