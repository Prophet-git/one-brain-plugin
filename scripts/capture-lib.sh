#!/bin/sh
# Funciones puras de captura, compartidas por stop-guard.sh y los tests.

# ob_pending_dir: markers de captura. Carpeta ESTABLE (sobrevive reinicios). Antes usaba
# ${CLAUDE_PLUGIN_DATA:-/tmp}: /tmp se limpia al reiniciar → se perdían pendientes.
ob_pending_dir() {
  printf '%s' "$(ob_config_dir)/pending"
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

# ob_config_dir: carpeta de config estable del plugin (tokens, cola, markers).
ob_config_dir() {
  BASE="${HOME:-$USERPROFILE}"
  printf '%s' "$BASE/.config/one-brain"
}

# ob_queue_dir: cola de guardados pendientes de reintento (offline / server caído).
ob_queue_dir() {
  printf '%s' "$(ob_config_dir)/queue"
}

# ob_enqueue <payload-json>: guarda el entry destilado para reintentar en el próximo arranque.
# El nombre se genera con mktemp: crea el archivo de forma ATÓMICA (sin TOCTOU), así que
# invocaciones concurrentes (sesiones en paralelo) nunca se pisan entre sí. El contador
# secuencial anterior (while [ -e "queued-$_n" ]) era check-then-act: dos procesos podían
# calcular el mismo $_n y uno pisaba la escritura del otro (perdía la memoria en silencio).
# Fallback a $$+contador si mktemp no está (no debería pasar en Mac/Linux/Git-Bash).
ob_enqueue() {
  _q=$(ob_queue_dir); mkdir -p "$_q" 2>/dev/null
  _f=""
  if command -v mktemp >/dev/null 2>&1; then
    _f=$(mktemp "$_q/queued-XXXXXXXX" 2>/dev/null)
  fi
  if [ -z "$_f" ]; then
    _n=1; while [ -e "$_q/queued-$$-$_n" ]; do _n=$((_n+1)); done
    _f="$_q/queued-$$-$_n"
  fi
  printf '%s' "$1" > "$_f"
}

# ob_try_save <payload>: intenta guardar; 0 si OK. En prod hace el curl a /api/entry.
# --max-time 8 (no 15): consistente con las otras llamadas de red de session-start.sh,
# que ya usan ese tope para no colgar el arranque si el server está lento/caído.
ob_try_save() {
  _tf="$(ob_config_dir)/token"
  _tok=""
  [ -r "$_tf" ] && _tok=$(tr -d ' \t\r\n' < "$_tf" 2>/dev/null)
  [ -n "$_tok" ] || return 1
  _url="${ONE_BRAIN_URL:-https://one-brain-kappa.vercel.app}"
  _code=$(curl -s --max-time 8 -o /dev/null -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $_tok" -H "content-type: application/json" \
    -d "$1" "$_url/api/entry" 2>/dev/null)
  [ "$_code" = "200" ]
}

# ob_flush_queue: reintenta cada queued-*; borra el que guarda OK, conserva el que falla.
# Tope de 20 items por corrida: una cola gigante (offline por días) no debe recorrer sin fin
# ni acumular 20×8s de curls en una sola invocación — el resto queda para el próximo arranque.
# El propio caller (session-start.sh) además la corre backgroundeada para no bloquear el arranque.
#
# CLAIM-BY-RENAME: dos arranques concurrentes pueden correr ob_flush_queue sobre la MISMA cola
# (ej. dos sesiones de Claude Code abriendo casi a la vez). Antes de procesar un item, lo
# renombramos a inflight-$$-<orig> — el rename es atómico (rename(2)), así que si el otro
# proceso ya lo reclamó, nuestro `mv` falla y hacemos `continue` (no se procesa dos veces, no
# se duplica la memoria en el server). Si el guardado falla, lo volvemos a renombrar a
# queued-<orig> para reintentar en la próxima corrida. El glob del loop sigue siendo
# EXCLUSIVAMENTE "queued-*": los inflight-* de otro proceso nunca son tomados por este loop.
ob_flush_queue() {
  _q=$(ob_queue_dir); [ -d "$_q" ] || return 0

  # REAPER de inflight-* huérfanos: si el proceso que hizo el claim-by-rename murió entre el
  # mv y el ob_try_save (crash, kill -9, corte de luz), el item queda inflight-* para siempre —
  # el glob del loop de abajo solo toma "queued-*", así que nunca se reintenta. Se recuperan acá
  # los que llevan >=10min sin tocarse (ob_is_stale, mismo umbral que ob_pending_message): una
  # sesión con un flush recién en curso NO se toca (podría estar guardándose de verdad ahora
  # mismo), solo los que quedaron claramente abandonados.
  for _if in "$_q"/inflight-*; do
    [ -e "$_if" ] || continue
    if ob_is_stale "$_if"; then
      _orig=$(basename "$_if" | sed 's/^inflight-[0-9]*-//')
      mv "$_if" "$_q/$_orig" 2>/dev/null
    fi
  done

  _max=20; _n=0
  for _f in "$_q"/queued-*; do
    [ -e "$_f" ] || continue
    _n=$((_n + 1))
    [ "$_n" -gt "$_max" ] && break
    _orig=$(basename "$_f")
    _cl="$_q/inflight-$$-$_orig"
    mv "$_f" "$_cl" 2>/dev/null || continue
    if ob_try_save "$(cat "$_cl")"; then
      rm -f "$_cl" 2>/dev/null
    else
      mv "$_cl" "$_q/$_orig" 2>/dev/null
    fi
  done
}

# ob_is_stale <path>: 0 (stale/inactivo) si el archivo no se modificó en los últimos 10 min,
# o si no existe. 1 si cambió recién (sesión probablemente viva → no rescatar todavía).
ob_is_stale() {
  [ -e "$1" ] || return 0
  _now=$(date +%s 2>/dev/null) || return 0
  _mt=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || return 0
  [ $((_now - _mt)) -ge 600 ]
}

# ob_pending_message <session-actual>: si hay un pending de OTRA sesión inactiva, devuelve el
# aviso IMPERATIVO de rescate. NO borra nada (antes se borraba al avisar → se perdía el trabajo).
ob_pending_message() {
  _cur="$1"; _pd=$(ob_pending_dir); [ -d "$_pd" ] || return 0
  for _f in "$_pd"/pending-*; do
    [ -e "$_f" ] || continue
    _b=$(basename "$_f"); [ "$_b" = "pending-$_cur" ] && continue
    _tp=$(sed -n 's/^transcript=//p' "$_f" | head -n1)
    ob_is_stale "$_tp" || continue
    printf 'IMPORTANTE — quedó trabajo SIN GUARDAR de una sesión anterior (transcript: %s). Antes de seguir con lo que te pida el usuario: activá la skill session-capture, destilá ese transcript y guardalo con onebrain-save. Este aviso se repite en cada arranque hasta que se guarde.' "$_tp"
    return 0
  done
}

# ob_resolve_pending <session-id>: borra la marca de esa sesión. La skill session-capture la
# llama SOLO después de un guardado confirmado. Borra también reminded-<id> y
# unsaved-count-<id> (markers de stop-guard.sh para el ciclo de reinsistencia, ver
# ob_should_renag) — dejar solo pending-<id> dejaba esos dos como cruft huérfano de la sesión
# ya cerrada, que nunca se limpiaba.
ob_resolve_pending() {
  _pd=$(ob_pending_dir)
  rm -f "$_pd/pending-$1" "$_pd/reminded-$1" "$_pd/unsaved-count-$1" 2>/dev/null
}

# ob_should_renag <count>: 1 si toca reinsistir el recordatorio (múltiplo de 5, >0), 0 si no.
ob_should_renag() { { [ "$1" -gt 0 ] && [ $(( $1 % 5 )) -eq 0 ]; } && printf 1 || printf 0; }

# ob_token_warning <http-code>: aviso fuerte si el token está vencido/inválido (401/403).
ob_token_warning() {
  case "$1" in
    401|403) printf '⚠️ One Brain: tu token venció o no es válido (el server respondió %s). No se está guardando ni trayendo contexto: reconecta con /one-brain:connect <token>. Avisale al usuario.' "$1" ;;
  esac
}

# ob_has_unsaved_work <transcript_path>
# Imprime 1 si hay trabajo sin guardar posterior al último guardado real; 0 si no.
# Dos señales cuentan como "trabajo": (1) Edit/Write/commit/deploy (lo de siempre), y (2)
# conversación sustancial (>=3 turnos de usuario) sin editar nada — sesiones de pura
# decisión/análisis (ej. "decidamos el approach A" / "aprobado, cerralo") también generan
# memoria que vale la pena guardar, aunque no toquen el filesystem. Un guardado real
# (tool MCP brain_save, o el canal Bash bin/onebrain-save) resetea AMBOS contadores (w y u).
#
# Dos bugs de formato REAL (no sintético) corregidos acá, verificados contra transcripts reales:
# 1) CADA tool_result se loguea como {"type":"user","message":{"role":"user","content":[...
#    {"type":"tool_result",...}]}} — mismo type:user+role:user que un mensaje humano genuino.
#    Sin excluir "tool_result" del conteo de u, cualquier sesión con >=3 tool calls (Read/Grep/
#    Bash, sin ningún Edit) daba falso positivo masivo.
# 2) El reset anterior miraba /\/api\/entry/ como substring SIN ANCLAR — con solo MENCIONAR esa
#    ruta (ej. al leer este mismo archivo, o en el content de un tool_result) se marcaba trabajo
#    real como guardado (false-negative silencioso). Y el guardado real por el canal principal
#    (bin/onebrain-save, invocado como Bash) NO contiene "/api/entry" en el transcript —la URL
#    vive adentro del script, no en el command— así que el reset ni disparaba para ese canal.
#    Ahora se ancla a los dos guardados REALES: el tool MCP brain_save, y un Bash cuyo command
#    invoca onebrain-save.
# 3) La regla de (2) para el canal Bash miraba /onebrain-save/ SIN ANCLAR: cualquier Bash que
#    MENCIONARA el string (ej. `cat .../bin/onebrain-save` para inspeccionarlo) reseteaba el
#    contador como si hubiera guardado de verdad. El uso real siempre lleva al menos un flag
#    (`onebrain-save --type ...`), así que se ancla a "onebrain-save --".
ob_has_unsaved_work() {
  transcript="$1"
  [ -r "$transcript" ] || { printf '0'; return; }
  awk '
    /"name":"[^"]*brain_save"/                                     { w=0; u=0; next }
    /"name":"Bash"/ && /onebrain-save --/                          { w=0; u=0; next }
    /"name":"Edit"/ || /"name":"Write"/                            { w=1; next }
    /"name":"Bash"/ && (/git commit/ || /vercel --prod/ || /vercel deploy/) { w=1; next }
    /"type":"user"/ && /"role":"user"/ && !/"tool_result"/         { u=u+1; next }
    END { print (w==1 || u>=3) ? 1 : 0 }
  ' "$transcript"
}
