#!/bin/sh
# headersHelper de One Brain: lee el token local y emite el header Authorization.
# Corre fresco en cada conexión del MCP. Sin token -> objeto vacío (no rompe la conexión),
# pero SIEMPRE explica por stderr POR QUÉ está vacío -- un helper mudo hace que la persona
# termine en el login por email creyendo que su token no sirve, cuando el problema real es
# otro (perfil no detectado, permisos, archivo vacío, o contenido corrupto).
#
# Motivos concretos por los que este helper fallaba mudo en Windows (Git Bash / MSYS / WSL):
#  - HOME no siempre está definido ahí: se cae a USERPROFILE.
#  - USERPROFILE en Windows nativo trae backslashes ("C:\Users\nacho"): se normalizan a "/"
#    antes de armar la ruta -- un separador mezclado puede no resolver en algunas shells.
#  - Si ni HOME ni USERPROFILE están definidos, antes se armaba una ruta rota ("/.config/...")
#    y se buscaba ahí en silencio; ahora se avisa en vez de buscar a ciegas.
#  - Un token pegado/guardado desde Windows puede traer CRLF, BOM UTF-8 (EF BB BF) o, si el
#    archivo se creó con redirección de PowerShell 5.1 (Out-File es UTF-16 ahí por default),
#    BOM UTF-16 (FF FE / FE FF) con un byte NUL intercalado entre cada caracter. Los tres casos
#    se limpian antes de armar el header -- un BOM o un NUL invisible hacía que el server
#    devolviera 401 sin ninguna pista de por qué.
#  - Si después de limpiar quedan caracteres que un token real nunca tiene (comillas, espacios,
#    no-ASCII), se trata como corrupto: mejor fallar fuerte acá que mandar un Authorization roto
#    o un JSON inválido que el cliente MCP no sepa parsear en silencio.
#  - En máquinas donde no se puede escribir en el perfil, ONE_BRAIN_TOKEN sirve de alternativa
#    (misma limpieza + validación que el archivo).
#
# Locale fijo a C: los bytes de un BOM UTF-16 (FF FE) no son una secuencia UTF-8 válida, y bajo
# un locale UTF-8 (el default en casi toda instalación moderna) tanto sed como tr los rechazan
# con "illegal byte sequence" en vez de simplemente borrarlos -- el helper volvía a fallar mudo,
# ahora en el paso pensado para arreglar justo este caso. Con LC_ALL=C todo se trata como bytes
# crudos, sin validación de codificación.
export LC_ALL=C

BASE="${HOME:-$USERPROFILE}"
BASE=$(printf '%s' "$BASE" | tr '\\' '/')

REASON=""
TOKEN_FILE="${ONE_BRAIN_TOKEN_FILE:-}"
if [ -z "$TOKEN_FILE" ]; then
  if [ -z "$BASE" ]; then
    REASON="one-brain: no encontré la carpeta de tu usuario (ni HOME ni USERPROFILE están definidos). Seteá ONE_BRAIN_TOKEN o ONE_BRAIN_TOKEN_FILE a mano, o corré /one-brain:doctor para más detalle."
  else
    # La resolución por perfil vive en core/scripts/state-dir.sh (fuente única con el resto del
    # plugin: si esto y ob_state_dir se separan, el arranque lee un cerebro y las tools escriben
    # en otro). Si no se puede sourcear —instalación incompleta— se cae a la ruta de siempre en
    # vez de dejar la conexión sin token.
    OB_HDR_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
    if [ -r "$OB_HDR_DIR/../core/scripts/state-dir.sh" ]; then
      . "$OB_HDR_DIR/../core/scripts/state-dir.sh"
      # El MCP se conecta por su cuenta, sin pasar por el hook de arranque (session-start-lib.sh)
      # ni esperarlo: en un perfil recién creado no está garantizado que el hook corra ANTES de
      # esta conexión. Sin esta llamada acá también, esa primera conexión encontraría el cajón
      # vacío (todavía no heredó) y se quedaría sin token en silencio, aunque la máquina sí tenga
      # uno para heredar -- exactamente lo que la herencia existe para evitar. Silenciosa ante
      # fallo e idempotente, igual que en el arranque.
      #
      # ob_state_dir() resuelve el perfil con cksum/awk/basename/sed y varios subshells -- caro,
      # y esto corre en CADA conexión del MCP (el motivo de que este archivo esté separado de
      # capture-lib.sh, ver cabecera de state-dir.sh). ob_heredar_token la vuelve a calcular
      # puertas adentro, así que sin lo de abajo se resolvía DOS VECES por conexión (medido:
      # +71% en un perfil no-default). Se calcula UNA sola vez acá y se fija en
      # ONE_BRAIN_STATE_DIR, que ob_state_dir() ya mira primero y devuelve tal cual (gana sobre
      # todo) -- la llamada de adentro de ob_heredar_token queda gratis (una lectura de
      # variable), sin tocar ob_state_dir() ni su contrato para el resto del core.
      ONE_BRAIN_STATE_DIR=$(ob_state_dir)
      ob_heredar_token 2>/dev/null
      TOKEN_FILE="$ONE_BRAIN_STATE_DIR/token"
    else
      TOKEN_FILE="$BASE/.config/one-brain/token"
    fi
  fi
fi

# Limpieza compartida para archivo y variable de entorno: espacios/CR/LF/tabs, NUL (aparece
# cuando el archivo quedó en UTF-16 en vez de UTF-8/ASCII, con un byte NUL entre cada caracter
# ASCII) y los bytes de los 3 BOM conocidos (UTF-8 EF BB BF, UTF-16LE FF FE, UTF-16BE FE FF).
# No hace falta que el BOM esté justo al principio para borrarlo: un token real (ver la
# validación de más abajo) nunca tiene esos bytes, así que sacarlos donde sea es seguro.
ob_hdr_clean() {
  tr -d ' \t\r\n\000\357\273\277\377\376'
}

TOKEN=""
if [ -n "$TOKEN_FILE" ]; then
  if [ ! -e "$TOKEN_FILE" ]; then
    : # no existe: no es una falla nueva, es "todavía no conectaste" (mensaje final genérico)
  elif [ ! -r "$TOKEN_FILE" ]; then
    REASON="one-brain: $TOKEN_FILE existe pero no se puede leer (revisá permisos del archivo). Corré /one-brain:connect <token>."
  elif [ ! -s "$TOKEN_FILE" ]; then
    REASON="one-brain: $TOKEN_FILE está vacío. Corré /one-brain:connect <token>."
  else
    TOKEN=$(ob_hdr_clean < "$TOKEN_FILE")
  fi
fi

if [ -z "$TOKEN" ] && [ -n "${ONE_BRAIN_TOKEN:-}" ]; then
  TOKEN=$(printf '%s' "$ONE_BRAIN_TOKEN" | ob_hdr_clean)
fi

# Un token real es "ob_" + slug + "_" + hex: solo alfanumérico, "_" y "-" (ver
# src/lib/provision.ts). Si después de limpiar queda otra cosa, el archivo o la variable están
# corruptos -- se descarta con aviso en vez de mandar un header roto en silencio.
case "$TOKEN" in
  *[!A-Za-z0-9_-]*)
    REASON="one-brain: el token tiene caracteres inválidos después de limpiarlo (¿archivo corrupto o mal codificado?). Corré /one-brain:connect <token>."
    TOKEN=""
    ;;
esac

if [ -n "$TOKEN" ]; then
  printf '{"Authorization":"Bearer %s"}' "$TOKEN"
else
  printf '{}'
  # REASON ya trae su propia acción concreta cuando hay un motivo específico; si no hay
  # ninguno (caso normal: todavía no conectó nada), el mensaje genérico de siempre.
  echo "${REASON:-one-brain: sin token. Corré /one-brain:connect <token>.}" >&2
fi
