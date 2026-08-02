#!/bin/sh
# Funciones puras de captura, compartidas por stop-guard.sh y los tests.

# ob_host — en qué programa corre esta copia del core: "codex" | "claude".
#
# El core es UNO y se vendoriza dentro de cada paquete, así que un mensaje suyo no puede
# nombrar el comando de un programa en particular: el mismo texto lo lee gente que usa Codex y
# gente que usa el otro asistente, y el comando de barra sólo existe en uno de los dos.
#
# Se detecta por el manifest del paquete que CONTIENE a esta copia, subiendo por los padres
# desde el script que está corriendo. Sirve para los dos casos de uso sin configurar nada:
#   - un bin (`core/bin/onebrain-token`): $0 es el bin, el paquete está dos niveles arriba;
#   - una lib cargada con `.` desde un adaptador: $0 es el script del adaptador, que también
#     vive adentro del paquete.
# Deliberadamente NO depende de una variable de entorno: un bin que necesita que alguien le
# avise dónde está es un bin que en la máquina del cliente le va a mentir a la persona.
# ONE_BRAIN_HOST existe sólo para que los tests puedan pedir un host concreto.
ob_host() {
  [ -n "$ONE_BRAIN_HOST" ] && { printf '%s' "$ONE_BRAIN_HOST"; return; }
  _obh=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || _obh=$(pwd)
  while [ -n "$_obh" ]; do
    [ -d "$_obh/.codex-plugin" ] && { printf 'codex'; return; }
    [ -d "$_obh/.claude-plugin" ] && { printf 'claude'; return; }
    # Se corta cuando el padre deja de cambiar, y no comparando contra "/": es la misma guarda
    # que la gemela en project-lib.mjs. Con una ruta rara (relativa, vacía) dirname devuelve "."
    # para siempre, y un `while` que sólo mira "/" no sale nunca — un cuelgue del arranque, que
    # es el peor lugar para uno.
    _obp=$(dirname "$_obh")
    [ "$_obp" = "$_obh" ] && break
    _obh="$_obp"
  done
  # Sin manifest alrededor (el repo en desarrollo, un bin copiado suelto): el default es el
  # paquete histórico, que es donde están todos los clientes de hoy.
  printf 'claude'
}

# ob_skill_cmd <skill> — cómo se le dice a la persona que use una skill de One Brain, en el
# programa donde efectivamente está. En Claude Code hay slash commands; en Codex no existen:
# las skills se nombran `one-brain:<skill>` y se activan pidiéndolas. Mandar a tipear la forma
# equivocada no da error — deja a la persona probando un comando que el programa ignora, justo
# cuando algo ya andaba mal.
ob_skill_cmd() {
  case "$(ob_host)" in
    codex) printf 'la skill one-brain:%s' "$1" ;;
    *) printf '/one-brain:%s' "$1" ;; # ob:forma-claude
  esac
}

# ob_host_name — cómo se llama este programa cuando hay que nombrárselo a la persona.
# Fuente única del nombre: si el adaptador ya declaró cuál es ($OB_CLIENT), manda eso; si no
# —el caso de los bins, que corren sueltos— se deduce del paquete. Tener dos listas de nombres
# es cómo un texto termina diciendo "Claude Code" en una máquina que sólo tiene Codex.
ob_host_name() {
  case "${OB_CLIENT:-$(ob_host)}" in
    codex) printf 'Codex' ;;
    *)     printf 'Claude Code' ;;
  esac
}

# ob_pending_dir: markers de captura. Carpeta ESTABLE (sobrevive reinicios). Antes usaba
# ${CLAUDE_PLUGIN_DATA:-/tmp}: /tmp se limpia al reiniciar → se perdían pendientes.
ob_pending_dir() {
  printf '%s' "$(ob_config_dir)/pending"
}

# ob_clip <max> — recorta stdin a <max> CARACTERES (no bytes) y avisa que recortó.
# Por qué caracteres: cortar por bytes parte los acentos al medio y deja mojibake, en un
# producto que escribe todo en español. Misma cascada que ob_json_field (python3→perl→awk),
# y como último recurso cut -c, que en la práctica también corta por carácter con locale UTF-8.
ob_clip() {
  _obn="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys
n = int(sys.argv[1]); s = sys.stdin.read()
sys.stdout.write(s if len(s) <= n else s[:n].rstrip() + "\n[...recortado — traelo entero con brain_get, el id está arriba]")' "$_obn" 2>/dev/null
    return
  fi
  if command -v perl >/dev/null 2>&1; then
    ONE_BRAIN_CLIP="$_obn" perl -Mutf8 -CSD -0777 -ne '
      my $n = $ENV{ONE_BRAIN_CLIP};
      if (length($_) <= $n) { print $_ } else { my $t = substr($_, 0, $n); $t =~ s/\s+$//; print $t, "\n[...recortado — traelo entero con brain_get, el id está arriba]" }' 2>/dev/null
    return
  fi
  awk -v n="$_obn" '{ buf = buf $0 "\n" }
    END { if (length(buf) <= n) printf "%s", buf; else printf "%s\n[...recortado — traelo entero con brain_get, el id está arriba]", substr(buf, 1, n) }' 2>/dev/null
}

# ob_chars — cuenta los CARACTERES de stdin (no los bytes). Misma cascada y mismo motivo que
# ob_clip: en un producto que escribe todo en español, medir en bytes reporta un tamaño inflado
# (cada acento pesa 2) y no dice nada sobre lo que el modelo realmente recibe. Lo usa la
# telemetría de entrega y el chequeo del techo global.
ob_chars() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys; sys.stdout.write(str(len(sys.stdin.buffer.read().decode("utf-8","replace"))))' 2>/dev/null
    return
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -Mutf8 -CSD -0777 -ne 'print length($_)' 2>/dev/null
    return
  fi
  # último recurso: wc -m cuenta caracteres si el locale es UTF-8 (si no, cae a bytes, que
  # sigue siendo una medida útil aunque no exacta).
  wc -m 2>/dev/null | tr -d ' \n'
}

# ob_log_delivery <session> <chars> <bytes> <bloques-recortados> <techo si|no>
# Telemetría de ENTREGA del hook de arranque. Contesta la única pregunta que importa —
# "¿lo que el hook emitió salió entero o se recortó, y qué se recortó?"— sin tener que
# adivinar. Va a un archivo, NUNCA a stdout: stdout es el contexto que consume el modelo y
# meterle ruido de instrumentación es envenenar justo lo que se está midiendo.
# (La deuda original decía "JSON válido sí/no"; desde P.1 la salida es texto plano, así que
# esa columna no existe más: no hay JSON que pueda quedar inválido.)
ob_log_delivery() {
  _ld=$(ob_config_dir)
  mkdir -p "$_ld" 2>/dev/null || return 0
  _lf="$_ld/delivery.log"
  printf '%s session=%s chars=%s bytes=%s recortes=%s techo=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "${1:-desconocida}" "${2:-0}" "${3:-0}" \
    "${4:-ninguno}" "${5:-no}" >> "$_lf" 2>/dev/null
  # Rotación: este archivo vive en la máquina del cliente y nadie lo va a podar a mano. Un log
  # de diagnóstico que crece para siempre es una deuda que se paga sola.
  _ll=$(wc -l < "$_lf" 2>/dev/null | tr -d ' ')
  case "$_ll" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$_ll" -gt 400 ]; then
    tail -n 200 "$_lf" > "$_lf.tmp" 2>/dev/null && mv "$_lf.tmp" "$_lf" 2>/dev/null
  fi
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

# ob_try_save <payload>: intenta guardar. En prod hace el curl a /api/entry.
# --max-time 8 (no 15): consistente con las otras llamadas de red de session-start.sh,
# que ya usan ese tope para no colgar el arranque si el server está lento/caído.
#
# TRES resultados, no dos (dead-letter):
#   0 = guardado
#   1 = falla TRANSITORIA (sin token todavía, red caída, 5xx, 429, timeout) → reintentar
#   2 = RECHAZO permanente del server (4xx que no sea 429) → reintentarlo es condenarlo
# onebrain-save ya aplica este criterio para lo que ENTRA a la cola (A-5, tanda 0), pero lo que
# YA estaba encolado —o lo que se encoló sin token, donde ningún server lo validó— seguía
# reintentándose para siempre: segundos de curl inútil en cada arranque y una memoria que la
# skill reporta como "pendiente, no perdida" y nunca va a entrar.
ob_try_save() {
  _tf="$(ob_config_dir)/token"
  _tok=""
  [ -r "$_tf" ] && _tok=$(tr -d ' \t\r\n' < "$_tf" 2>/dev/null)
  # sin token no es un payload malo: es una instalación a medio conectar. Reintentable.
  [ -n "$_tok" ] || return 1
  _url="${ONE_BRAIN_URL:-https://onebrain.prophet.lat}"
  _code=$(curl -s --max-time 8 -o /dev/null -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $_tok" -H "content-type: application/json" \
    -d "$1" "$_url/api/entry" 2>/dev/null)
  case "$_code" in
    200) return 0 ;;
    # 429 es rate limit ("ahora no"), no "tu payload está mal": reintentar es lo correcto.
    429) return 1 ;;
    # 401/403 tampoco condenan el payload: el token venció y se puede reconectar. Reintentable
    # a propósito — tirar la memoria de alguien porque su token expiró sería lo peor posible.
    401|403) return 1 ;;
    4??) return 2 ;;
    *)   return 1 ;;
  esac
}

# ob_dead_message: aviso si quedaron memorias que el server RECHAZÓ (dead-letter). Mandarlas
# a una carpeta y no decir nada sería cambiar un bug ruidoso (reintento infinito) por uno mudo
# (memoria perdida en silencio), que es peor. El aviso trae la ruta y qué hacer, para que el
# modelo pueda corregir el payload y reguardarlo.
ob_dead_message() {
  _q=$(ob_queue_dir); [ -d "$_q" ] || return 0
  _dn=0
  for _d in "$_q"/dead-*; do
    [ -e "$_d" ] || continue
    _dn=$((_dn + 1))
  done
  [ "$_dn" -gt 0 ] || return 0
  printf 'IMPORTANTE — One Brain rechazó %s memoria(s) al intentar guardarlas (el server dijo que el payload está mal, reintentarlas no las va a hacer entrar). Quedaron guardadas como archivos dead-* en %s. Leelas, corregí lo que esté mal (título o contenido vacío, demasiado largo) y reguardalas con onebrain-save; borrá el archivo dead-* recién cuando entre. Avisale al usuario.' "$_dn" "$_q"
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
    ob_try_save "$(cat "$_cl")"
    case "$?" in
      0) rm -f "$_cl" 2>/dev/null ;;
      # DEAD-LETTER: el server rechazó el payload. Sale del ciclo de reintento pero NO se
      # borra — el contenido es de alguien y se puede corregir a mano (ob_dead_message avisa).
      2) mv "$_cl" "$_q/dead-$_orig" 2>/dev/null ;;
      *) mv "$_cl" "$_q/$_orig" 2>/dev/null ;;
    esac
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
    _sid=${_b#pending-}
    _tp=$(sed -n 's/^transcript=//p' "$_f" | head -n1)
    # El transcript se fue (retención de Claude Code, limpieza manual): no hay NADA que
    # destilar. Antes igual gritaba —ob_is_stale trata "no existe" como inactivo— y mandaba
    # a la skill contra un archivo fantasma.
    [ -n "$_tp" ] && [ -e "$_tp" ] || { ob_resolve_pending "$_sid"; continue; }
    # Sesión probablemente viva (otra ventana abierta ahora): ni avisar ni tocar sus markers.
    ob_is_stale "$_tp" || continue
    # Sólo el trabajo REAL sostiene un aviso que ordena postergar lo que pidió el usuario.
    # El resto (conversación posterior a un guardado, y los markers del formato viejo que no
    # anotan motivo) se descarta ACÁ: cuando la sesión ya murió nada más los borra, y
    # acumulados hacen que el aviso salga en todos los arranques para siempre.
    [ "$(sed -n 's/^reason=//p' "$_f" | head -n1)" = "edits" ] || { ob_resolve_pending "$_sid"; continue; }
    # TOPE DE INSISTENCIA. "Se repite en cada arranque hasta que se guarde" suena a red de
    # seguridad y funciona como lo contrario: un aviso que sale siempre se lee como decorado
    # y se ignora — incluso las veces que dice la verdad. Después de OB_PENDING_MAX_NAGS
    # arranques sin rescate, el marker se descarta; la última vez lo dice, así que nada
    # desaparece en silencio.
    _ng=$(cat "$_pd/nagged-$_sid" 2>/dev/null); [ -n "$_ng" ] || _ng=0
    _ng=$((_ng + 1))
    [ "$_ng" -gt "${OB_PENDING_MAX_NAGS:-3}" ] && { ob_resolve_pending "$_sid"; continue; }
    printf '%s' "$_ng" > "$_pd/nagged-$_sid" 2>/dev/null
    printf 'IMPORTANTE — quedó trabajo SIN GUARDAR de una sesión anterior (transcript: %s). Antes de seguir con lo que te pida el usuario: activá la skill session-capture, destilá ese transcript y guardalo con onebrain-save.' "$_tp"
    [ "$_ng" -ge "${OB_PENDING_MAX_NAGS:-3}" ] \
      && printf ' Es la última vez que aviso por este transcript: si no se rescata ahora, la marca se descarta. Decíselo al usuario.'
    return 0
  done
}

# ob_gc_pending [dias]: caduca markers que ya no le sirven a nadie. SIN esto el pending-dir
# sólo crece: cerrar Claude Code (o /clear, que abre session_id nueva) deja el marker huérfano
# para siempre — el Stop hook necesita la sesión VIVA para limpiarlo y ob_resolve_pending
# depende de que alguien lo corra a mano. Medido en una máquina real: 9 markers acumulados en
# 3 días, y el arranque siempre encontraba uno del cual quejarse.
ob_gc_pending() {
  _days=${1:-${OB_PENDING_MAX_DAYS:-7}}
  _pd=$(ob_pending_dir); [ -d "$_pd" ] || return 0
  _now=$(date +%s 2>/dev/null) || return 0
  _cut=$((_days * 86400))
  for _g in "$_pd"/*; do
    [ -f "$_g" ] || continue
    _gm=$(stat -f %m "$_g" 2>/dev/null || stat -c %Y "$_g" 2>/dev/null) || continue
    [ $((_now - _gm)) -gt "$_cut" ] && rm -f "$_g" 2>/dev/null
  done
  return 0
}

# ob_resolve_pending <session-id>: borra la marca de esa sesión. La skill session-capture la
# llama SOLO después de un guardado confirmado. Borra también reminded-<id> y
# unsaved-count-<id> (markers de stop-guard.sh para el ciclo de reinsistencia, ver
# ob_should_renag) — dejar solo pending-<id> dejaba esos dos como cruft huérfano de la sesión
# ya cerrada, que nunca se limpiaba.
ob_resolve_pending() {
  _pd=$(ob_pending_dir)
  rm -f "$_pd/pending-$1" "$_pd/reminded-$1" "$_pd/unsaved-count-$1" "$_pd/nagged-$1" 2>/dev/null
}

# ob_should_renag <count>: 1 si toca reinsistir el recordatorio (múltiplo de 5, >0), 0 si no.
ob_should_renag() { { [ "$1" -gt 0 ] && [ $(( $1 % 5 )) -eq 0 ]; } && printf 1 || printf 0; }

# ob_token_warning <http-code>: aviso fuerte si el token está vencido/inválido (401/403).
ob_token_warning() {
  case "$1" in
    401|403) printf '⚠️ One Brain: tu token venció o no es válido (el server respondió %s). No se está guardando ni trayendo contexto: reconectá con %s <token>. Avisale al usuario.' "$1" "$(ob_skill_cmd connect)" ;;
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
# 4) FALSO POSITIVO, el que hacía saltar el aviso cuando no correspondía: contar LÍNEAS
#    type:user+role:user no es contar turnos del usuario. Un solo "hola" después de un /clear
#    ya son TRES: el caveat que Claude Code inyecta (isMeta), el eco del /clear y el mensaje.
#    Un prompt con dos imágenes adjuntas mete cuatro mensajes isMeta más. Resultado: "quedó
#    trabajo sin guardar" en sesiones donde no se tocó un archivo — y el aviso que grita
#    siempre deja de significar algo. Medido sobre 123 transcripts REALES de ~/.claude/
#    projects: 10 falsos positivos (8%), cero falsos negativos.
#    La señal correcta es `promptId`: Claude Code emite uno por TURNO real del usuario, y todos
#    los mensajes derivados de ese turno (tool_results, adjuntos, inyecciones de skills) lo
#    heredan. Se cuentan promptId ÚNICOS, salteando los isMeta (los que no los escribió una
#    persona). Un transcript sin promptId (formato viejo, o sintético) cae al conteo por
#    mensaje de antes, para no quedarse ciego ante un cambio de formato.
#
# ob_unsaved_kind devuelve QUÉ quedó sin guardar; ob_has_unsaved_work es el wrapper booleano
# de siempre (contrato intacto para el recordatorio suave de stop-guard.sh).
#
# 5) La distinción edits/conversacion existe porque los dos avisos tienen costos MUY distintos.
#    El recordatorio de fin de turno es barato y puede errar por exceso. El de arranque ordena
#    "antes de seguir con lo que te pida el usuario, destilá el transcript anterior": si sale
#    cuando no corresponde, le roba el primer turno a otra tarea y —peor— enseña a ignorarlo.
#    Y sale casi siempre, porque `u>=3` se prende con la conversación posterior al guardado:
#    guardar el handoff y despedirse YA son turnos nuevos. Medido sobre los markers reales de
#    esta máquina: 8 de 9 sesiones marcadas "sin guardar" tenían guardados confirmados en su
#    propio transcript (una tenía 16). Sólo `w` (Edit/Write/commit/deploy) es trabajo que se
#    pierde de verdad si nadie lo destila; la conversación posterior al último guardado, no.
ob_has_unsaved_work() {
  [ -n "$(ob_unsaved_kind "$1")" ] && printf 1 || printf 0
}

# ob_unsaved_kind <transcript>: "edits" | "conversacion" | "" (nada sin guardar).
ob_unsaved_kind() {
  transcript="$1"
  [ -r "$transcript" ] || { printf ''; return; }
  awk -v min="${OB_UNSAVED_MIN_EDITS:-3}" '
    function turno(s) {
      # "promptId":" son 12 caracteres; la comilla de cierre, 1 más.
      if (match(s, /"promptId":"[^"]*"/)) return substr(s, RSTART + 12, RLENGTH - 13)
      return ""
    }
    /"name":"[^"]*brain_save"/                                     { w=0; u=0; split("", vistos); next }
    /"name":"Bash"/ && /onebrain-save --/                          { w=0; u=0; split("", vistos); next }
    /"name":"Edit"/ || /"name":"Write"/                            { w++; next }
    /"name":"Bash"/ && (/git commit/ || /vercel --prod/ || /vercel deploy/) { w++; next }
    /"type":"user"/ && /"role":"user"/ && !/"tool_result"/ {
      if ($0 ~ /"isMeta"[[:space:]]*:[[:space:]]*true/) next
      p = turno($0)
      if (p == "") { u = u + 1; next }
      if (!(p in vistos)) { vistos[p] = 1; u = u + 1 }
      next
    }
    END { print (w>=min) ? "edits" : (w>0 ? "cola" : (u>=3 ? "conversacion" : "")) }
  ' "$transcript"
}
