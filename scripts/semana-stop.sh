#!/bin/sh
# Stop hook de Semana: lanza onebrain-semana-push en segundo plano y sale enseguida.
#
#   1. NO BLOQUEA. El recolector lee los logs de Claude Code y sube por la red; eso va desacoplado
#      (nohup, sin stdin/stdout) y este script termina en milisegundos.
#   2. EL TOPE DE 10 MINUTOS lo aplica el bin (una sola regla, y `--ahora` la saltea a mano).
#   3. NO HABLA. Un Stop hook que escribe en stdout le habla al modelo. Si algo no anda, lo dice el
#      arranque de la sesión siguiente (onebrain-semana-push --aviso) y brain_semana en `estado`.
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
command -v python3 >/dev/null 2>&1 || exit 0
nohup sh "$DIR/../bin/onebrain-semana-push" </dev/null >/dev/null 2>&1 &
exit 0
