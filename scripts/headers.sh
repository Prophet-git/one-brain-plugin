#!/bin/sh
# headersHelper de One Brain: lee el token local y emite el header Authorization.
# Corre fresco en cada conexión del MCP. Sin token -> objeto vacío (no rompe).
#
# Robustez en Windows (Git Bash / WSL), donde este helper fallaba mudo y el usuario terminaba
# creyendo que su token no servía:
#  - HOME no siempre está definido: se cae a USERPROFILE.
#  - Un token pegado desde un editor de Windows viene con CRLF y a veces con BOM UTF-8: los
#    dos se limpian antes de armar el header (un BOM invisible hacía que el server devolviera
#    401 sin explicación).
#  - En máquinas donde no se puede escribir en el perfil, ONE_BRAIN_TOKEN sirve de alternativa.
BASE="${HOME:-$USERPROFILE}"
TOKEN_FILE="${ONE_BRAIN_TOKEN_FILE:-$BASE/.config/one-brain/token}"

TOKEN=""
if [ -r "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
  # tr saca espacios/CR/LF; sed saca el BOM UTF-8 (EF BB BF) si el archivo empieza con él.
  TOKEN=$(tr -d ' \t\r\n' < "$TOKEN_FILE" | sed "1s/^$(printf '\357\273\277')//")
fi
[ -z "$TOKEN" ] && TOKEN=$(printf '%s' "${ONE_BRAIN_TOKEN:-}" | tr -d ' \t\r\n')

if [ -n "$TOKEN" ]; then
  printf '{"Authorization":"Bearer %s"}' "$TOKEN"
else
  printf '{}'
  echo "one-brain: sin token. Corré /one-brain:connect <token>." >&2
fi
