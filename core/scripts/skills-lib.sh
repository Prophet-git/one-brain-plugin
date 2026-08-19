#!/bin/sh
# La biblioteca de skills del lado de la máquina: qué puede correr, dónde se escriben, y qué
# instaló el plugin (para no borrar nunca una skill que escribió el usuario).

# Las dos carpetas salen de state-dir.sh, que es donde vive la resolución por perfil: alguien
# con dos cuentas de Claude en la misma computadora instala en cada una por separado. Se carga
# con el mismo patrón que capture-lib.sh —$0 y tres candidatas— y con la misma red de seguridad
# abajo, porque el patrón falla cuando esto se sourcea vía `sh -c`, que es como corren los tests.
ob_sk_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
for _obsd in "$ob_sk_dir/state-dir.sh" "$ob_sk_dir/../scripts/state-dir.sh" "$ob_sk_dir/../core/scripts/state-dir.sh"; do
  [ -r "$_obsd" ] && { . "$_obsd"; break; }
done
# Ante la duda, el comportamiento de SIEMPRE (perfil único). Nunca reventar el arranque.
if ! command -v ob_host_config_dir >/dev/null 2>&1; then
  ob_host_config_dir() { printf '%s' "${OB_HOST_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-$(printf '%s' "${HOME:-$USERPROFILE}" | tr '\\' '/')/.claude}}"; }
fi
if ! command -v ob_state_dir >/dev/null 2>&1; then
  ob_state_dir() { printf '%s/.config/one-brain' "$(printf '%s' "${HOME:-$USERPROFILE}" | tr '\\' '/')"; }
fi

# Los binarios y apps que el catálogo puede llegar a pedir. Se chequean TODOS y se informa qué
# hay: el server decide, acá sólo se mira. Es una lista y no un descubrimiento libre porque
# mandar el inventario de programas de la computadora de alguien sería otra cosa.
OB_SKILLS_BINARIOS_DEFAULT="mlx-whisper yt-dlp ffmpeg playwright"

# Dónde se escriben las skills: la carpeta del perfil de Claude que hospeda ESTA sesión.
ob_skills_dir() {
  printf '%s/skills' "$(ob_host_config_dir)"
}

# Qué instaló el plugin. Cuelga del estado del perfil, no de $HOME: si son dos cuentas, cada
# una lleva su propia cuenta de lo que instaló.
ob_skills_manifest() {
  printf '%s/skills.json' "$(ob_state_dir)"
}

# Imprime {"so":"darwin","arch":"arm64","tiene":["mlx-whisper"]}
ob_perfil_maquina() {
  _obso=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')
  case "$_obso" in
    darwin) _obso=darwin ;;
    linux)  _obso=linux ;;
    mingw*|msys*|cygwin*) _obso=windows ;;
  esac
  _obarch=$(uname -m 2>/dev/null)
  _obtiene=""
  for _obb in ${OB_SKILLS_BINARIOS:-$OB_SKILLS_BINARIOS_DEFAULT}; do
    if command -v "$_obb" >/dev/null 2>&1; then
      _obtiene="$_obtiene${_obtiene:+,}\"$_obb\""
    fi
  done
  # Apps de macOS: existen como carpeta, no como binario en PATH.
  if [ "$_obso" = darwin ] && [ -d "/Applications/WhatsApp.app" ]; then
    _obtiene="$_obtiene${_obtiene:+,}\"WhatsApp Desktop\""
  fi

  # mlx-whisper es un caso aparte por dos motivos que se suman: su ejecutable se llama
  # mlx_whisper con guion BAJO (el guion medio es el nombre del paquete de pip, no del binario),
  # y se instala en un venv que nadie tiene activado. Con `command -v mlx-whisper` no aparecía
  # NUNCA, ni en la computadora donde anda perfecto: el panel apagaba la card de la primera
  # skill del catálogo diciéndole a su propio autor que le faltaba algo que tenía instalado.
  #
  # Se busca el EJECUTABLE donde vive, no se importa el módulo: `python -c "import mlx_whisper"`
  # tarda 1,5 s y esto corre en cada arranque de sesión. Se reporta con el nombre que usa la
  # ficha del catálogo (mlx-whisper), que es contra lo que compara el server.
  case ",$_obtiene," in
    *'"mlx-whisper"'*) ;;
    *)
      for _obmw in \
        "$(command -v mlx_whisper 2>/dev/null)" \
        "$(command -v mlx-whisper 2>/dev/null)" \
        "${WA_READ_WHISPER_PY%/*}/mlx_whisper" \
        "${HOME:-$USERPROFILE}/.local/mlx-whisper-venv/bin/mlx_whisper"
      do
        if [ -n "$_obmw" ] && [ -x "$_obmw" ]; then
          _obtiene="$_obtiene${_obtiene:+,}\"mlx-whisper\""
          break
        fi
      done ;;
  esac
  printf '{"so":"%s","arch":"%s","tiene":[%s]}' "$_obso" "$_obarch" "$_obtiene"
}

# --- la bajada -------------------------------------------------------------------------------

# El plan del sync, aplanado a texto que el shell consume sin volver a parsear JSON: una línea
# por ARCHIVO, con "slug<TAB>version<TAB>ruta<TAB>sha256".
#
# Va por la misma cascada jq → python3 → perl que ob_json_field, y por el mismo motivo: parsear
# este JSON con sed no se puede. El primer intento del plan separaba los ítems con `tr '}' '\n'`
# y perdía en silencio el segundo archivo de cualquier skill —la primera skill real,
# whatsapp-read, tiene SKILL.md más scripts—, o sea que instalaba una skill a medias y la daba
# por buena. Y los campos `nombre` y `ejemplo` vienen de la base: un nombre con una comilla o
# una llave adentro le mueve el piso a cualquier expresión regular.
#
# Sin ninguno de los tres no se instala NADA. Es a propósito: media skill en disco es peor que
# ninguna, y el motivo sale por stderr en vez de fallar mudo.
ob_skills_plan() { # <json del sync>
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.instalar[]? | .slug as $s | .version as $v | .archivos[]? | [$s,$v,.ruta,.sha256] | @tsv' 2>/dev/null
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for it in d.get("instalar") or []:
    for a in it.get("archivos") or []:
        sys.stdout.write("\t".join([str(it.get("slug","")),str(it.get("version","")),str(a.get("ruta","")),str(a.get("sha256",""))])+"\n")' 2>/dev/null
    return
  fi
  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$1" | perl -CO -MJSON::PP -0777 -ne 'my $d=eval{decode_json($_)}; exit unless ref $d eq "HASH";
for my $i (@{$d->{instalar}||[]}) { for my $a (@{$i->{archivos}||[]}) {
  print join("\t", $i->{slug}//"", $i->{version}//"", $a->{ruta}//"", $a->{sha256}//""), "\n" } }' 2>/dev/null
    return
  fi
  printf 'One Brain: no hay jq, python3 ni perl en esta computadora, así que no se instalan skills.\n' >&2
}

# Los slugs a sacar, uno por línea. Misma cascada, mismo motivo.
ob_skills_plan_sacar() { # <json del sync>
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.sacar[]? | select(type=="string")' 2>/dev/null
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for s in d.get("sacar") or []:
    if isinstance(s,str): sys.stdout.write(s+"\n")' 2>/dev/null
    return
  fi
  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$1" | perl -CO -MJSON::PP -0777 -ne 'my $d=eval{decode_json($_)}; exit unless ref $d eq "HASH";
print "$_\n" for grep { !ref } @{$d->{sacar}||[]}' 2>/dev/null
  fi
}

# El nombre y el ejemplo de cada skill del plan, para el aviso del arranque: una línea
# "slug<TAB>nombre<TAB>ejemplo". Van aparte del plan de archivos a propósito: son texto libre
# cargado en el panel, y mezclarlos con la lista de rutas y hashes ensucia el bucle que escribe
# en disco. Los tabs y saltos que pudieran venir adentro se aplastan a espacio, porque el
# separador de esta salida es justo el tab.
ob_skills_plan_meta() { # <json del sync>
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.instalar[]? | [.slug, (.nombre // ""), (.ejemplo // "")] | map(gsub("[\t\n\r]";" ")) | @tsv' 2>/dev/null
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import json,sys
def limpio(v): return " ".join(str(v or "").split())
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for it in d.get("instalar") or []:
    sys.stdout.write("\t".join([limpio(it.get("slug")),limpio(it.get("nombre")),limpio(it.get("ejemplo"))])+"\n")' 2>/dev/null
    return
  fi
  if command -v perl >/dev/null 2>&1; then
    printf '%s' "$1" | perl -CO -MJSON::PP -0777 -ne 'my $d=eval{decode_json($_)}; exit unless ref $d eq "HASH";
for my $i (@{$d->{instalar}||[]}) { my @c = map { my $x = $_ // ""; $x =~ s/[\t\n\r]+/ /g; $x } ($i->{slug}, $i->{nombre}, $i->{ejemplo});
  print join("\t", @c), "\n" }' 2>/dev/null
  fi
}

# ¿Esta carpeta la escribió el plugin? Es la pregunta que evita el bug caro: borrarle a alguien
# una skill que escribió a mano porque el catálogo tiene una con el mismo nombre.
ob_skills_es_mia() { # <slug>
  grep -q "\"slug\":\"$1\"" "$(ob_skills_manifest)" 2>/dev/null
}

# Una ruta que se puede escribir adentro de la carpeta de la skill y en ningún otro lado.
# El catálogo lo cura Prophet, pero eso es una promesa de proceso y esto es la de código: una
# ruta absoluta o con ".." adentro escribiría archivos donde se le cante, y el que baja no
# tiene por qué confiar en el que publica.
ob_skills_ruta_ok() { # <ruta>
  case "$1" in
    ""|/*|*..*|*"\\"*) return 1 ;;
  esac
  return 0
}

# Baja, verifica y escribe. NUNCA ejecuta nada de lo que baja: sólo lo escribe.
ob_skills_aplicar() { # <url> <token> <json del sync>
  _oburl="$1"; _obtok="$2"; _objson="$3"
  _obdest=$(ob_skills_dir)
  mkdir -p "$_obdest" 2>/dev/null
  # La meta se resuelve UNA vez y se deja en un temporal: ob_skills_cerrar_una la consulta para
  # armar el aviso, y volver a parsear el JSON por cada skill sería el mismo trabajo N veces.
  _obmeta=$(mktemp) && ob_skills_plan_meta "$_objson" > "$_obmeta" 2>/dev/null

  # --- instalar ---
  # El plan viene aplanado por archivo; acá se reagrupa por skill. Se recorre con `while read`
  # sobre un heredoc y NO sobre un pipe, para que las variables sobrevivan a la última vuelta:
  # con un pipe el bucle corre en un subshell y la última skill se quedaba sin escribir.
  _obslug=""; _obver=""; _obtmp=""; _obok=1
  while IFS="$(printf '\t')" read -r _obs _obv _obr _obh; do
    [ -z "$_obs" ] && continue
    if [ "$_obs" != "$_obslug" ]; then
      ob_skills_cerrar_una   # cierra la anterior, si había
      _obslug="$_obs"; _obver="$_obv"; _obok=1; _obtmp=""
      # Si el destino existe y NO lo escribió el plugin, es del usuario: no se toca.
      if [ -e "$_obdest/$_obslug" ] && ! ob_skills_es_mia "$_obslug"; then
        _obok=2   # 2 = choque de nombre, se avisa distinto y no se baja nada
        continue
      fi
      _obtmp=$(mktemp -d) || { _obok=0; continue; }
    fi
    [ "$_obok" = 2 ] && continue
    [ -z "$_obtmp" ] && continue
    if ! ob_skills_ruta_ok "$_obr"; then _obok=0; continue; fi
    mkdir -p "$_obtmp/$(dirname "$_obr")" 2>/dev/null
    curl -s --max-time 20 -H "Authorization: Bearer $_obtok" \
      "$_oburl/api/skills/archivo?slug=$_obslug&version=$_obver&ruta=$_obr" \
      -o "$_obtmp/$_obr" 2>/dev/null
    _obreal=$(shasum -a 256 "$_obtmp/$_obr" 2>/dev/null | awk '{print $1}')
    [ "$_obreal" = "$_obh" ] || _obok=0
  done <<OBPLAN
$(ob_skills_plan "$_objson")
OBPLAN
  ob_skills_cerrar_una   # la última

  # --- sacar ---
  ob_skills_plan_sacar "$_objson" | while read -r _obs; do
    [ -z "$_obs" ] && continue
    # SÓLO lo que instaló el plugin. Una skill del usuario con el mismo nombre no se toca.
    ob_skills_es_mia "$_obs" || continue
    rm -rf "$_obdest/$_obs" 2>/dev/null
    ob_skills_manifest_del "$_obs"
    ob_skills_confirmar "$_oburl" "$_obtok" "$_obs" true ""
  done
  [ -n "$_obmeta" ] && rm -f "$_obmeta" 2>/dev/null
}

# Cierra la skill que se venía bajando: si está entera la mueve al destino, si no la tira.
# Depende de las variables del bucle de ob_skills_aplicar a propósito — es su segunda mitad,
# separada sólo para que ese bucle se lea.
ob_skills_cerrar_una() {
  [ -z "$_obslug" ] && return 0
  if [ "$_obok" = 2 ]; then
    ob_skills_confirmar "$_oburl" "$_obtok" "$_obslug" false "Ya tenés una skill con ese nombre en tu computadora."
  elif [ "$_obok" = 1 ] && [ -n "$_obtmp" ]; then
    rm -rf "$_obdest/$_obslug" 2>/dev/null
    mv "$_obtmp" "$_obdest/$_obslug" 2>/dev/null
    ob_skills_manifest_add "$_obslug" "$_obver"
    ob_skills_confirmar "$_oburl" "$_obtok" "$_obslug" true ""
    # El aviso del arranque. Sale por stdout —es lo ÚNICO que esta función imprime— para que
    # session-start lo pegue en el saludo. Lleva el ejemplo de uso porque una skill instalada
    # que nadie sabe cómo pedir es una skill que no existe.
    _obnom=$(awk -F"\t" -v s="$_obslug" '$1==s{print $2; exit}' "$_obmeta" 2>/dev/null)
    _obej=$(awk -F"\t" -v s="$_obslug" '$1==s{print $3; exit}' "$_obmeta" 2>/dev/null)
    [ -z "$_obnom" ] && _obnom="$_obslug"
    if [ -n "$_obej" ]; then
      printf 'Instalé %s. Probala pidiéndome: "%s"\n' "$_obnom" "$_obej"
    else
      printf 'Instalé %s.\n' "$_obnom"
    fi
  else
    [ -n "$_obtmp" ] && rm -rf "$_obtmp" 2>/dev/null
    ob_skills_confirmar "$_oburl" "$_obtok" "$_obslug" false "Se cortó la descarga."
  fi
  _obslug=""; _obtmp=""
}

ob_skills_confirmar() { # <url> <token> <slug> <true|false> <motivo>
  curl -s --max-time 8 -X POST -H "Authorization: Bearer $2" -H "content-type: application/json" \
    -d "{\"slug\":\"$3\",\"ok\":$4,\"motivo\":\"$5\"}" "$1/api/skills/aplicado" >/dev/null 2>&1
}

# El manifest es JSON-lines, una línea por skill. Es a propósito: agregar y borrar líneas con
# grep y >> es confiable en shell POSIX, y editar un objeto JSON con sed no lo es.
ob_skills_manifest_add() { # <slug> <version>
  _obm=$(ob_skills_manifest)
  mkdir -p "$(dirname "$_obm")" 2>/dev/null
  ob_skills_manifest_del "$1"
  printf '{"slug":"%s","version":"%s"}\n' "$1" "$2" >> "$_obm"
}

ob_skills_manifest_del() { # <slug>
  _obm=$(ob_skills_manifest)
  [ -f "$_obm" ] || return 0
  grep -v "\"slug\":\"$1\"" "$_obm" > "$_obm.tmp" 2>/dev/null
  mv "$_obm.tmp" "$_obm" 2>/dev/null
}
