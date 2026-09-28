#!/bin/sh
# El arranque le manda a /api/resume el remote de git de la carpeta de la sesión (?repo=), para
# que el server sume la ficha del proyecto. Este test corre el hook contra el server mock en
# cinco carpetas y mira la ruta EXACTA que le llegó al server:
#   - repo con remote              → ?repo=<remote codificado>
#   - subcarpeta de ese repo       → el mismo remote
#   - carpeta sin git              → /api/resume pelado, igual que antes
#   - repo sin remote              → /api/resume pelado
#   - remote con caracteres raros  → el server lo decodifica y le queda idéntico
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/.." && pwd)

TMP=$(mktemp -d)
MOCK=""
limpiar() {
  [ -n "$MOCK" ] && kill "$MOCK" 2>/dev/null
  rm -rf "${TMP:?}"
}
trap limpiar EXIT INT TERM

PATHS="$TMP/paths.log"
OB_MOCK_PATHS="$PATHS" python3 "$DIR/mock-server.py" 0 > "$TMP/mock.out" 2>/dev/null & MOCK=$!

PUERTO=""
ESPERA=0
while [ "$ESPERA" -lt 200 ]; do
  if [ "$(wc -l < "$TMP/mock.out" 2>/dev/null || echo 0)" -ge 1 ]; then
    PUERTO=$(head -n 1 "$TMP/mock.out"); break
  fi
  kill -0 "$MOCK" 2>/dev/null || break
  sleep 0.05; ESPERA=$((ESPERA + 1))
done
[ -n "$PUERTO" ] || { echo "FAIL: el server mock no arrancó"; exit 1; }

FAKEHOME="$TMP/home"
mkdir -p "$FAKEHOME/.config/one-brain"
printf 'ob_test_0000000000000000' > "$FAKEHOME/.config/one-brain/token"

PASS=0; FAIL=0
assert_eq() { # <desc> <esperado> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s\n  esperado=%s\n  actual=  %s\n' "$1" "$2" "$3"; fi
}

# Corre el arranque con <cwd> en el input del hook y devuelve la ruta con la que llegó
# /api/resume al server (una sola línea; "" si no llegó).
resume_de() {
  : > "$PATHS"
  printf '{"session_id":"test-repo","cwd":"%s"}' "$1" \
    | HOME="$FAKEHOME" ONE_BRAIN_URL="http://127.0.0.1:$PUERTO" OB_HOST_CONFIG_DIR="$FAKEHOME/.claude" \
      sh "$ROOT/scripts/session-start.sh" >/dev/null 2>&1
  grep '^/api/resume' "$PATHS" | head -n1
}

# El valor de repo= tal como lo decodifica el server (parse_qs, igual que haría Next con
# searchParams.get). Así se prueba la ida y vuelta, no un string codificado a mano.
repo_decodificado() {
  python3 -c 'import sys, urllib.parse as u
q = u.urlsplit(sys.argv[1]).query
sys.stdout.write(u.parse_qs(q).get("repo", [""])[0])' "$1"
}

REPO="$TMP/proyecto"
mkdir -p "$REPO/src/adentro"
git -C "$REPO" init -q
git -C "$REPO" remote add origin "https://github.com/Prophet-git/one-brain.git"

R=$(resume_de "$REPO")
# curl escribe el hex en minúscula (%3a); los dos son válidos, así que se compara sin mayúsculas.
assert_eq "repo con remote: sale ?repo= codificado" \
  "/api/resume?repo=https%3a%2f%2fgithub.com%2fprophet-git%2fone-brain.git" "$(printf '%s' "$R" | tr 'A-Z' 'a-z')"
assert_eq "repo con remote: el server lo lee igual" \
  "https://github.com/Prophet-git/one-brain.git" "$(repo_decodificado "$R")"

R=$(resume_de "$REPO/src/adentro")
assert_eq "subcarpeta del repo: mismo remote" \
  "https://github.com/Prophet-git/one-brain.git" "$(repo_decodificado "$R")"

SINGIT="$TMP/suelta"
mkdir -p "$SINGIT"
assert_eq "carpeta sin git: /api/resume sin query" "/api/resume" "$(resume_de "$SINGIT")"

SINREMOTE="$TMP/sin-remote"
mkdir -p "$SINREMOTE"
git -C "$SINREMOTE" init -q
assert_eq "repo sin remote: /api/resume sin query" "/api/resume" "$(resume_de "$SINREMOTE")"

RARO="$TMP/raro"
mkdir -p "$RARO"
git -C "$RARO" init -q
REMOTE_RARO='git@github.com:Pro phet/ñandú&x=1+2#frag%41.git'
git -C "$RARO" remote add origin "$REMOTE_RARO"
R=$(resume_de "$RARO")
assert_eq "remote con caracteres raros: ida y vuelta idéntica" "$REMOTE_RARO" "$(repo_decodificado "$R")"
case "$R" in
  *'&x='*|*' '*|*'#'*) FAIL=$((FAIL+1)); printf 'FAIL: remote raro salió sin codificar: %s\n' "$R" ;;
  *) PASS=$((PASS+1)) ;;
esac

printf 'resume-repo: %s ok, %s fallas\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
