#!/bin/sh
# Batería de la bajada de skills: el plugin baja, verifica el sha256 y escribe, sin tocar
# NUNCA una skill que escribió el usuario.
#
# Archivo aparte de run.sh porque necesita un server levantado, y run.sh no levanta ninguno.
# El patrón del mock en puerto efímero está copiado de session-start-test.sh, incluida la
# espera al socket: dormir a ciegas ya hizo fallar ese test dos veces sin que hubiera nada roto.
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/.." && pwd)

PASS=0; FAIL=0
assert_eq() { # <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s (esperado=%s actual=%s)\n' "$1" "$2" "$3"; fi
}

# Cuántas líneas de <archivo> matchean <patrón>. Existe porque `grep -c x f || echo 0` imprime
# DOS ceros cuando el archivo existe y no matchea: grep -c ya escribe su "0" y encima sale 1.
contar() { # <patrón> <archivo>
  [ -f "$2" ] || { printf 0; return; }
  _n=$(grep -c "$1" "$2" 2>/dev/null)
  printf '%s' "${_n:-0}"
}

# --- mock en puerto efímero ------------------------------------------------------------------
MOCK_OUT=$(mktemp)
POSTS=$(mktemp)
MOCK=""
SKILLS_DIR=""
ESTADO_DIR=""
limpiar() {
  [ -n "$MOCK" ] && kill "$MOCK" 2>/dev/null
  rm -f "$MOCK_OUT" "$POSTS"
  [ -n "$SKILLS_DIR" ] && rm -rf "$SKILLS_DIR"
  [ -n "$ESTADO_DIR" ] && rm -rf "$ESTADO_DIR"
}
trap limpiar EXIT INT TERM

OB_MOCK_POSTS="$POSTS" python3 "$DIR/skills-mock.py" 0 > "$MOCK_OUT" 2>/dev/null & MOCK=$!

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
MOCK_URL="http://127.0.0.1:$PUERTO"

# Confirmar que el socket acepta de verdad antes de pegarle.
ESPERA=0
while [ "$ESPERA" -lt 200 ]; do
  curl -s --max-time 1 "$MOCK_URL/api/skills/archivo?ruta=x" >/dev/null 2>&1 && break
  sleep 0.05
  ESPERA=$((ESPERA + 1))
done

# --- el escenario --------------------------------------------------------------------------
SKILLS_DIR=$(mktemp -d)
ESTADO_DIR=$(mktemp -d)
OB_HOST_CONFIG_DIR="$SKILLS_DIR"
ONE_BRAIN_STATE_DIR="$ESTADO_DIR"
export OB_HOST_CONFIG_DIR ONE_BRAIN_STATE_DIR
. "$ROOT/core/scripts/skills-lib.sh"

# Una skill ajena, escrita por el usuario, que el plugin NO tiene que tocar nunca.
mkdir -p "$OB_HOST_CONFIG_DIR/skills/mia"
printf 'no me borres' > "$OB_HOST_CONFIG_DIR/skills/mia/SKILL.md"

SHA_HOLA=$(printf 'hola' | shasum -a 256 | awk '{print $1}')
SYNC_JSON="{\"instalar\":[{\"slug\":\"demo\",\"version\":\"1.0.0\",\"archivos\":[{\"ruta\":\"SKILL.md\",\"sha256\":\"$SHA_HOLA\"}]}],\"sacar\":[]}"
ob_skills_aplicar "$MOCK_URL" "tok" "$SYNC_JSON" >/dev/null 2>&1

assert_eq "escribió la skill" "hola" "$(cat "$OB_HOST_CONFIG_DIR/skills/demo/SKILL.md" 2>/dev/null)"
assert_eq "anotó en el manifest" 1 "$(contar '"demo"' "$(ob_skills_manifest)")"
assert_eq "confirmó la instalación al server" 1 "$(contar '"slug":"demo".*"ok":true' "$POSTS")"

# El aviso para el arranque: lo ÚNICO que esta función imprime. Lleva el nombre en criollo y el
# ejemplo de uso, porque una skill instalada que nadie sabe cómo pedir es una skill que no existe.
SYNC_AVISO="{\"instalar\":[{\"slug\":\"avisa\",\"version\":\"1.0.0\",\"nombre\":\"Leer WhatsApp\",\"ejemplo\":\"fijate qué mandó Nacho\",\"archivos\":[{\"ruta\":\"SKILL.md\",\"sha256\":\"$SHA_HOLA\"}]}],\"sacar\":[]}"
AVISO=$(ob_skills_aplicar "$MOCK_URL" "tok" "$SYNC_AVISO" 2>/dev/null)
assert_eq "el aviso trae nombre y ejemplo" 'Instalé Leer WhatsApp. Probala pidiéndome: "fijate qué mandó Nacho"' "$AVISO"

# Sin ejemplo cargado, el aviso sale igual pero sin la parte del "probala".
SYNC_SIN_EJ="{\"instalar\":[{\"slug\":\"pelada\",\"version\":\"1.0.0\",\"nombre\":\"Cosa\",\"archivos\":[{\"ruta\":\"SKILL.md\",\"sha256\":\"$SHA_HOLA\"}]}],\"sacar\":[]}"
assert_eq "sin ejemplo, aviso corto" "Instalé Cosa." "$(ob_skills_aplicar "$MOCK_URL" "tok" "$SYNC_SIN_EJ" 2>/dev/null)"

# Una que NO se pudo bajar no aparece en el aviso: el arranque no puede prometer lo que no está.
SYNC_MUDA="{\"instalar\":[{\"slug\":\"muda\",\"version\":\"1.0.0\",\"nombre\":\"Muda\",\"archivos\":[{\"ruta\":\"SKILL.md\",\"sha256\":\"0000\"}]}],\"sacar\":[]}"
assert_eq "la que falló no se anuncia" "" "$(ob_skills_aplicar "$MOCK_URL" "tok" "$SYNC_MUDA" 2>/dev/null)"

# Una skill de varios archivos, con subcarpeta: se escriben todos.
MAPA=$(mktemp)
printf '{"SKILL.md":"cuerpo","scripts/leer.sh":"#!/bin/sh\\necho ok"}' > "$MAPA"
kill "$MOCK" 2>/dev/null; wait "$MOCK" 2>/dev/null
: > "$MOCK_OUT"
OB_MOCK_POSTS="$POSTS" OB_MOCK_ARCHIVOS="$MAPA" python3 "$DIR/skills-mock.py" "$PUERTO" > "$MOCK_OUT" 2>/dev/null & MOCK=$!
ESPERA=0
while [ "$ESPERA" -lt 200 ]; do
  curl -s --max-time 1 "$MOCK_URL/api/skills/archivo?ruta=SKILL.md" 2>/dev/null | grep -q cuerpo && break
  sleep 0.05
  ESPERA=$((ESPERA + 1))
done
SHA_CUERPO=$(printf 'cuerpo' | shasum -a 256 | awk '{print $1}')
SHA_SCRIPT=$(printf '#!/bin/sh\necho ok' | shasum -a 256 | awk '{print $1}')
SYNC_MULTI="{\"instalar\":[{\"slug\":\"multi\",\"version\":\"2.0.0\",\"archivos\":[{\"ruta\":\"SKILL.md\",\"sha256\":\"$SHA_CUERPO\"},{\"ruta\":\"scripts/leer.sh\",\"sha256\":\"$SHA_SCRIPT\"}]}],\"sacar\":[]}"
ob_skills_aplicar "$MOCK_URL" "tok" "$SYNC_MULTI" >/dev/null 2>&1
assert_eq "escribió el archivo de la raíz" "cuerpo" "$(cat "$OB_HOST_CONFIG_DIR/skills/multi/SKILL.md" 2>/dev/null)"
assert_eq "escribió el de la subcarpeta" "ok" "$(sh "$OB_HOST_CONFIG_DIR/skills/multi/scripts/leer.sh" 2>/dev/null)"
rm -f "$MAPA"

# Volver al mock que devuelve "hola" para todo.
kill "$MOCK" 2>/dev/null; wait "$MOCK" 2>/dev/null
: > "$MOCK_OUT"
OB_MOCK_POSTS="$POSTS" python3 "$DIR/skills-mock.py" "$PUERTO" > "$MOCK_OUT" 2>/dev/null & MOCK=$!
ESPERA=0
while [ "$ESPERA" -lt 200 ]; do
  curl -s --max-time 1 "$MOCK_URL/api/skills/archivo?ruta=x" 2>/dev/null | grep -q hola && break
  sleep 0.05
  ESPERA=$((ESPERA + 1))
done

# sha256 que no coincide: no queda NADA a medias en disco.
: > "$POSTS"
SYNC_MAL="{\"instalar\":[{\"slug\":\"rota\",\"version\":\"1.0.0\",\"archivos\":[{\"ruta\":\"SKILL.md\",\"sha256\":\"0000\"}]}],\"sacar\":[]}"
ob_skills_aplicar "$MOCK_URL" "tok" "$SYNC_MAL" >/dev/null 2>&1
assert_eq "no dejó nada a medias" 0 "$([ -e "$OB_HOST_CONFIG_DIR/skills/rota" ] && echo 1 || echo 0)"
assert_eq "no la anotó en el manifest" 0 "$(contar '"rota"' "$(ob_skills_manifest)")"
assert_eq "avisó al server que falló" 1 "$(contar '"slug":"rota".*"ok":false' "$POSTS")"

# Una skill del usuario con el mismo nombre que una del catálogo: no se pisa, se avisa.
: > "$POSTS"
SYNC_CHOQUE="{\"instalar\":[{\"slug\":\"mia\",\"version\":\"1.0.0\",\"archivos\":[{\"ruta\":\"SKILL.md\",\"sha256\":\"$SHA_HOLA\"}]}],\"sacar\":[]}"
ob_skills_aplicar "$MOCK_URL" "tok" "$SYNC_CHOQUE" >/dev/null 2>&1
assert_eq "no pisa la skill del usuario" "no me borres" "$(cat "$OB_HOST_CONFIG_DIR/skills/mia/SKILL.md" 2>/dev/null)"
assert_eq "avisa el choque de nombre" 1 "$(contar 'Ya tenés una skill con ese nombre' "$POSTS")"

# Una ruta que se escapa de la carpeta de la skill no se escribe, y la skill entera se cae.
# El catálogo lo cura Prophet, pero eso es una promesa de proceso: esta es la de código.
#
# La fuga es RELATIVA al temporal donde se baja, así que para que el assert sea determinístico
# hay que saber dónde cae ese temporal. Fijar TMPDIR no alcanza: el `mktemp -d` de macOS lo
# IGNORA cuando no lleva template (usa _CS_DARWIN_USER_TEMP_DIR), y con eso el archivo robado
# aterrizaba en /var/folders/... — el assert daba verde con la defensa SACADA, o sea que no
# probaba nada. Se intercepta mktemp con una función del propio test, que sí manda porque
# skills-lib.sh se sourcea en este mismo shell.
: > "$POSTS"
mkdir -p "$SKILLS_DIR/tmp"
mktemp() {
  if [ "$1" = "-d" ]; then command mktemp -d "$SKILLS_DIR/tmp/ob.XXXXXX"; else command mktemp "$@"; fi
}
CENTINELA="$SKILLS_DIR/tmp/robado.txt"
SYNC_FUGA="{\"instalar\":[{\"slug\":\"fuga\",\"version\":\"1.0.0\",\"archivos\":[{\"ruta\":\"../robado.txt\",\"sha256\":\"$SHA_HOLA\"}]}],\"sacar\":[]}"
ob_skills_aplicar "$MOCK_URL" "tok" "$SYNC_FUGA" >/dev/null 2>&1
assert_eq "no escribe fuera de la carpeta de la skill" 0 "$([ -e "$CENTINELA" ] && echo 1 || echo 0)"
assert_eq "y no la da por instalada" 0 "$(contar '"slug":"fuga"' "$(ob_skills_manifest)")"
unset -f mktemp

# Sacar borra sólo lo del manifest.
ob_skills_aplicar "$MOCK_URL" "tok" '{"instalar":[],"sacar":["demo"]}' >/dev/null 2>&1
assert_eq "borró la que instaló" 0 "$([ -e "$OB_HOST_CONFIG_DIR/skills/demo" ] && echo 1 || echo 0)"
assert_eq "la sacó del manifest" 0 "$(contar '"demo"' "$(ob_skills_manifest)")"
assert_eq "NO tocó la del usuario" "no me borres" "$(cat "$OB_HOST_CONFIG_DIR/skills/mia/SKILL.md" 2>/dev/null)"

# Sacar algo que el plugin no instaló: no borra nada aunque esté en la lista.
ob_skills_aplicar "$MOCK_URL" "tok" '{"instalar":[],"sacar":["mia"]}' >/dev/null 2>&1
assert_eq "no borra lo ajeno ni cuando se lo piden" "no me borres" "$(cat "$OB_HOST_CONFIG_DIR/skills/mia/SKILL.md" 2>/dev/null)"

unset OB_HOST_CONFIG_DIR ONE_BRAIN_STATE_DIR

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
