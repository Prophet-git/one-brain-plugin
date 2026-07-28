#!/bin/sh
# Chequeos del doctor de One Brain. Viven en una lib aparte (no en el ejecutable) para poder
# testearlos uno por uno sin correr el diagnóstico entero.
#
# Cada chequeo imprime UNA línea: "<clave>|<estado>|<detalle>", con estado ok | falla | aviso.
# El formato es fijo a propósito: el ejecutable lo imprime como reporte y la skill lo lee para
# explicarle al usuario qué hacer. Ningún chequeo modifica nada — el doctor diagnostica.

ob_doc_token_file() { printf '%s' "${ONE_BRAIN_TOKEN_FILE:-$HOME/.config/one-brain/token}"; }

# ¿Hay token guardado y legible? Nunca imprime el token: solo su presencia y longitud.
ob_doc_token() {
  f=$(ob_doc_token_file)
  if [ ! -e "$f" ]; then
    printf 'token|falla|no hay token en %s — corré /one-brain:connect <token>\n' "$f"; return
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
    printf 'parser|ok|el hook puede leer el input de Claude Code\n'
  else
    printf 'parser|falla|el hook NO puede leer el input en este entorno: la captura automática no va a andar\n'
  fi
}

# ¿Los hooks están apagados a nivel Claude Code? Con disableAllHooks en true el plugin queda
# mudo aunque todo lo demás esté perfecto — y no hay ninguna señal visible de eso.
ob_doc_hooks_activos() {
  s="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
  if [ -r "$s" ] && grep -q '"disableAllHooks"[[:space:]]*:[[:space:]]*true' "$s" 2>/dev/null; then
    printf 'hooks|falla|disableAllHooks está en true en %s: el plugin no captura nada\n' "$s"
  else
    printf 'hooks|ok|los hooks de Claude Code están habilitados\n'
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

# El CLAUDE.md con reglas de One Brain más cercano al directorio donde se está trabajando,
# subiendo por los padres. Claude Code carga el CLAUDE.md del directorio en el que se abrió y
# también los de arriba, así que un cerebro configurado en la carpeta madre igual aplica.
# Imprime la ruta y sale 0; si no hay ninguno, no imprime nada y sale 1.
ob_doc_claudemd_cerca() { # [directorio inicial; default el actual]
  # `pwd` (builtin) y no $PWD: el hook puede haber sido invocado con un PWD heredado que ya no
  # es el directorio real, y acá el directorio real es justamente el dato.
  ob_d=${1:-$(pwd)}
  case "$ob_d" in /*) ;; *) ob_d=$(pwd) ;; esac
  while :; do
    if ob_doc_reglas_en "$ob_d/CLAUDE.md"; then printf '%s/CLAUDE.md' "$ob_d"; return 0; fi
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
  if aqui=$(ob_doc_claudemd_cerca); then
    printf 'carpeta|ok|las reglas de One Brain están en %s\n' "$aqui"; return
  fi
  if [ -r "$d/CLAUDE.md" ]; then
    printf 'carpeta|ok|%s con su CLAUDE.md\n' "$d"; return
  fi
  if [ -d "$d" ]; then
    printf 'carpeta|aviso|%s existe pero no tiene CLAUDE.md, y en esta carpeta tampoco hay reglas de One Brain\n' "$d"
    return
  fi
  printf 'carpeta|aviso|no hay un CLAUDE.md con las reglas de One Brain en esta carpeta (ni en %s)\n' "$d"
}

# ¿El cerebro responde con este token? Un tools/list contra el endpoint MCP.
ob_doc_conexion() {
  f=$(ob_doc_token_file)
  url="${ONE_BRAIN_URL:-https://one-brain-kappa.vercel.app}"
  if [ ! -r "$f" ] || [ ! -s "$f" ]; then
    printf 'conexion|falla|sin token no se puede probar la conexión\n'; return
  fi
  command -v curl >/dev/null 2>&1 || { printf 'conexion|falla|sin curl no se puede probar\n'; return; }
  tok=$(tr -d ' \t\r\n' < "$f")
  # Mismo endpoint que usa `onebrain-token verify`: /api/mcp (no /mcp).
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 -X POST "$url/api/mcp" \
    -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' 2>/dev/null)
  case "$code" in
    200) printf 'conexion|ok|el cerebro responde en %s\n' "$url" ;;
    401|403) printf 'conexion|falla|el cerebro rechazó el token (HTTP %s): pedí uno nuevo y corré /one-brain:connect\n' "$code" ;;
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

# Corre todos los chequeos, en orden de "qué mirar primero".
ob_doc_todos() {
  ob_doc_token
  ob_doc_dependencias
  ob_doc_parser
  ob_doc_hooks_activos
  ob_doc_carpeta
  ob_doc_entrega
  ob_doc_conexion
}
