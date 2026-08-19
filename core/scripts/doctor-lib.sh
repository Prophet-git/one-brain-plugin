#!/bin/sh
# Chequeos del doctor de One Brain. Viven en una lib aparte (no en el ejecutable) para poder
# testearlos uno por uno sin correr el diagnóstico entero.
#
# Cada chequeo imprime UNA línea: "<clave>|<estado>|<detalle>", con estado ok | falla | aviso.
# El formato es fijo a propósito: el ejecutable lo imprime como reporte y la skill lo lee para
# explicarle al usuario qué hacer. Ningún chequeo modifica nada — el doctor diagnostica.

ob_doc_token_file() { printf '%s' "${ONE_BRAIN_TOKEN_FILE:-$(ob_state_dir)/token}"; }

# ¿Hay token guardado y legible? Nunca imprime el token: solo su presencia y longitud.
ob_doc_token() {
  f=$(ob_doc_token_file)
  if [ ! -e "$f" ]; then
    printf 'token|falla|no hay token en %s — conectá con %s <token>\n' "$f" "$(ob_skill_cmd connect)"; return
  fi
  if [ ! -r "$f" ]; then
    printf 'token|falla|el archivo %s existe pero no se puede leer (permisos)\n' "$f"; return
  fi
  n=$(tr -d ' \t\r\n' < "$f" | wc -c | tr -d ' ')
  if [ "$n" -lt 10 ]; then
    printf 'token|falla|el token guardado está vacío o truncado (%s caracteres)\n' "$n"; return
  fi
  printf 'token|ok|token guardado (%s caracteres)\n' "$n"
}

# ¿Las herramientas que usan los hooks están? curl es obligatorio; jq es opcional (hay fallback).
ob_doc_dependencias() {
  if command -v curl >/dev/null 2>&1; then
    printf 'curl|ok|disponible\n'
  else
    printf 'curl|falla|no está instalado: sin curl el plugin no puede hablar con el cerebro\n'
  fi
}

# ¿El parser del input de los hooks funciona en ESTE entorno? Es el bug que hizo que la captura
# fallara en silencio cuando Claude Code pasó a mandar el JSON pretty-printed.
ob_doc_parser() {
  if [ "$(ob_selftest)" = "1" ]; then
    printf 'parser|ok|el hook puede leer el input de %s\n' "$(ob_host_name)"
  else
    printf 'parser|falla|el hook NO puede leer el input en este entorno: la captura automática no va a andar\n'
  fi
}

# ¿Los avisos del plugin pueden correr en esta máquina? Cada programa lo apaga a su manera, y
# las dos formas dejan al producto mudo sin una sola señal visible. Preguntar por la del OTRO
# programa no es inofensivo: devuelve `ok` sin haber mirado nada, o sea que tranquiliza sobre
# justo lo que estaba fallando.
ob_doc_hooks_activos() {
  if [ "$(ob_host)" = "codex" ]; then ob_doc_hooks_codex; else ob_doc_hooks_claude; fi
}

# Claude Code: la perilla `disableAllHooks`. Con eso en true el plugin queda mudo aunque todo lo
# demás esté perfecto.
ob_doc_hooks_claude() {
  s="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
  if [ -r "$s" ] && grep -q '"disableAllHooks"[[:space:]]*:[[:space:]]*true' "$s" 2>/dev/null; then
    printf 'hooks|falla|disableAllHooks está en true en %s: el plugin no captura nada\n' "$s"
  else
    printf 'hooks|ok|los hooks de Claude Code están habilitados\n'
  fi
}

# Codex: la CONFIANZA. Un aviso recién instalado nace sin aprobar y no se ejecuta, aunque el
# plugin figure instalado y activo (medido con codex 0.136; el flag para saltearlo no funciona).
# Y como la aprobación está atada al contenido exacto del hooks.json, cada actualización nuestra
# que lo toque vuelve a pedirla: es el modo de falla más común de este programa y el más mudo.
#
# El chequeo es deliberadamente laxo —busca que exista algún estado de hooks aprobado para
# one-brain— y ante la duda avisa en vez de fallar: la forma exacta de la clave la elige Codex,
# y preferimos una línea que diga "revisá esto" a uno que declare rota una instalación sana.
ob_doc_hooks_codex() {
  c="${CODEX_CONFIG_FILE:-${CODEX_HOME:-$HOME/.codex}/config.toml}"
  if [ ! -r "$c" ]; then
    printf 'hooks|aviso|no encontré la configuración de Codex en %s: si al arrancar no ves el contexto de tu equipo, reiniciá Codex y aprobá los avisos de One Brain cuando te los pregunte\n' "$c"
    return
  fi
  if grep -q 'hooks\.state' "$c" 2>/dev/null && grep -qi 'one-brain' "$c" 2>/dev/null; then
    printf 'hooks|ok|los avisos de One Brain están aprobados en %s\n' "$c"
  else
    printf 'hooks|aviso|no figura que hayas aprobado los avisos de One Brain en %s. Sin esa aprobación no se ejecutan (aunque el plugin figure instalado): reiniciá Codex y aceptá cuando te los pregunte. Vuelve a preguntarte después de cada actualización que los toque\n' "$c"
  fi
}

# ¿Un CLAUDE.md tiene adentro las reglas de One Brain? Se buscan las TOOLS, no el nombre del
# producto: "One Brain" puede aparecer de pasada en cualquier archivo, pero un CLAUDE.md que
# nombra brain_context y brain_save es el que efectivamente hace que Claude use el cerebro.
# Las escriben los dos caminos de alta (el heredoc de public/setup.sh y REGLAS_ONE_BRAIN).
ob_doc_reglas_en() { # <archivo>
  [ -r "$1" ] || return 1
  grep -q 'brain_context' "$1" 2>/dev/null || return 1
  grep -q 'brain_save' "$1" 2>/dev/null || return 1
  return 0
}

# Cómo se llama, en ESTE programa, el archivo donde viven las reglas de la carpeta. Los dos
# cargan el del directorio donde se abrió y también los de arriba, pero con distinto nombre:
# preguntar por el del otro programa reporta como problema una instalación sana, y encima manda
# a crear un archivo que ahí no hace nada.
ob_doc_reglas_archivo() {
  if [ "$(ob_host)" = "codex" ]; then printf 'AGENTS.md'; else printf 'CLAUDE.md'; fi
}

# El archivo de reglas con las de One Brain más cercano al directorio donde se está trabajando,
# subiendo por los padres. Un cerebro configurado en la carpeta madre igual aplica.
# Imprime la ruta y sale 0; si no hay ninguno, no imprime nada y sale 1.
ob_doc_claudemd_cerca() { # [directorio inicial; default el actual]
  # `pwd` (builtin) y no $PWD: el hook puede haber sido invocado con un PWD heredado que ya no
  # es el directorio real, y acá el directorio real es justamente el dato.
  ob_d=${1:-$(pwd)}
  ob_arch=$(ob_doc_reglas_archivo)
  case "$ob_d" in /*) ;; *) ob_d=$(pwd) ;; esac
  while :; do
    if ob_doc_reglas_en "$ob_d/$ob_arch"; then printf '%s/%s' "$ob_d" "$ob_arch"; return 0; fi
    [ "$ob_d" = "/" ] && break
    ob_d=$(dirname "$ob_d")
  done
  return 1
}

# ¿Hay un CLAUDE.md con las reglas de One Brain donde esta persona trabaja? Sin él, Claude no
# sabe que tiene que usar el cerebro y el usuario cree que el producto "no hace nada".
#
# El alta tiene DOS caminos y sólo uno usa la carpeta fija: quien se dio de alta por la terminal
# corrió setup.sh, que crea `Documents/one-brain` y le escribe el CLAUDE.md adentro; quien se dio
# de alta desde la app eligió SU carpeta y ahí Claude le escribió las mismas reglas. Mirando sólo
# la carpeta fija, a esta segunda persona el chequeo le daba "no existe" para siempre — una
# instalación perfectamente sana reportada como problema, y encima con un arreglo (`curl | bash`)
# que justamente no puede correr. Por eso se mira PRIMERO dónde está parada la sesión.
ob_doc_carpeta() {
  d="${ONE_BRAIN_DIR:-$HOME/Documents/one-brain}"
  arch=$(ob_doc_reglas_archivo)
  if aqui=$(ob_doc_claudemd_cerca); then
    printf 'carpeta|ok|las reglas de One Brain están en %s\n' "$aqui"; return
  fi
  if [ -r "$d/$arch" ]; then
    printf 'carpeta|ok|%s con su %s\n' "$d" "$arch"; return
  fi
  if [ -d "$d" ]; then
    printf 'carpeta|aviso|%s existe pero no tiene %s, y en esta carpeta tampoco hay reglas de One Brain\n' "$d" "$arch"
    return
  fi
  printf 'carpeta|aviso|no hay un %s con las reglas de One Brain en esta carpeta (ni en %s)\n' "$arch" "$d"
}

# ¿El cerebro responde con este token? Un tools/list contra el endpoint MCP.
ob_doc_conexion() {
  f=$(ob_doc_token_file)
  url="${ONE_BRAIN_URL:-https://onebrain.prophet.lat}"
  if [ ! -r "$f" ] || [ ! -s "$f" ]; then
    printf 'conexion|falla|sin token no se puede probar la conexión\n'; return
  fi
  command -v curl >/dev/null 2>&1 || { printf 'conexion|falla|sin curl no se puede probar\n'; return; }
  tok=$(tr -d ' \t\r\n' < "$f")
  # Se guardan las CABECERAS además del código: sin ellas, un 403 del token inválido y un 403
  # del bloqueo del dominio se ven idénticos, y el diagnóstico mandaba a rotar la llave en los
  # dos casos. Rotar una llave sana no es gratis: con una llave por persona, rompe la máquina
  # donde ya estaba trabajando. Pasó el 29-jul-2026.
  hdrs=$(mktemp 2>/dev/null || printf '/tmp/ob-doc-hdrs.%s' "$$")
  # Mismo endpoint que usa `onebrain-token verify`: /api/mcp (no /mcp).
  code=$(curl -s -o /dev/null -D "$hdrs" -w '%{http_code}' --max-time 12 -X POST "$url/api/mcp" \
    -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' 2>/dev/null)
  desafiado=0
  grep -qi 'x-vercel-mitigated' "$hdrs" 2>/dev/null && desafiado=1
  rm -f "$hdrs" 2>/dev/null
  # El bloqueo del dominio se contesta ANTES que el código: es un 403 que no habla del token.
  if [ "$desafiado" = "1" ]; then
    printf 'conexion|falla|el dominio %s está bloqueado por la protección anti-bots de Vercel, no es tu llave (tu llave está bien, no la cambies). Suele soltarse solo en unos minutos; mientras tanto podés trabajar con ONE_BRAIN_URL=https://one-brain-kappa.vercel.app, y si no cede se apaga a mano en Vercel → proyecto one-brain → Firewall → Attack Challenge Mode\n' "$url"
    return
  fi
  case "$code" in
    200) printf 'conexion|ok|el cerebro responde en %s\n' "$url" ;;
    401|403) printf 'conexion|falla|el cerebro rechazó el token (HTTP %s): pedí uno nuevo y conectá con %s\n' "$code" "$(ob_skill_cmd connect)" ;;
    000) printf 'conexion|falla|no hubo respuesta (sin red, VPN o el server caído)\n' ;;
    *) printf 'conexion|falla|el cerebro respondió HTTP %s\n' "$code" ;;
  esac
}

# ¿La versión que está corriendo es la instalada? Cuando el plugin se actualiza con Claude Code
# abierto, la versión vieja queda huérfana pero el PATH de la sesión sigue apuntando a su bin/.
# Mirando el plugin.json del directorio propio, el doctor reporta la vieja: el usuario actualiza,
# corre el doctor, ve la de antes y cree que el update falló. Y no es solo cosmético — los
# binarios nuevos tampoco están en ese PATH. La verdad la tiene el registro de Claude Code.
ob_doc_plugins_file() {
  printf '%s' "${CLAUDE_PLUGINS_FILE:-$HOME/.claude/plugins/installed_plugins.json}"
}

# Versión declarada por el plugin.json de un directorio dado.
ob_doc_version_dir() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$1/.claude-plugin/plugin.json" 2>/dev/null | head -n1
}

# Versión que Claude Code tiene registrada como instalada. Vacío si no hay registro (otro
# instalador, o el archivo todavía no existe): en ese caso no inventamos nada.
ob_doc_version_instalada() {
  ob_pf=$(ob_doc_plugins_file)
  [ -r "$ob_pf" ] || return 0
  # Un campo por registro (RS=","), y recién después del bloque de one-brain: el JSON trae un
  # "version" propio arriba de todo y uno por cada plugin instalado.
  awk 'BEGIN{RS=","}
       /"one-brain@prophet"/ {f=1}
       f && /"version"[[:space:]]*:[[:space:]]*"/ {
         sub(/.*"version"[[:space:]]*:[[:space:]]*"/,""); sub(/".*/,""); print; exit }' \
    "$ob_pf" 2>/dev/null
}

ob_doc_version() { # <root del plugin que se está ejecutando>
  ob_corre=$(ob_doc_version_dir "$1")
  # El registro de versión instalada es de Claude Code. En Codex no existe ese archivo, así que
  # la comparación "instalada vs corriendo" no se puede hacer: se informa la que corre y listo.
  # Antes se consultaba igual, y el registro del OTRO programa —si esa máquina tenía los dos—
  # podía contradecir a esta sesión y mandar a reiniciar un programa que no era el suyo.
  if [ "$(ob_host)" = "codex" ]; then
    [ -n "$ob_corre" ] && printf 'version|ok|paquete %s\n' "$ob_corre"
    return
  fi
  ob_inst=$(ob_doc_version_instalada)
  if [ -n "$ob_inst" ] && [ -n "$ob_corre" ] && [ "$ob_inst" != "$ob_corre" ]; then
    printf 'version|aviso|tenés instalada la %s pero esta sesión está corriendo la %s: reiniciá Claude Code para que tome la nueva\n' \
      "$ob_inst" "$ob_corre"
    return
  fi
  [ -n "$ob_corre" ] || ob_corre="$ob_inst"
  [ -n "$ob_corre" ] && printf 'version|ok|plugin %s\n' "$ob_corre"
}

# ¿El contexto de arranque llegó ENTERO la última vez? Traduce la telemetría de entrega que
# deja session-start.sh (ob_log_delivery). Existe porque la falla que más contexto se comió no
# es visible desde afuera: cuando el bloque pasa de ~9 KB, Claude Code lo reemplaza por un
# preview de 2 KB y nadie se entera — el 62% de las sesiones medidas. Sin esta línea, la única
# forma de saberlo era adivinar.
ob_doc_entrega() {
  f="${ONE_BRAIN_DELIVERY_LOG:-$(ob_config_dir)/delivery.log}"
  if [ ! -r "$f" ] || [ ! -s "$f" ]; then
    printf 'entrega|aviso|todavía no hay registro de entregas del hook de arranque (%s)\n' "$f"; return
  fi
  ult=$(tail -n1 "$f")
  ch=$(printf '%s' "$ult" | sed -n 's/.*chars=\([0-9]*\).*/\1/p')
  rec=$(printf '%s' "$ult" | sed -n 's/.*recortes=\([^ ]*\).*/\1/p')
  techo=$(printf '%s' "$ult" | sed -n 's/.*techo=\([^ ]*\).*/\1/p')
  if [ "$techo" = "si" ] || { [ -n "$rec" ] && [ "$rec" != "ninguno" ]; }; then
    printf 'entrega|aviso|el último arranque emitió %s caracteres y hubo recorte (bloques: %s, techo global: %s)\n' \
      "$ch" "$rec" "$techo"
  else
    printf 'entrega|ok|el último arranque emitió %s caracteres, sin recortes\n' "$ch"
  fi
}

# ¿Hay trabajo esperando ser destilado, y cuánto? El aviso de arranque decide sobre markers en
# un directorio que nadie sabe que existe: cuando salía en todos los arranques, la única forma
# de entender por qué era leerse el código del hook. Cuenta SÓLO los que van a avisar de
# verdad (reason=edits), no las colas de cierre ni el cruft.
ob_doc_captura() {
  d=$(ob_pending_dir)
  n=0
  for f in "$d"/pending-*; do
    [ -e "$f" ] || continue
    [ "$(sed -n 's/^reason=//p' "$f" | head -n1)" = "edits" ] && n=$((n + 1))
  done
  if [ "$n" -eq 0 ]; then
    printf 'captura|ok|no hay trabajo anterior esperando destilarse\n'
  else
    printf 'captura|aviso|%s sesión(es) anteriores con trabajo sin destilar (se avisa al arrancar, hasta %s veces cada una; markers en %s)\n' \
      "$n" "${OB_PENDING_MAX_NAGS:-3}" "$d"
  fi
}

# ¿En qué perfil y con qué cerebro está corriendo esta instalación? Existe porque con dos
# cerebros en la misma máquina, "no me guarda nada" y "me guarda en el cerebro equivocado" se
# ven igual desde afuera.
ob_doc_perfil() {
  d=$(ob_state_dir)
  c=$(ob_cerebro_de_token "$d/token")
  if ob_token_heredado 2>/dev/null; then
    printf 'perfil|aviso|perfil %s, cerebro %s — el token lo heredó de la máquina; %s <token> lo separa\n' \
      "$(ob_profile_name "$(ob_host_config_dir)")" "${c:-sin token}" "$(ob_skill_cmd connect)"; return
  fi
  printf 'perfil|ok|perfil %s, cerebro %s, estado en %s\n' \
    "$(ob_profile_name "$(ob_host_config_dir)")" "${c:-sin token}" "$d"
}

# Corre todos los chequeos, en orden de "qué mirar primero".
ob_doc_todos() {
  ob_doc_token
  ob_doc_perfil
  ob_doc_dependencias
  ob_doc_parser
  ob_doc_hooks_activos
  ob_doc_carpeta
  ob_doc_entrega
  ob_doc_captura
  ob_doc_conexion
}
