#!/bin/sh
# Dónde vive el estado local de One Brain (token, pendientes, cola, features, log).
#
# Existe porque el estado colgaba del usuario de la MÁQUINA ($HOME/.config/one-brain), y una
# persona con dos cuentas de Claude en la misma computadora terminaba con las dos leyendo la
# misma llave y escribiendo al mismo cerebro. Ahora cuelga del PERFIL: la carpeta de
# configuración del programa que hospeda la sesión.
#
# Archivo aparte de capture-lib.sh a propósito: headers.sh también necesita esta resolución y
# corre en CADA conexión del MCP, así que no puede arrastrar la librería grande.
#
# El perfil de siempre (~/.claude) resuelve a la ruta de SIEMPRE, byte a byte: esa ruta está
# escrita en el README público, en las skills y en los avisos, y hay instalaciones en
# producción que dependen de ella. Nadie migra nada.

# Una misma carpeta escrita de dos formas tiene que resolver al MISMO cajón. Acá abajo el perfil
# de siempre se reconoce comparando rutas como TEXTO ("$(ob_host_config_dir)" contra
# "$(ob_home)/.claude"), así que cualquier diferencia de escritura que no sea byte a byte manda a
# una instalación que hoy anda a un cajón nuevo bajo perfiles/ — hereda el token, pero pendientes,
# cola, features y bienvenida nacen vacíos, y nadie pidió nada de eso. Dos formas reales:
#   - la barra final: `CLAUDE_CONFIG_DIR=~/.claude/` es la misma carpeta que sin barra;
#   - los backslashes: en Windows (Git Bash/MSYS) una variable que viene del entorno de Windows
#     llega con "\", y encima basename no los reconoce como separador, así que el nombre visible
#     del perfil salía siendo la ruta entera con guiones ("C--Users-bauti--claude-prophet").
# Se normaliza en UN solo lugar y lo usan las dos puntas de la comparación.
ob_norm_path() {
  _obnp=$(printf '%s' "$1" | tr '\\' '/')
  while :; do
    case "$_obnp" in
      /|*:/) break ;;                 # la raíz "/" y una unidad pelada "C:/" se dejan como están
      */) _obnp="${_obnp%/}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$_obnp"
}

# La carpeta del usuario. En Windows (Git Bash/MSYS) HOME puede no existir y USERPROFILE viene
# con backslashes: se normalizan, porque un separador mezclado no resuelve en algunas shells.
ob_home() {
  ob_norm_path "${HOME:-$USERPROFILE}"
}

# La carpeta de configuración del programa host, por orden de confianza.
ob_host_config_dir() {
  # 1. El adaptador de cada paquete puede decirlo explícitamente (igual que OB_CLIENT).
  if [ -n "${OB_HOST_CONFIG_DIR:-}" ]; then ob_norm_path "$OB_HOST_CONFIG_DIR"; return; fi
  # 2. Claude Code, cuando la trae en el entorno.
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then ob_norm_path "$CLAUDE_CONFIG_DIR"; return; fi
  # 3. La ruta del propio script. Instalado, el paquete vive en
  #    <config>/plugins/cache/<owner>/<paquete>/<version>/..., así que la carpeta de config es
  #    todo lo que está antes de /plugins/cache/. Es la señal más confiable: no depende de que
  #    nadie exporte nada, que era justo el pedido.
  _obd=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
  case "$_obd" in
    */plugins/cache/*) ob_norm_path "${_obd%%/plugins/cache/*}"; return ;;
  esac
  # 4. No se pudo deducir (corriendo desde el repo, entorno raro): el perfil de siempre.
  printf '%s/.claude' "$(ob_home)"
}

# Nombre legible del perfil: el de la carpeta sin el punto y sin caracteres raros.
ob_profile_name() {
  basename -- "$1" | sed 's/^\.//; s/[^A-Za-z0-9_-]/-/g'
}

# Nombre de la CARPETA del cajón: el legible más 6 dígitos derivados de la ruta completa.
# El sufijo cubre un caso real aunque raro — ~/work/.claude y ~/personal/.claude tienen el
# mismo nombre y son perfiles distintos. cksum es POSIX y está en todas partes; shasum no.
ob_profile_slug() {
  _obk=$(printf '%s' "$1" | cksum | awk '{print $1}')
  printf '%s-%06d' "$(ob_profile_name "$1")" "$((_obk % 1000000))"
}

# El cajón del PERFIL, sin mirar la carpeta: el cerebro por defecto de esta Mac.
ob_state_dir_perfil() {
  _obraiz="$(ob_home)/.config/one-brain"
  _obcfg=$(ob_host_config_dir)
  if [ "$_obcfg" = "$(ob_home)/.claude" ]; then printf '%s' "$_obraiz"; return; fi
  printf '%s/perfiles/%s' "$_obraiz" "$(ob_profile_slug "$_obcfg")"
}

# El .onebrain más cercano, subiendo desde la carpeta de la sesión (OB_CWD, que los hooks sacan
# de su entrada, o PWD: el headersHelper del MCP corre parado en la carpeta de la sesión). Igual
# que .vercel/project.json: el repo dice a qué cerebro pertenece y la llave vive aparte. No mira
# la carpeta del usuario ni más arriba: un .onebrain ahí haría que TODO fuera de ese cerebro.
ob_onebrain_archivo() {
  _obd=$(ob_norm_path "${OB_CWD:-${PWD:-}}")
  _obh=$(ob_home)
  while [ -n "$_obd" ] && [ "$_obd" != "$_obh" ]; do
    [ -f "$_obd/.onebrain" ] && { printf '%s/.onebrain' "$_obd"; return 0; }
    case "$_obd" in /|*:/|.) return 0 ;; esac
    _obd=$(dirname -- "$_obd")
  done
}

# La carpeta de la sesión para quien NO la recibe: el headersHelper del MCP. Claude Code lo corre
# parado en la carpeta del PLUGIN, sin CLAUDE_PROJECT_DIR (medido el 23-nov-2026): con PWD, el MCP
# de una carpeta de El Profeta se conectaba con la llave de Prophet. En orden:
#   1. La carpeta del proceso que lanzó este script ($PPID), si es Claude Code. Va primero porque CLAUDE_PID y CLAUDE_CODE_SESSION_ID se HEREDAN: un
#      `claude -p` lanzado desde otra sesión trae los de la sesión de afuera.
#   2. Lo que anotó el arranque para CLAUDE_CODE_SESSION_ID.
#   3. La carpeta del proceso CLAUDE_PID.
#   4. PWD, como antes.
# La carpeta de un proceso sale de /proc en Linux y de lsof en Mac (~15 ms).
ob_cwd_de_proceso() { # <pid>
  case "$1" in ''|*[!0-9]*) return 0 ;; esac
  if [ -e "/proc/$1/cwd" ]; then readlink "/proc/$1/cwd" 2>/dev/null; return 0; fi
  command -v lsof >/dev/null 2>&1 || return 0
  lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1
}

# El nombre del programa de un proceso (para saber si el padre es Claude Code).
ob_nombre_de_proceso() { # <pid>
  case "$1" in ''|*[!0-9]*) return 0 ;; esac
  if [ -r "/proc/$1/comm" ]; then cat "/proc/$1/comm" 2>/dev/null; return 0; fi
  ps -o comm= -p "$1" 2>/dev/null
}

ob_cwd_de_sesion() {
  # Sólo si el padre ES Claude Code: un shell intermedio (o un `sh` que reemplazó a su subshell,
  # como hace dash) tiene otra carpeta, que no es la de la sesión.
  case "$(ob_nombre_de_proceso "${PPID:-}")" in
    *claude*)
      _obpc=$(ob_cwd_de_proceso "$PPID")
      [ -n "$_obpc" ] && { printf '%s' "$_obpc"; return 0; } ;;
  esac
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    _obsf="$(ob_state_dir_perfil)/sesiones/$CLAUDE_CODE_SESSION_ID"
    if [ -s "$_obsf" ]; then head -n 1 "$_obsf"; return 0; fi
  fi
  _obpc=$(ob_cwd_de_proceso "${CLAUDE_PID:-}")
  [ -n "$_obpc" ] && { printf '%s' "$_obpc"; return 0; }
  printf '%s' "${PWD:-}"
}

# Fija para este proceso (y sus hijos) el cerebro de la carpeta y el cajón, así no se recalculan.
ob_fijar_carpeta() {
  OB_CEREBRO_CARPETA=$(ob_cerebro_de_carpeta); [ -n "$OB_CEREBRO_CARPETA" ] || OB_CEREBRO_CARPETA=-
  export OB_CEREBRO_CARPETA
}

# El arranque anota la carpeta de su sesión para que el MCP la encuentre (ver ob_cwd_de_sesion).
# Los registros de más de 7 días se borran: una sesión no dura tanto.
ob_anotar_sesion() { # <session_id> <cwd>
  case "$1" in ''|*[!A-Za-z0-9_-]*) return 0 ;; esac
  [ -n "$2" ] || return 0
  _obsd="$(ob_state_dir_perfil)/sesiones"
  mkdir -p "$_obsd" 2>/dev/null || return 0
  printf '%s\n' "$2" > "$_obsd/$1" 2>/dev/null
  find "$_obsd" -type f -mtime +7 -delete 2>/dev/null
  return 0
}

# El team que pide la carpeta. El archivo dice "team: el-profeta" ("cerebro:" también vale, o sólo
# "el-profeta");
# las líneas que empiezan con # son comentarios. Vacío si no hay .onebrain.
ob_cerebro_de_carpeta() {
  # Calculado una vez por el arranque o por el helper del MCP (OB_CEREBRO_CARPETA, "-" = sin
  # .onebrain): esto se pregunta en cada ob_state_dir y ob_token_file, y subir carpetas con sed
  # cada vez le sumaba medio segundo al arranque (medido el 23-nov-2026).
  case "${OB_CEREBRO_CARPETA:-}" in
    -) return 0 ;;
    ?*) printf '%s' "$OB_CEREBRO_CARPETA"; return 0 ;;
  esac
  _oba=$(ob_onebrain_archivo)
  [ -n "$_oba" ] || return 0
  sed -n 's/^[[:space:]]*team[[:space:]]*:[[:space:]]*//; s/^[[:space:]]*cerebro[[:space:]]*:[[:space:]]*//; /^[[:space:]]*#/d; s/[[:space:]]*$//; /^[a-z0-9][a-z0-9_-]*$/p' "$_oba" 2>/dev/null | head -n 1
}

# La respuesta: dónde vive el estado de ESTA sesión.
#   1. ONE_BRAIN_STATE_DIR (a mano, o fijada por el arranque para toda la sesión).
#   2. .onebrain: cerebros/<nombre> adentro del cajón del perfil, con su token, su cola y sus
#      pendientes. Si el .onebrain nombra el cerebro por defecto, es el cajón de siempre.
#   3. El perfil, como siempre. Sin .onebrain nada cambia, byte a byte.
ob_state_dir() {
  if [ -n "${ONE_BRAIN_STATE_DIR:-}" ]; then printf '%s' "$ONE_BRAIN_STATE_DIR"; return; fi
  _obbase=$(ob_state_dir_perfil)
  _obcc=$(ob_cerebro_de_carpeta)
  if [ -n "$_obcc" ] && [ "$_obcc" != "$(ob_cerebro_de_token "$_obbase/token")" ]; then
    printf '%s/cerebros/%s' "$_obbase" "$_obcc"; return
  fi
  printf '%s' "$_obbase"
}

# El archivo del token de ESTA sesión. Es la ÚNICA regla: todo lo que manda algo al server
# (MCP, arranque, onebrain-save, la cola, Semana, los comandos en Node) la usa. Antes cada uno
# tenía la suya y onebrain-save ignoraba ONE_BRAIN_TOKEN_FILE: una sesión leía de un cerebro y
# guardaba en otro (23-nov-2026).
#
# Con .onebrain hay una barrera más: el token tiene que ser de ESE cerebro (el nombre va adentro
# del token, ob_<cerebro>_<hex>). Si no coincide, o no hay token, devuelve vacío y nadie manda
# nada: se cierra, nunca se cae al cerebro por defecto.
ob_token_file() {
  if [ -n "${ONE_BRAIN_TOKEN_FILE:-}" ]; then _obtf=$ONE_BRAIN_TOKEN_FILE
  else _obtf="$(ob_state_dir)/token"; fi
  _obcc=$(ob_cerebro_de_carpeta)
  if [ -n "$_obcc" ] && [ "$(ob_cerebro_de_token "$_obtf")" != "$_obcc" ]; then return 0; fi
  printf '%s' "$_obtf"
}

# El token que usaría esta Mac sin ninguna variable puesta: el del perfil, como siempre.
ob_token_file_por_defecto() {
  printf '%s/token' "$(ob_state_dir_perfil)"
}

# ¿Esta sesión usa el cerebro por defecto de la Mac? Se compara el CONTENIDO del token, no la
# ruta: dos rutas distintas con la misma llave son el mismo cerebro.
# Si la Mac no tiene llave por defecto, la de la sesión es la única: cuenta como la por defecto.
ob_cerebro_por_defecto() {
  _obtd=$(tr -d ' \t\r\n' < "$(ob_token_file_por_defecto)" 2>/dev/null)
  [ -n "$_obtd" ] || return 0
  _obta=$(tr -d ' \t\r\n' < "$(ob_token_file)" 2>/dev/null)
  [ "$_obta" = "$_obtd" ]
}

# ¿Esta sesión corre en un perfil distinto del de siempre? (para los avisos)
ob_perfil_propio() {
  [ "$(ob_state_dir_perfil)" != "$(ob_home)/.config/one-brain" ]
}

# Un perfil nuevo hereda UNA VEZ el token de la máquina, y desde ahí es suyo.
#
# Sin esto, cualquiera que ya trabaje con un perfil distinto del de siempre quedaría mudo en la
# primera actualización, sin haber pedido nada. Se hereda SÓLO el token: pendientes, features y
# bienvenida nacen vacíos porque son de ese perfil.
#
# La marca `heredado` no es decorativa: mientras exista, el arranque avisa que este perfil está
# usando el token de la máquina y cómo cambiarlo. onebrain-token set la borra.
ob_heredar_token() {
  [ -n "${ONE_BRAIN_SIN_HERENCIA:-}" ] && return 0
  _obdst=$(ob_state_dir)
  _obsrc="$(ob_home)/.config/one-brain/token"
  [ "$_obdst" = "$(ob_home)/.config/one-brain" ] && return 0   # el perfil de siempre no hereda de sí mismo
  # El cajón de un cerebro de carpeta (.onebrain) NUNCA hereda: copiarle el token de la máquina
  # sería guardar lo de El Profeta en Prophet, justo lo que .onebrain existe para impedir.
  case "$_obdst" in */cerebros/*) return 0 ;; esac
  # Barrido de temporales huérfanos de intentos anteriores (un kill/crash/disco lleno/suspensión
  # a mitad de una corrida previa deja basura bajo ".token.<pid>"). Va ANTES del "ya tiene el
  # suyo": si no, un perfil que ya heredó nunca volvería a pasar por acá y esa basura -- que
  # podía contener bytes reales del token -- quedaría en el disco para siempre, hasta que
  # alguien la borrara a mano. Silencioso: si no hay nada que barrer, rm -f no dice nada.
  rm -f "$_obdst"/.token.* 2>/dev/null
  [ -e "$_obdst/token" ] && return 0                            # ya tiene el suyo
  [ -r "$_obsrc" ] && [ -s "$_obsrc" ] || return 0              # no hay de dónde heredar
  mkdir -p "$_obdst" 2>/dev/null || return 0
  # Copia atómica Y confidencial: primero se crea el TEMPORAL VACÍO, se le ponen permisos 600, y
  # RECIÉN AHÍ se le escribe el contenido adentro -- en ese orden, el archivo nunca existe con
  # un byte del token adentro Y permisos legibles por otros usuarios al mismo tiempo. El
  # contenido se escribe con una REDIRECCIÓN (`cat fuente > temporal-que-ya-existe`), no con
  # `cp`: `cp` puede recrear el destino de cero (en APFS, incluso clonarlo con clonefile()), lo
  # que pisaría el chmod ya aplicado y reabriría la ventana de permisos por defecto: la
  # redirección abre el archivo YA EXISTENTE respetando su modo ya puesto y sólo trunca+escribe.
  #
  # Recién con el contenido completo se hace `mv` sobre el nombre final -- mismo directorio,
  # mismo filesystem, así que es rename(2), atómico. Si el proceso muere en CUALQUIER punto de
  # esta secuencia (kill, crash, disco lleno, la máquina se duerme):
  #  - antes del chmod: lo que queda es un archivo VACÍO (0 bytes) con permisos laxos -- ningún
  #    byte del token expuesto.
  #  - después del chmod, a mitad de la escritura: lo que queda es parcial pero con permisos
  #    600 -- nunca legible por otros usuarios de la máquina.
  #  - antes del mv: "token" (nombre final) nunca existe -- el guard de arriba nunca lo ve como
  #    "ya tiene el suyo", así que el próximo llamado reintenta solo (y el barrido de arriba
  #    limpia lo que haya quedado bajo el nombre temporal).
  # Si cualquier paso falla, se borra el temporal y se sale sin dejar rastro; la marca
  # `heredado` se escribe sólo después del mv exitoso.
  _obtmp="$_obdst/.token.$$"
  rm -f "$_obtmp" 2>/dev/null
  : > "$_obtmp" 2>/dev/null || { rm -f "$_obtmp" 2>/dev/null; return 0; }
  chmod 600 "$_obtmp" 2>/dev/null || { rm -f "$_obtmp" 2>/dev/null; return 0; }
  cat "$_obsrc" > "$_obtmp" 2>/dev/null || { rm -f "$_obtmp" 2>/dev/null; return 0; }
  mv "$_obtmp" "$_obdst/token" 2>/dev/null || { rm -f "$_obtmp" 2>/dev/null; return 0; }
  printf '' > "$_obdst/heredado" 2>/dev/null
}

# ¿El token de este perfil vino heredado y todavía no se reconectó?
ob_token_heredado() {
  [ -e "$(ob_state_dir)/heredado" ]
}

# El nombre del cerebro sale del TOKEN, no del server: un token es ob_<slug>_<hex> (ver
# src/lib/provision.ts). Cero red, cero deploy, funciona sin internet.
#
# Se corta por el ÚLTIMO guión bajo y no por el primero: un slug puede tener guiones bajos
# (plata_en_mano), el hex del final nunca.
ob_cerebro_de_token() {
  [ -r "$1" ] || return 0
  _obt=$(tr -d ' \t\r\n' < "$1")
  case "$_obt" in
    ob_*_*) _obt="${_obt#ob_}"; printf '%s' "${_obt%_*}" ;;
  esac
}

# La línea que abre el arranque. Vacía si no hay token: nunca inventar un nombre de cerebro.
ob_linea_cerebro() {
  _obcc=$(ob_cerebro_de_carpeta)
  if [ -n "$_obcc" ]; then
    if [ -n "$(ob_token_file)" ]; then
      printf 'One Brain · Team: %s (por .onebrain)' "$_obcc"
    else
      printf 'One Brain · ⚠️ Esta carpeta es del team %s (lo dice %s) y esta Mac no tiene su llave. No se lee ni se guarda nada en ningún team hasta conectarla: %s conectar <token>. Decíselo al usuario antes de seguir.' \
        "$_obcc" "$(ob_onebrain_archivo)" "$(ob_skill_cmd_cerebro)"
    fi
    return 0
  fi
  _obc=$(ob_cerebro_de_token "$(ob_token_file)")
  [ -n "$_obc" ] || return 0
  if ob_perfil_propio; then
    printf 'One Brain · Team: %s (perfil: %s)' "$_obc" "$(ob_profile_name "$(ob_host_config_dir)")"
  else
    printf 'One Brain · Team: %s' "$_obc"
  fi
}

# Cómo se nombra el comando de cerebros en este programa. state-dir.sh no carga capture-lib.sh
# (ob_skill_cmd vive ahí), así que se usa ése si está y si no, el ejecutable, que existe en los dos.
ob_skill_cmd_cerebro() {
  if command -v ob_skill_cmd >/dev/null 2>&1; then ob_skill_cmd cerebro; else printf 'onebrain-cerebro'; fi
}
