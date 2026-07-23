#!/bin/sh
# Funciones puras de captura, compartidas por stop-guard.sh y los tests.

# ob_pending_dir: dónde viven los markers (scratch del plugin, /tmp de fallback).
ob_pending_dir() {
  printf '%s' "${CLAUDE_PLUGIN_DATA:-/tmp}"
}

# ob_json_field <campo> <json>
# Extrae un campo string top-level del JSON que Claude Code pasa al hook. ROBUSTO al
# formato (compacto O pretty-printed, con o sin espacios tras los ":") y a campos gigantes
# como last_assistant_message (texto arbitrario con comillas). Un parser line-oriented
# (sed/grep) rompe con pretty-print → se elige un parser ESTRUCTURAL. Mismo patrón de
# fallback jq→python3→perl que bin/onebrain-constitution (jq casi nunca está en Windows/Git
# Bash; python3/perl sí). El sed tolerante es el último recurso. Imprime "" si el campo no está.
ob_json_field() {
  _obf="$1"; _obj="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$_obj" | jq -r --arg k "$_obf" '.[$k] // empty' 2>/dev/null
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$_obj" | python3 -c 'import json,sys
try:
    v=json.load(sys.stdin).get(sys.argv[1],"")
    sys.stdout.write(v if isinstance(v,str) else "")
except Exception:
    pass' "$_obf" 2>/dev/null
    return
  fi
  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$_obj" | ONE_BRAIN_JF="$_obf" perl -MJSON::PP -0777 -ne 'my $d=eval{decode_json($_)}; print $d->{$ENV{ONE_BRAIN_JF}}//"" if ref $d eq "HASH"' 2>/dev/null
    return
  fi
  # último recurso: sed tolerante a espacios tras los ":" (sirve para compacto y para el
  # caso pretty donde clave y valor quedan en la misma línea).
  printf '%s' "$_obj" | sed -n "s/.*\"$_obf\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n1
}

# ob_selftest: 1 si el parser de input FUNCIONA en este entorno, 0 si está roto. Lo prueba
# contra un input pretty-printed conocido (el formato real que manda Claude Code). Sirve para
# que session-start avise/reporte en el arranque si la captura automática no va a funcionar —
# en vez de descubrirlo cuando ya se perdieron memorias. Barato (en memoria, sin red).
ob_selftest() {
  _st='{
  "session_id": "SELFTEST",
  "transcript_path": "/ok/t.jsonl"
}'
  if [ "$(ob_json_field session_id "$_st")" = "SELFTEST" ] && \
     [ "$(ob_json_field transcript_path "$_st")" = "/ok/t.jsonl" ]; then
    printf '1'
  else
    printf '0'
  fi
}

# ob_has_unsaved_work <transcript_path>
# Imprime 1 si el ÚLTIMO evento relevante fue trabajo (Edit/Write/commit/deploy)
# posterior al último brain_save; 0 si no hubo trabajo o ya se guardó después.
ob_has_unsaved_work() {
  transcript="$1"
  [ -r "$transcript" ] || { printf '0'; return; }
  awk '
    /"name":"[^"]*brain_save"/                                     { w=0; next }
    /"name":"Edit"/ || /"name":"Write"/                            { w=1; next }
    /"name":"Bash"/ && (/git commit/ || /vercel --prod/ || /vercel deploy/) { w=1; next }
    END { print w+0 }
  ' "$transcript"
}
