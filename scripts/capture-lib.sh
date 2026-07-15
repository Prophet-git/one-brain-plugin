#!/bin/sh
# Funciones puras de captura, compartidas por stop-guard.sh y los tests.

# ob_pending_dir: dónde viven los markers (scratch del plugin, /tmp de fallback).
ob_pending_dir() {
  printf '%s' "${CLAUDE_PLUGIN_DATA:-/tmp}"
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
