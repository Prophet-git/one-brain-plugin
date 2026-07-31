#!/bin/sh
# Test de caracterización de session-start.sh: corre el hook contra un server mock,
# con HOME aislado, y compara la salida contra el golden. NO valida que la salida sea
# "correcta" — valida que sea LA MISMA que antes de tocar nada.
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/.." && pwd)
REPO=$(CDPATH= cd -- "$ROOT/.." && pwd)
GOLDEN="$DIR/golden/session-start.txt"

# El hook imprime la ruta ABSOLUTA de bin/onebrain-save, así que un golden crudo queda atado a
# la máquina donde se generó (acá el checkout está en un lado, en la de Fran en otro). Se
# reemplaza SOLO la raíz del repo por <REPO>, con un replace literal: el resto de la línea
# —incluido el "/plugin/scripts/../bin/onebrain-save"— se compara tal cual, así que si el
# refactor mueve el binario o le cambia el nombre, el test sigue fallando como tiene que fallar.
# Se aplica al generar Y al comparar, para que las dos puntas hablen el mismo idioma.
#
# La base del server mock se normaliza igual y por el mismo motivo: el puerto ahora es EFÍMERO
# (lo asigna el sistema), así que un golden con el puerto adentro fallaría en cada corrida. Se
# reemplaza SOLO "http://127.0.0.1:<puerto>"; el "/api/synthesis" que sigue se compara tal cual.
normalizar() {
  python3 -c 'import sys
texto = sys.stdin.read().replace(sys.argv[1], "<REPO>").replace(sys.argv[2], "<URL>")
sys.stdout.write(texto)' "$REPO" "$1"
}

# --- mock en puerto efímero ------------------------------------------------------------------
# Antes: puerto fijo 8791 + `sleep 1`. Dos corridas solapadas se pisaban (la segunda moría con
# "Address already in use", el hook le pegaba al mock de la otra) y el test fallaba sin que
# hubiera nada roto — ya pasó dos veces. Ahora el sistema asigna un puerto libre, el mock lo
# anuncia por stdout, y en vez de dormir a ciegas se espera a que el socket ACEPTE conexiones.
MOCK_OUT=$(mktemp)
MOCK=""
limpiar() {
  [ -n "$MOCK" ] && kill "$MOCK" 2>/dev/null
  rm -f "$MOCK_OUT"
  [ -n "$FAKEHOME" ] && rm -rf "$FAKEHOME"
}
trap limpiar EXIT INT TERM

python3 "$DIR/mock-server.py" 0 > "$MOCK_OUT" 2>/dev/null & MOCK=$!

# Esperar la línea con el puerto (máx ~10s). Si el proceso murió, no tiene sentido seguir.
# Se exige el SALTO DE LÍNEA (wc -l >= 1) antes de leer: leer el archivo a mitad de la escritura
# podría devolver un puerto truncado ("879" en vez de "8791"), que es justo la clase de carrera
# que este cambio viene a sacar.
PUERTO=""
ESPERA=0
while [ "$ESPERA" -lt 200 ]; do
  if [ "$(wc -l < "$MOCK_OUT" 2>/dev/null || echo 0)" -ge 1 ]; then
    PUERTO=$(head -n 1 "$MOCK_OUT")
    break
  fi
  kill -0 "$MOCK" 2>/dev/null || break
  sleep 0.05
  ESPERA=$((ESPERA + 1))
done
if [ -z "$PUERTO" ]; then
  echo "FAIL: el server mock no arrancó (no anunció puerto)"
  exit 1
fi

# Confirmar que el socket acepta de verdad antes de correr el hook. El bind ya pasó (el mock
# imprime el puerto después de construir el HTTPServer), pero esto lo deja explícito y sin
# supuestos sobre el orden: reintenta hasta 10s y sale apenas conecta, así que en el caso normal
# tarda milisegundos en vez del segundo fijo de antes.
if ! python3 - "$PUERTO" <<'PY'
import socket, sys, time
puerto = int(sys.argv[1])
limite = time.time() + 10
while time.time() < limite:
    try:
        with socket.create_connection(("127.0.0.1", puerto), timeout=0.2):
            sys.exit(0)
    except OSError:
        time.sleep(0.02)
sys.exit(1)
PY
then
  echo "FAIL: el server mock nunca aceptó conexiones en el puerto $PUERTO"
  exit 1
fi

FAKEHOME=$(mktemp -d)
mkdir -p "$FAKEHOME/.config/one-brain"
printf 'ob_test_0000000000000000' > "$FAKEHOME/.config/one-brain/token"

BASE="http://127.0.0.1:$PUERTO"
SALIDA=$(printf '{"session_id":"test-fijo","cwd":"/tmp"}' \
  | HOME="$FAKEHOME" ONE_BRAIN_URL="$BASE" sh "$ROOT/scripts/session-start.sh" 2>/dev/null \
  | normalizar "$BASE")

limpiar
trap - EXIT INT TERM

if [ "${1:-}" = "--actualizar" ]; then
  mkdir -p "$DIR/golden"
  printf '%s' "$SALIDA" > "$GOLDEN"
  echo "golden actualizado"
  exit 0
fi

if [ ! -r "$GOLDEN" ]; then
  echo "FAIL: no existe el golden. Generalo con: sh $0 --actualizar"
  exit 1
fi

if [ "$SALIDA" = "$(cat "$GOLDEN")" ]; then
  echo "PASS: session-start.sh produce la salida esperada"
  exit 0
fi

echo "FAIL: la salida de session-start.sh cambió"
printf '%s' "$SALIDA" > /tmp/session-start-actual.txt
diff "$GOLDEN" /tmp/session-start-actual.txt | head -40
exit 1
