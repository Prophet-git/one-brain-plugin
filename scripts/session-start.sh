#!/bin/sh
# SessionStart de CLAUDE CODE — adaptador.
#
# El arranque (qué se le pide al server, en qué orden se ensambla, el presupuesto de caracteres,
# la instrucción de atribución, la telemetría de entrega) vive en core/scripts/session-start-lib.sh:
# es One Brain, no el programa que lo hospeda. Acá quedan SOLO las diferencias de este host.
# De las cuatro, Claude Code usa tres:
#
#   - Token para las tools: no hace falta hacer nada. El server MCP lo resuelve solo en cada
#     conexión con scripts/headers.sh (headersHelper), que Codex no tiene — por eso allá el
#     arranque tiene que reconciliarlo a mano y acá no.
#   - Canal de guardado que se le informa al modelo: el PUENTE de bin/, no el bin del core. Esa
#     ruta ya circula en el contexto de sesiones abiertas y en las skills; moverla rompería a
#     cualquiera que la tenga escrita.
#   - Header x-client: claude.
#   - Emisión: stdout en TEXTO PLANO. Para SessionStart, lo que el hook escribe en stdout se
#     agrega al contexto tal cual. Sin escapado no hay nada que romper — y este script emitía
#     JSON antes: el brief trae comillas y saltos de línea reales, el JSON quedaba inválido y
#     Claude Code lo descartaba o mostraba el andamiaje crudo en pantalla.
#
# Silencioso ante cualquier fallo (nunca bloquea el arranque).
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Las librerías compartidas viven en core/ (fuente única, copiada acá por scripts/sync-core.sh).
[ -r "$DIR/../core/scripts/capture-lib.sh" ] || exit 0
. "$DIR/../core/scripts/capture-lib.sh"
[ -r "$DIR/../core/scripts/session-start-lib.sh" ] || exit 0
. "$DIR/../core/scripts/session-start-lib.sh"

OB_PKG_ROOT="$DIR/.."
OB_SAVE_BIN="$DIR/../bin/onebrain-save"
OB_CLIENT=claude

# Deja el auto-update del marketplace prendido, una sola vez y en silencio. Es específico de
# Claude Code (Codex no tiene extraKnownMarketplaces), por eso vive acá en el adaptador y no
# en core/. Sale en el primer `[ -f marca ]` en todas las sesiones menos la primera.
[ -x "$DIR/enable-autoupdate.sh" ] && "$DIR/enable-autoupdate.sh" >/dev/null 2>&1

ob_session_start

printf '%s' "$OB_STDOUT"
exit 0
