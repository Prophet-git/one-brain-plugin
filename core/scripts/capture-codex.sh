#!/bin/sh
# Lector del transcript de CODEX. Contesta la única pregunta del aviso de trabajo sin guardar:
# "¿qué quedó sin registrar en el cerebro en esta sesión?".
#
# Es el gemelo de ob_unsaved_kind (capture-lib.sh, el lector de Claude Code) y devuelve
# EXACTAMENTE el mismo vocabulario —"edits" | "cola" | "conversacion" | ""— porque quien lo
# consume es el mismo: stop-guard.sh anota el motivo en el marker y ob_pending_message decide,
# con ese motivo, si al arrancar grita o se calla. Los criterios (qué es trabajo, cuál es el
# umbral, qué reinicia el conteo, por qué la conversación posterior a un guardado NO justifica
# el grito de arranque) están razonados en el comentario largo de ob_unsaved_kind y no se
# repiten acá: lo que cambia es el FORMATO, no la política.
#
# El formato es lo que obligó a escribir un lector aparte en vez de parametrizar el de Claude
# Code. El rollout de Codex es JSONL donde cada línea es
#   {"timestamp":"…","type":"response_item"|"event_msg"|"turn_context"|"session_meta","payload":{…}}
# y adentro NO hay ninguna tool que se llame Edit ni Write. Verificado contra transcripts reales
# de Codex CLI 0.136 con gpt-5.5 (los fixtures de codex/tests/fixtures/ son esas sesiones):
#
#   1. Las ediciones llegan como payload.type == "custom_tool_call" con name "apply_patch", y el
#      patch entero viaja en "input". Un solo apply_patch puede tocar VARIOS archivos, así que
#      lo que se cuenta son los encabezados "*** Add File:" / "*** Update File:" /
#      "*** Delete File:", no las llamadas: contar llamadas dejaría una sesión que creó cinco
#      archivos en el mismo escalón que una que cambió una línea.
#   2. El shell llega como payload.type == "function_call" con name "exec_command" y el comando
#      JSON-escapado adentro de "arguments". Ahí aparecen los commits y los deploys —el mismo
#      criterio que en Claude Code— y también escrituras por redirección (`printf … > archivo`),
#      que es lo que el modelo hace cuando crea varios archivos de una sola pasada.
#   3. Un turno del usuario es UNA línea event_msg con payload.type == "user_message". El mismo
#      texto aparece TAMBIÉN como response_item/message role:"user", y encima Codex inyecta un
#      <environment_context> con ese mismísimo shape antes del primer turno. Contar por
#      "role":"user" convertiría un "hola" en tres turnos — que es, palabra por palabra, el
#      falso positivo que ya nos costó caro en Claude Code (medido: 8% de las sesiones).
#   4. Las tools MCP se nombran mcp__<server>__<tool> (verificado en el binario de Codex), o sea
#      que el guardado del cerebro llega como mcp__one-brain__brain_save. Por eso el patrón se
#      ancla al SUFIJO brain_save y no al nombre pelado.

# ob_unsaved_kind_codex <transcript>: "edits" | "cola" | "conversacion" | "" (nada pendiente).
ob_unsaved_kind_codex() {
  transcript="$1"
  [ -r "$transcript" ] || { printf ''; return; }
  awk -v min="${OB_UNSAVED_MIN_EDITS:-3}" '
    # Archivos tocados por un apply_patch. gsub devuelve la cantidad de reemplazos, así que
    # cuenta ocurrencias sin tener que iterar a mano. Trabaja sobre una copia (t) para no
    # ensuciar la línea.
    function archivos(s,   t) { t = s; return gsub(/\*\*\* (Add|Update|Delete) File:/, "", t) }

    # Escrituras por redirección adentro de un comando de shell. Es el punto donde este lector
    # puede volverse ruidoso, así que es deliberadamente CONSERVADOR: en la práctica, casi todos
    # los comandos de LECTURA llevan un > adentro (`2>/dev/null`, `>/dev/null 2>&1`, `>&2`) y si
    # contaran, tres greps seguidos gritarían "trabajo sin guardar". Un guard que grita después
    # de un "hola" enseña a ignorarlo, y ahí es cuando se pierde el trabajo de verdad.
    # Se descartan: los descriptores duplicados (>&1, >&2), todo lo que va a /dev/*, y los
    # destinos que no parecen un archivo (sin barra ni punto) — eso último ataja las
    # comparaciones tipo `if (a>b)` adentro de un awk o un test.
    function redirecciones(s,   n, partes, i, t, c) {
      c = 0
      n = split(s, partes, ">")
      for (i = 2; i <= n; i++) {
        t = partes[i]
        sub(/^[[:space:]]+/, "", t)
        if (t == "") continue                  # ">>" parte en dos: la mitad de adentro es vacía
        if (substr(t, 1, 1) == "&") continue   # >&1, >&2: no escriben ningún archivo
        sub(/[[:space:]"\\|;&()].*$/, "", t)   # quedarse con el primer token (el destino)
        if (t == "") continue
        if (t ~ /^\/dev\//) continue
        if (t !~ /[\/.]/) continue
        c++
      }
      return c
    }

    {
      # Sólo las LLAMADAS a tools cuentan, nunca sus salidas: el output de un comando puede
      # traer cualquier cosa —incluido el string `onebrain-save --type …` si alguien lee este
      # repo, o un `*** Add File:` si alguien imprime un patch— y tomarlo por trabajo (o peor,
      # por un guardado) es el error que ya cometimos una vez. Ojo con el ancla: la comilla de
      # cierre es lo que distingue "function_call" de "function_call_output".
      llamada = ($0 ~ /"type":[[:space:]]*"function_call"/) ||
                ($0 ~ /"type":[[:space:]]*"custom_tool_call"/) ||
                ($0 ~ /"type":[[:space:]]*"local_shell_call"/)

      if (llamada) {
        # Un guardado en el cerebro reinicia el conteo, por cualquiera de los dos canales.
        # El del bin se ancla a "onebrain-save --": el uso real SIEMPRE lleva flags, así que
        # una mención del comando (leer el archivo, nombrarlo) no se hace pasar por guardado.
        if ($0 ~ /"name":[[:space:]]*"[^"]*brain_save"/ || $0 ~ /onebrain-save --/) {
          w = 0; u = 0; next
        }
        w += archivos($0)
        # Un patch no se mira como shell: sus líneas "+" pueden contener cualquier cosa,
        # redirecciones incluidas, y ya se contó por archivo unas líneas más arriba.
        if ($0 !~ /\*\*\* Begin Patch/) w += redirecciones($0)
        if ($0 ~ /git commit/ || $0 ~ /vercel --prod/ || $0 ~ /vercel deploy/) w++
        next
      }

      if ($0 ~ /"type":[[:space:]]*"user_message"/) { u++; next }
    }
    END { print (w>=min) ? "edits" : (w>0 ? "cola" : (u>=3 ? "conversacion" : "")) }
  ' "$transcript"
}
