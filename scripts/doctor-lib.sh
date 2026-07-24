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

# ¿Hay un CLAUDE.md en la carpeta de trabajo? Sin él, Claude no sabe que tiene que usar el
# cerebro y el usuario cree que el producto "no hace nada".
ob_doc_carpeta() {
  d="${ONE_BRAIN_DIR:-$HOME/Documents/one-brain}"
  if [ ! -d "$d" ]; then
    printf 'carpeta|aviso|no existe %s (si trabajás en otra carpeta, ignoralo)\n' "$d"; return
  fi
  if [ -r "$d/CLAUDE.md" ]; then
    printf 'carpeta|ok|%s con su CLAUDE.md\n' "$d"
  else
    printf 'carpeta|aviso|%s existe pero no tiene CLAUDE.md: Claude no va a saber usar el cerebro ahí\n' "$d"
  fi
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

# Corre todos los chequeos, en orden de "qué mirar primero".
ob_doc_todos() {
  ob_doc_token
  ob_doc_dependencias
  ob_doc_parser
  ob_doc_hooks_activos
  ob_doc_carpeta
  ob_doc_conexion
}
