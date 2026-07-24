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

# --- stop-guard.sh: markers pending ---
run_stop() { # <fixture> <session_id> ; usa un CLAUDE_PLUGIN_DATA temporal aislado
  TMP=$(mktemp -d)
  printf '{"transcript_path":"%s","session_id":"%s","cwd":"/tmp/proj"}' "$1" "$2" \
    | CLAUDE_PLUGIN_DATA="$TMP" sh "$ROOT/scripts/stop-guard.sh" >/dev/null 2>&1
  printf '%s' "$TMP"
}
T=$(run_stop "$FIX/work-no-save.jsonl" "s1")
[ -e "$T/pending-s1" ]; assert_eq "work-no-save crea pending" 0 "$?"
T=$(run_stop "$FIX/saved.jsonl" "s2")
[ -e "$T/pending-s2" ]; assert_eq "saved NO crea pending" 1 "$?"
T=$(run_stop "$FIX/work-after-save.jsonl" "s3")
[ -e "$T/pending-s3" ]; assert_eq "work-after-save crea pending" 0 "$?"
# pending se limpia cuando una corrida posterior ya está guardada:
TMP=$(mktemp -d)
printf '{"transcript_path":"%s","session_id":"s4","cwd":"/tmp/proj"}' "$FIX/work-no-save.jsonl" | CLAUDE_PLUGIN_DATA="$TMP" sh "$ROOT/scripts/stop-guard.sh" >/dev/null 2>&1
printf '{"transcript_path":"%s","session_id":"s4","cwd":"/tmp/proj"}' "$FIX/saved.jsonl"        | CLAUDE_PLUGIN_DATA="$TMP" sh "$ROOT/scripts/stop-guard.sh" >/dev/null 2>&1
[ -e "$TMP/pending-s4" ]; assert_eq "pending se limpia tras guardar" 1 "$?"

# --- REGRESIÓN del bug: input pretty-printed + campos falsos en last_assistant_message ---
run_stop_pretty() { # <fixture> <session_id> ; input pretty-printed con un "transcript_path"/"session_id" FALSO adentro
  TMP=$(mktemp -d)
  printf '{\n  "session_id": "%s",\n  "transcript_path": "%s",\n  "cwd": "/tmp/proj",\n  "last_assistant_message": "ojo con \\"transcript_path\\": \\"/FAKE\\" y \\"session_id\\": \\"FAKE\\" en el texto"\n}\n' "$2" "$1" \
    | CLAUDE_PLUGIN_DATA="$TMP" sh "$ROOT/scripts/stop-guard.sh" >/dev/null 2>&1
  printf '%s' "$TMP"
}
T=$(run_stop_pretty "$FIX/work-no-save.jsonl" "sp1")
[ -e "$T/pending-sp1" ];   assert_eq "pretty-print: crea pending con el session REAL" 0 "$?"
[ -e "$T/pending-FAKE" ];  assert_eq "pretty-print: NO usa el session_id falso"       1 "$?"

# --- FAIL-LOUD: input presente pero SIN session/transcript => aviso + marker degraded ---
TMP=$(mktemp -d)
OUTFL=$(printf '{"algo":"otra cosa","sin_session":true}' | CLAUDE_PLUGIN_DATA="$TMP" sh "$ROOT/scripts/stop-guard.sh" 2>/dev/null)
printf '%s' "$OUTFL" | grep -q 'NO está funcionando'; assert_eq "fail-loud: grita si no puede parsear" 0 "$?"
ls "$TMP"/degraded-* >/dev/null 2>&1;                  assert_eq "fail-loud: deja marker degraded"      0 "$?"
# input VACÍO (no llegó nada) NO debe gritar: es un caso normal, no una falla
TMP=$(mktemp -d)
OUTEMPTY=$(printf '' | CLAUDE_PLUGIN_DATA="$TMP" sh "$ROOT/scripts/stop-guard.sh" 2>/dev/null)
printf '%s' "$OUTEMPTY" | grep -q 'NO está funcionando'; assert_eq "input vacío no gatilla fail-loud" 1 "$?"

# --- skill session-capture ---
SK="$ROOT/skills/session-capture/SKILL.md"
[ -f "$SK" ]; assert_eq "skill existe" 0 "$?"
grep -q '^description:' "$SK" 2>/dev/null; assert_eq "skill tiene description" 0 "$?"
grep -q 'brain_save' "$SK" 2>/dev/null; assert_eq "skill referencia brain_save" 0 "$?"

# --- session-start.sh: fallback de pending anterior ---
run_start() { # <session_id_actual> <pending_dir>
  printf '{"session_id":"%s","source":"startup"}' "$1" \
    | CLAUDE_PLUGIN_DATA="$2" ONE_BRAIN_URL="http://127.0.0.1:9" sh "$ROOT/scripts/session-start.sh" 2>/dev/null
}
# con un pending de OTRA sesión => el output menciona la captura pendiente
TMP=$(mktemp -d); printf 'transcript=/tmp/old.jsonl\ncwd=/tmp/proj\n' > "$TMP/pending-old"
OUT=$(run_start "current" "$TMP")
printf '%s' "$OUT" | grep -q 'session-capture'; assert_eq "avisa pending anterior" 0 "$?"
[ -e "$TMP/pending-old" ]; assert_eq "consume (borra) el pending tras avisar" 1 "$?"
# sin ningún pending => no menciona captura
TMP2=$(mktemp -d)
OUT=$(run_start "current" "$TMP2")
printf '%s' "$OUT" | grep -q 'session-capture'; assert_eq "sin pending no avisa" 1 "$?"
# un pending de la MISMA sesión no se auto-levanta
TMP3=$(mktemp -d); printf 'transcript=/tmp/x.jsonl\n' > "$TMP3/pending-current"
OUT=$(run_start "current" "$TMP3")
printf '%s' "$OUT" | grep -q 'session-capture'; assert_eq "pending de misma sesión no dispara" 1 "$?"
# REGRESIÓN: con input PRETTY-PRINTED, session_id se parsea bien => el pending propio se auto-skipea
TMP4=$(mktemp -d); printf 'transcript=/tmp/x.jsonl\n' > "$TMP4/pending-cur9"
OUT=$(printf '{\n  "session_id": "cur9",\n  "source": "startup"\n}' | CLAUDE_PLUGIN_DATA="$TMP4" ONE_BRAIN_URL="http://127.0.0.1:9" sh "$ROOT/scripts/session-start.sh" 2>/dev/null)
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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
