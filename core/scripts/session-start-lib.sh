#!/bin/sh
# Arranque de sesión: TODO lo que NO depende del programa host (Claude Code, Codex).
#
# Por qué esto vive en core/ y no copiado adentro de cada paquete: de las ~280 líneas que
# tenía el arranque, sólo CUATRO cosas dependen del host —cómo se resuelve el token para las
# tools, qué ruta se le informa al modelo como canal de guardado, el valor del header x-client
# y cómo se emite el resultado—. Todo el resto (qué se pide, en qué orden se ensambla, el
# presupuesto de caracteres, la instrucción de atribución, la telemetría de entrega) es One
# Brain, no el programa que lo hospeda. Duplicarlo garantiza que en tres meses los dos archivos
# digan cosas distintas y que un arreglo viva en uno solo — exactamente lo que core/ vino a
# evitar. Los adaptadores (plugin/scripts/session-start.sh, codex/scripts/session-start.sh)
# configuran sus cuatro diferencias y llaman acá.
#
# Se SOURCEA (no se ejecuta). Requiere capture-lib.sh ya cargado: lo hace el adaptador, que es
# el que sabe dónde está parado.
#
# --- Contrato con el adaptador ---------------------------------------------------------------
# Entradas (variables, seteadas por el adaptador ANTES de llamar a ob_session_start):
#   OB_PKG_ROOT  raíz del paquete instalado; de ahí sale la versión que se reporta al server.
#   OB_SAVE_BIN  ruta del canal de guardado que se le informa al modelo. Es host-específica a
#                propósito: en Claude Code es el puente de bin/, que ya circula en las sesiones
#                abiertas de los clientes y no se puede mover sin romperlas.
#   OB_CLIENT    valor del header x-client (claude | codex).
# Salidas (variables, para que el adaptador las entregue como su host espera):
#   OB_STDOUT    el bloque de contexto ya ensamblado y recortado; "" si no hay nada que decir.
# La telemetría de entrega la registra esta librería, no el adaptador: se mide sobre el string
# EXACTO que el adaptador va a entregar ($OB_STDOUT), y dejarla en manos de cada adaptador es
# pedir que alguno se la olvide. (Que se registre justo antes del printf en vez de justo
# después no cambia nada: va a un archivo, no a stdout.)

# Techo del bloque entero. NO se toca sin medir: si el arranque se pasa, Claude Code reemplaza
# todo por un preview de 2 KB y un puntero a un archivo que nadie lee — el contexto del equipo
# desaparece sin que nadie se entere. Medimos que el techo de Codex son 10.000 bytes (y que
# pasarse ahí es menos grave: conserva cabeza y cola) y el de Claude Code es más bajo. El número
# lo manda el más restrictivo, así que 8000 vale para los dos paquetes.
OB_MAX_TOTAL=8000

# ob_feat_on <slug>: 0 (on) si el feature no está explícitamente en false, o si no
# hay features.json cacheado (default ON). Misma lógica que core/bin/onebrain-feature.
# Se usa ANTES de llamar al server a propósito: dos de las llamadas del arranque tienen EFECTO
# (/api/synthesis reclama el candado atómico del día, /api/mentions marca resoluciones como
# vistas). Antes se llamaban siempre y el resultado se descartaba después, así que alguien con
# la síntesis apagada le bloqueaba el día a todo su equipo por 6 horas en cada arranque, y
# perdía avisos de menciones en silencio. Lee el cache del arranque anterior, que es
# exactamente lo que corresponde para decidir si vale la pena llamar.
ob_feat_on() {
  FFILE="$HOME/.config/one-brain/features.json"
  [ -r "$FFILE" ] || return 0
  ! grep -qE "\"$1\"[[:space:]]*:[[:space:]]*false" "$FFILE" 2>/dev/null
}

# ob_client_name: cómo se llama, en el idioma del usuario, el programa que hospeda esta sesión.
# Sale de OB_CLIENT, que ya setean los dos adaptadores para el header x-client.
#
# Existe porque el core emite texto que LEE UNA PERSONA, y hasta ahora ese texto tenía el
# nombre de un solo host escrito a mano — el de Claude Code, que era el único cuando se
# escribió. En Codex nombraba el programa equivocado justo en el aviso que sale cuando algo se
# rompió: la persona sale a revisar una instalación que no tiene.
#
# El default es "Claude Code" a propósito, y no vacío: hay cuatro instalaciones en producción
# leyendo ese texto, así que un host que se olvide de setear OB_CLIENT (o un sourceo suelto del
# core desde un test) tiene que seguir produciendo LA MISMA frase de siempre, no una con un
# agujero en el medio.
ob_client_name() {
  case "$OB_CLIENT" in
    codex) printf 'Codex' ;;
    *)     printf 'Claude Code' ;;
  esac
}

# --- Ensamblado: helpers ----------------------------------------------------------------------
ob_append() { [ -n "$1" ] || return 0; if [ -n "$CONTEXT" ]; then CONTEXT="$CONTEXT$NL$NL$1"; else CONTEXT="$1"; fi; }
# ob_clip_block deja el resultado en $OB_BLOCK en vez de imprimirlo: usado en $(...) el registro
# del recorte se perdería en el subshell, que es justo el dato que la telemetría necesita.
ob_clip_block() { # <texto> <max_chars> <nombre-del-bloque>
  OB_BLOCK=""
  [ -n "$1" ] || return 0
  OB_BLOCK=$(printf '%s' "$1" | ob_clip "$2")
  # ob_clip marca el recorte en el propio texto: usar esa marca (y no una estimación de
  # tamaño) es medir lo que efectivamente pasó, no lo que suponemos que pasó.
  case "$OB_BLOCK" in
    # Se ancla al PREFIJO, no a la marca completa: el texto que sigue explica cómo recuperar
    # lo recortado y se va a seguir puliendo. Con el literal entero, cambiarle una palabra a
    # ese mensaje apagaba la telemetría en silencio — pasó al agregarle el aviso de brain_get,
    # y sólo se notó porque un test lo cazó.
    *'[...recortado'*) OB_CLIPPED="$OB_CLIPPED${OB_CLIPPED:+,}$3" ;;
  esac
}
ob_append_clipped() { ob_clip_block "$1" "$2" "$3"; ob_append "$OB_BLOCK"; }

# ob_session_start — el arranque entero. Lee el input del hook de stdin (los dos programas lo
# pasan igual: un JSON con session_id, cwd, transcript_path...). Silencioso ante cualquier
# fallo: nunca bloquea el arranque de una sesión.
ob_session_start() {
  # Reintentar guardados que quedaron en cola (offline previo). BACKGROUNDEADO A PROPÓSITO:
  # el propio bloque de abajo ya backgroundea sus curls (context/synthesis/etc.) para acotar el
  # arranque a ~8s (la MÁS lenta, no la suma; ver comentario más abajo) — si el flush corriera
  # acá de forma sincrónica, sumaría hasta 20×8s ANTES de que ese bloque siquiera arranque. El
  # subshell "( ... & )" lanza el flush y sigue de largo sin esperarlo (fire-and-forget): el
  # arranque nunca queda bloqueado por la cola, sin importar cuán lenta/caída esté la red.
  ( ob_flush_queue >/dev/null 2>&1 & )

  INPUT=$(cat 2>/dev/null)
  SESSION=$(ob_json_field session_id "$INPUT")
  # Self-test del parser (Capa 3): ¿el hook puede leer el input en ESTE entorno? Se reporta al
  # server (header x-hook-ok) para que el operador lo vea en el panel, y si falla se avisa fuerte
  # en el contexto de arranque. Nunca en silencio.
  HOOK_OK=$(ob_selftest)

  TOKEN_FILE="$HOME/.config/one-brain/token"
  URL="${ONE_BRAIN_URL:-https://onebrain.prophet.lat}"
  BRIEF=""; SYN=""; HELLO=""; RESUME=""; MENTIONS=""; MATERIAL=""; SAVEBIN=""; TOKENWARN=""; HAS_TOKEN=0
  if [ -r "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
    HAS_TOKEN=1
    TOKEN=$(tr -d ' \t\r\n' < "$TOKEN_FILE")
    # Recordatorio del canal de guardado a prueba de "deferred": SOLO en instalaciones YA
    # onboardeadas (con token). Sin token, onebrain-save encola en silencio para siempre (nunca
    # guarda de verdad) — mostrar este mensaje ahí sería engañoso, así que va adentro del gate.
    # La ruta la pone el adaptador (OB_SAVE_BIN): cada programa tiene la suya.
    SAVEBIN="Para guardar en One Brain usá el comando: $OB_SAVE_BIN (canal Bash, no depende de la tool MCP)."
    # Versión instalada del paquete (del manifest). Se reporta piggyback en la llamada de contexto
    # (x-plugin-version) para que el panel avise SOLO si estás atrasado — Fase 2 del aviso de update.
    # Los dos paquetes traen el mismo dato en un manifest con distinto nombre (.claude-plugin /
    # .codex-plugin): se prueban los dos y gana el que exista. Es puro accidente del formato de
    # cada marketplace, no una diferencia de producto, así que no merece otra perilla.
    PLUGIN_VERSION=""
    for _obm in "$OB_PKG_ROOT/.claude-plugin/plugin.json" "$OB_PKG_ROOT/.codex-plugin/plugin.json"; do
      [ -r "$_obm" ] || continue
      PLUGIN_VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_obm" 2>/dev/null | head -n1)
      [ -n "$PLUGIN_VERSION" ] && break
    done
    GREETED_MARKER="$HOME/.config/one-brain/greeted"
    DO_HELLO=0; [ ! -e "$GREETED_MARKER" ] && DO_HELLO=1

    # Las 5-6 llamadas de arranque son INDEPENDIENTES entre sí → se disparan en PARALELO (curl en
    # background a archivos temporales) y se espera a todas juntas con `wait`. Antes eran secuenciales
    # (hasta 6×8s de espera acumulada en el peor caso); ahora el arranque tarda lo que la MÁS lenta
    # (~8s tope), no la suma. Silencioso ante fallo, igual que antes.
    OB_TMP=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/ob-start-$$")
    mkdir -p "$OB_TMP" 2>/dev/null

    # -w '\n%{http_code}': el body y el http status quedan en el mismo archivo (código al final),
    # así detectamos un token vencido/inválido (401/403) sin una llamada extra. Se separan abajo,
    # DESPUÉS del wait — ver Task 8 (fail-loud de token vencido).
    # x-client: qué programa es esta máquina (claude | codex). Lo pone el adaptador; el server lo
    # usa para saber desde dónde entra cada cliente sin tener que adivinarlo por el user-agent.
    curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" -H "x-plugin-version: $PLUGIN_VERSION" -H "x-hook-ok: $HOOK_OK" -H "x-client: $OB_CLIENT" -w '\n%{http_code}' "$URL/api/context"   > "$OB_TMP/context.raw"   2>/dev/null &
    # ?peek=1: sólo pregunta si hay día sin sintetizar. Sin peek, este GET TOMA el candado del
    # día y se trae ~24 KB de material — se hacía en cada arranque, casi nunca se usaba, y ese
    # peso era lo que hacía que Claude Code truncara todo el contexto de arranque.
    ob_feat_on daily-synthesis && curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/synthesis?peek=1" > "$OB_TMP/synthesis" 2>/dev/null &
    # Continuidad: el handoff más reciente del PROPIO usuario (≤3 días), para retomar donde quedó.
    curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/resume"    > "$OB_TMP/resume"    2>/dev/null &
    # Menciones pendientes que te dejó un compañero (string ya formateado, o "" si no hay).
    # También tiene efecto: marca las resoluciones como vistas. Mismo criterio que arriba.
    ob_feat_on menciones && curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/mentions"  > "$OB_TMP/mentions"  2>/dev/null &
    # Material sin amasar que la propia persona subió (string ya formateado, o "" si no hay).
    ob_feat_on material && curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/material-pendiente" > "$OB_TMP/material" 2>/dev/null &
    # Features del usuario (toggles). Silencioso ante fallo → se conserva el features.json anterior.
    curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/features"  > "$OB_TMP/features"  2>/dev/null &
    # First-run "el cerebro habla primero" (#21): SOLO la primera vez que este usuario conecta.
    [ "$DO_HELLO" = 1 ] && curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" "$URL/api/hello" > "$OB_TMP/hello" 2>/dev/null &

    wait  # esperar a que TODAS las llamadas en background terminen antes de parsear

    # Separar body/http_code de /api/context ANTES de parsear nada (Task 8). El orden importa:
    # $OB_TMP/context tiene que quedar como el BODY puro para que ob_json_field (Task 9) lo lea bien.
    CTX_CODE=$(tail -n1 "$OB_TMP/context.raw" 2>/dev/null)
    sed '$d' "$OB_TMP/context.raw" > "$OB_TMP/context" 2>/dev/null
    TOKENWARN=$(ob_token_warning "$CTX_CODE")

    # Parser ESTRUCTURAL (ob_json_field), no sed: el sed line-oriented anterior rompía con
    # pretty-print o comillas escapadas adentro del valor (mismo bug de fondo que ob_json_field
    # ya resuelve para el input del hook). ob_json_field recibe un STRING, no un archivo.
    BRIEF=$(ob_json_field brief "$(cat "$OB_TMP/context" 2>/dev/null)")
    # Aviso de update, YA REDACTADO por el server (viene sólo si esta versión quedó atrasada).
    # La comparación de versiones se hace allá a propósito: acá no hay con qué comparar semver de
    # forma confiable, y el texto —incluido el comando— se puede corregir sin que nadie actualice
    # el plugin, que es justo el problema que este aviso viene a resolver.
    UPDATEWARN=$(ob_json_field update "$(cat "$OB_TMP/context" 2>/dev/null)")
    # De la síntesis sólo viene el día pendiente. El material se pide recién cuando la persona
    # dice que sí — con la orden concreta que va en el aviso de abajo.
    SYN_DAY=$(ob_json_field period_key "$(cat "$OB_TMP/synthesis" 2>/dev/null)")
    [ -n "$SYN_DAY" ] && SYN="One Brain: el día $SYN_DAY quedó sin sintetizar. Si el usuario quiere que la hagas, traé el material con: curl -s -H \"Authorization: Bearer \$(cat ~/.config/one-brain/token)\" $URL/api/synthesis"
    RESUME=$(ob_json_field resume "$(cat "$OB_TMP/resume" 2>/dev/null)")
    MENTIONS=$(ob_json_field mentions "$(cat "$OB_TMP/mentions" 2>/dev/null)")
    MATERIAL=$(ob_json_field material "$(cat "$OB_TMP/material" 2>/dev/null)")

    # First-run: parsear el saludo y apagar el marker para siempre (exista o no la respuesta).
    if [ "$DO_HELLO" = 1 ]; then
      HELLO=$(sed -n 's/.*"hello":"\(.*\)"}/\1/p' "$OB_TMP/hello" 2>/dev/null)
      mkdir -p "$HOME/.config/one-brain" 2>/dev/null
      printf '' > "$GREETED_MARKER" 2>/dev/null
    fi

    # Cachear features solo si la respuesta trae el objeto (si no responde, se conserva el anterior).
    FEATURES=$(cat "$OB_TMP/features" 2>/dev/null)
    case "$FEATURES" in
      *'"features"'*)
        mkdir -p "$HOME/.config/one-brain" 2>/dev/null
        printf '%s' "$FEATURES" \
          | sed -n 's/.*"features":[[:space:]]*\({.*}\)}/\1/p' \
          > "$HOME/.config/one-brain/features.json" ;;
    esac

    rm -rf "$OB_TMP" 2>/dev/null
  fi

  # Segundo gate, ahora sobre el contenido: el de arriba evitó la llamada, éste evita mostrarlo
  # (cubre el caso de que el features.json haya cambiado en esta misma corrida).
  ob_feat_on team-digest || BRIEF=""
  ob_feat_on daily-synthesis || SYN=""
  ob_feat_on session-resume || RESUME=""
  ob_feat_on menciones || MENTIONS=""
  ob_feat_on material || MATERIAL=""

  # Aviso de reuniones sin sincronizar (feature 'reuniones', máx 1×/día). No llama a API/MCP:
  # solo invita a activar la skill. Idempotente por día vía marker en el pending-dir.
  # SOLO con token (instalación onboardeada) — sin token el plugin no está conectado y no debe
  # emitir NADA (mismo criterio que SAVEBIN); antes disparaba igual porque ob_feat_on da default ON
  # sin features.json, y esta llamada no dependía del gate de token como el resto del bloque.
  REUNMSG=""
  if [ "$HAS_TOKEN" = "1" ] && ob_feat_on reuniones; then
    RDAY=$(date +%Y%m%d 2>/dev/null)
    RMARK="$(ob_pending_dir)/reuniones-reminded-$RDAY"
    if [ -n "$RDAY" ] && [ ! -e "$RMARK" ]; then
      mkdir -p "$(ob_pending_dir)" 2>/dev/null
      printf '' > "$RMARK" 2>/dev/null
      REUNMSG="Puede que tengas reuniones nuevas de Granola sin sincronizar al cerebro. Si querés, activá la skill reuniones: trae las nuevas, las guarda y te ofrece destilar decisiones/avances."
    fi
  fi

  # Fallback de captura: marker pending-* de una sesión DISTINTA de la actual, INACTIVA
  # (ob_is_stale). NO borra la marca al avisar — antes sí lo hacía y, si el modelo no actuaba
  # ese único aviso, el trabajo se perdía para siempre. Ahora la marca se borra SOLO cuando
  # session-capture confirma el guardado (ob_resolve_pending), y este aviso INSISTE en cada
  # arranque hasta que eso pase.
  #
  # Antes del aviso, la caducidad: markers de sesiones muertas hace rato que nadie va a rescatar.
  # Es lo único que corre sin depender de que la sesión dueña siga viva, así que si no está acá
  # el pending-dir crece sin techo y el arranque SIEMPRE encuentra de qué quejarse.
  ob_gc_pending
  PENDMSG=$(ob_pending_message "$SESSION")

  # Memorias que el server RECHAZÓ: salieron del ciclo de reintento (dead-letter) para no
  # reintentarse eternamente, pero el contenido es de alguien y no puede desaparecer callado.
  DEADMSG=$(ob_dead_message)

  # Aviso de captura degradada (Capa 3): si el self-test falló, la captura automática NO va a
  # funcionar en este entorno. Se avisa arriba de todo, es lo más urgente.
  #
  # El nombre del programa sale de ob_client_name (OB_CLIENT, lo pone el adaptador): este texto
  # es lo primero que lee alguien que ya sabe que algo no anda, y nombrarle el programa
  # equivocado justo ahí lo manda a buscar el problema donde no está. El default conserva el
  # texto histórico, palabra por palabra, para las instalaciones que ya están en producción.
  HOOKWARN=""
  if [ "$HOOK_OK" != "1" ]; then
    HOOKWARN="⚠️ One Brain: la captura automática NO está operativa en este entorno — el hook no puede parsear el input de $(ob_client_name) (instalá jq o python3, o actualizá el plugin one-brain). Mientras tanto, tus avances NO se guardan solos: guardá manualmente con brain_save. Mostrale este aviso al usuario."
  fi

  # --- Ensamblado -------------------------------------------------------------------------
  #
  # Dos reglas, las dos aprendidas a los golpes (medido sobre 24 sesiones reales: sólo el 29%
  # recibía el contexto entero):
  #
  # 1) SALIDA SIN ANDAMIAJE PROPIO. Lo que se arma acá es TEXTO PLANO. Antes esto se emitía como
  #    JSON armado con printf, y el brief trae comillas y saltos de línea REALES (ob_json_field
  #    los decodifica): el JSON quedaba inválido y Claude Code lo descartaba, o peor, mostraba el
  #    andamiaje crudo en pantalla. Si un host necesita un sobre (Codex lo pide), lo arma SU
  #    adaptador sobre este texto, que es el único lugar donde ese escapeo se puede testear.
  #
  # 2) PRESUPUESTO. Si el bloque pasa de ~9 KB, Claude Code lo reemplaza por un preview de 2 KB
  #    y un puntero a un archivo que nadie lee — o sea, el contexto del equipo desaparece sin
  #    que nadie se entere. Cada bloque grande tiene su tope y el total tiene un techo.
  #
  # 3) EL ORDEN DECIDE QUIÉN SOBREVIVE. El techo recorta por el FINAL, así que primero van los
  #    avisos operativos y las instrucciones (cortos, y lo que se pierde no se recupera: un
  #    "quedó trabajo sin guardar" que no se emite es trabajo que nadie va a guardar) y al final
  #    el MATERIAL (resume/menciones/brief), que se vuelve a pedir en el próximo arranque.
  #    Antes estaba al revés: con el brief real de prod (5.431 chars) + un resume largo +
  #    menciones, la salida pegaba el techo y se comía el aviso de trabajo sin guardar, el
  #    recordatorio del canal de guardado y media orden de curl de la síntesis. Verificado
  #    ejecutando el hook contra un server con el material real.
  NL='
'
  CONTEXT=""
  OB_CLIPPED=""   # qué bloques hubo que recortar (telemetría de entrega, al final de la función)
  OB_BLOCK=""     # salida de ob_clip_block: el bloque ya recortado

  # --- Primero lo que no puede perderse: avisos operativos e instrucciones (todos cortos) ---
  ob_append "$TOKENWARN"                 # token vencido: sin esto nada funciona
  ob_append "$HOOKWARN"                  # captura rota en este entorno
  ob_append "$UPDATEWARN"                # plugin viejo: los arreglos viajan en la versión
  ob_append "$DEADMSG"                   # memorias que el server rechazó y nadie va a reintentar
  ob_append "$PENDMSG"                   # quedó trabajo sin guardar
  ob_append "$SYN"                       # una línea: hay día sin sintetizar
  ob_append "$REUNMSG"
  ob_append "$SAVEBIN"

  # --- Después el material, que es lo recortable ---
  ob_append_clipped "$RESUME" 2500 resume        # dónde quedaste
  ob_append_clipped "$MENTIONS" 800 menciones    # lo que te dejó un compañero
  ob_append_clipped "$MATERIAL" 600 material     # documentos que subiste y no estudiaste
  ob_append_clipped "$HELLO" 1200 hello          # bienvenida (sólo la primera vez)
  if [ -n "$BRIEF" ]; then
    # El brief va ÚLTIMO: es el bloque más grande y el único que el techo puede morder sin costo
    # (se vuelve a pedir en el próximo arranque).
    ob_clip_block "# One Brain — contexto del equipo$NL$BRIEF" 3500 brief
    # T1.3 — HACER VISIBLE EL RETORNO.
    # Todo esto entra como additionalContext de un hook: lo consume el MODELO, y la persona nunca
    # ve que lo que Claude "ya sabe" lo escribió un compañero. El momento "ajá" del producto es
    # exactamente ese cruce entre dos personas, y hoy sólo ocurre en la reunión de venta, nunca
    # adentro del producto. Lo que no se atribuye, no se renueva.
    #
    # La instrucción va ANTES del brief a propósito (regla 3): si el techo pega, lo que se corta
    # es el final del material, no la instrucción que hace que el material se atribuya.
    #
    # Y se adapta al material: el brief viene de buildTeamBrief, que formatea cada entrada como
    # "- **Título** ([[Autor]] · 24/07/2026): ..." — pero el autor sale de users.name, que puede
    # ser null, y encima el recorte a 3500 puede dejar afuera la parte firmada. Por eso el chequeo
    # es sobre el texto YA RECORTADO ($OB_BLOCK), no sobre el brief entero: pedirle al modelo que
    # nombre a una persona que no está en el material es pedirle que la invente, y una atribución
    # falsa hace más daño que ninguna.
    #
    # Se busca la FIRMA COMPLETA "([[Alguien]] · " y no un simple "[[": los cuerpos de las memorias
    # están llenos de wikilinks (así escribe el equipo), así que detectar por corchetes haría que
    # en un brief sin autor le pidiéramos atribuir a una nota en vez de a una persona.
    if printf '%s' "$OB_BLOCK" | grep -q '(\[\[[^]]*\]\] · '; then
      # El "sin los corchetes" no es cosmético: probado con el brief real, el modelo copiaba la
      # firma tal cual y le escribía "[[Bauti]]" a la persona. El wikilink es sintaxis interna del
      # cerebro; lo que la persona tiene que leer es un nombre.
      ATRIBUCION="Antes de responder lo primero que te pida el usuario, escribí UNA sola línea que empiece con \"One Brain:\" diciendo qué te trajo el cerebro del equipo y quién lo escribió: el nombre de la persona (en el material figura entre corchetes dobles, ej. [[Fran]]; escribilo SIN los corchetes) y la fecha que está al lado. Ejemplo: \"One Brain: traje la decisión de pasar la carga a Postgres, la escribió Fran el 24/07/2026\". Una línea sola, y seguí con lo que te pidieron. No inventes autor ni fecha: si algo no los trae, no se lo atribuyas a nadie."
    else
      ATRIBUCION="Antes de responder lo primero que te pida el usuario, escribí UNA sola línea que empiece con \"One Brain:\" diciendo qué te trajo el cerebro del equipo y de cuándo es. Ejemplo: \"One Brain: traje el último movimiento del equipo, del 24/07/2026\". Una línea sola, y seguí con lo que te pidieron. Lo que llegó no viene firmado, así que no se lo atribuyas a ninguna persona: no inventes autores."
    fi
    ob_append "$ATRIBUCION"
    ob_append "$OB_BLOCK"
  fi

  # --- Entrega ------------------------------------------------------------------------------
  # Techo final, por si la suma de los topes se pasa igual (varios bloques grandes a la vez).
  OB_TECHO=no
  if [ "$(printf '%s' "$CONTEXT" | ob_chars)" -gt "$OB_MAX_TOTAL" ] 2>/dev/null; then OB_TECHO=si; fi
  OB_OUT=$(printf '%s\n' "$CONTEXT" | ob_clip "$OB_MAX_TOTAL")
  [ -n "$CONTEXT" ] && OB_STDOUT="$OB_OUT$NL$NL" || OB_STDOUT=""

  # Telemetría de ENTREGA: qué sale de acá, medido sobre el string exacto que el adaptador va a
  # entregar y no sobre lo que creemos que se escribió. Es lo único que después permite contestar
  # "¿el contexto del equipo llegó entero?" sin adivinar — el 62% de las sesiones se perdía por
  # tamaño y nadie se enteraba. Va a un archivo local; el contexto del modelo no lleva ni un
  # carácter de esto.
  ob_log_delivery "$SESSION" \
    "$(printf '%s' "$OB_STDOUT" | ob_chars)" \
    "$(printf '%s' "$OB_STDOUT" | wc -c | tr -d ' ')" \
    "$OB_CLIPPED" "$OB_TECHO"
}
