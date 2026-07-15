#!/bin/sh
# headersHelper de One Brain: lee el token local y emite el header Authorization.
# Corre fresco en cada conexión del MCP. Sin token -> objeto vacío (no rompe).
TOKEN_FILE="$HOME/.config/one-brain/token"
if [ -r "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
  TOKEN=$(tr -d ' \t\r\n' < "$TOKEN_FILE")
  printf '{"Authorization":"Bearer %s"}' "$TOKEN"
else
  printf '{}'
  echo "one-brain: sin token. Corré /one-brain:connect <token>." >&2
fi
