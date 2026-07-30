---
name: session-capture
description: Destilar el avance de la sesión y guardarlo en One Brain al cerrar. Se activa cuando el usuario señala que la sesión termina (dice "listo", "gracias", "terminamos", "eso es todo", se despide) o pide guardar el avance ("guardá esto", "metelo al cerebro"). También cuando un aviso de sesión anterior pide revisar trabajo sin guardar.
---

# Capturar la sesión en One Brain

Cerrás el loop de memoria: convertís el trabajo de la sesión en entries de One Brain, con el usuario confirmando antes de escribir.

## Cuándo actuás
- El usuario señala cierre ("listo", "gracias", "terminamos", se despide) y hubo trabajo real.
- El usuario pide guardar explícitamente ("guardá esto").
- Un aviso de `SessionStart` dice que la sesión anterior quedó con trabajo sin guardar: leé ese transcript (la ruta viene en el aviso) y aplicá lo mismo sobre él.

## Qué merece entrar al cerebro (el criterio)

Al cerebro entran **avances importantes, decisiones y avisos**. Nada más. Es memoria de
empresa, no un registro de actividad: cada entrada que no aporta le agrega ruido a la
próxima búsqueda de otra persona.

**Guardá** cuando pasó algo que otro (o vos en dos semanas) necesita saber para no repetir
trabajo ni decidir de nuevo:
- un frente que avanzó de verdad: se terminó, se deployó, se entregó, se rompió;
- una decisión y **su porqué** — sobre todo si reemplaza una anterior (usá `supersedes`);
- algo que se aprendió y no está escrito en ningún lado: una restricción del cliente, una
  limitación de una herramienta, por qué un camino no funcionó;
- un aviso que cambia lo que hay que hacer: un bloqueante, un pendiente que quedó abierto.

**No guardes** (por más que haya llevado tiempo):
- verificaciones y chequeos de estado ("confirmé que la versión es la X", "los tests pasan");
- exploración, lectura de código, respuestas a preguntas del usuario;
- lo que ya queda registrado en otro lado: el detalle de un commit, el diff, la config;
- pasos intermedios de algo que todavía no cerró — para eso está la skill `handoff`;
- reformulaciones de una entrada que ya existe.

Prueba rápida antes de proponer: **si dentro de dos semanas nadie la buscaría, no va.** Ante
la duda, no la guardes y decilo: es más barato perder una nota menor que ensuciar la memoria.

### Si no entra, son dos memorias (no una larga)

El contenido topea en 20.000 caracteres, y el tope existe por la búsqueda: cada memoria se
guarda con **un solo vector**, así que una nota larga que toca cinco temas produce un
embedding que queda en el promedio de todos y no representa bien a ninguno — deja de aparecer
justo cuando alguien la busca por uno de esos temas.

Por eso, si lo que ibas a guardar no entra:

- **Casi siempre son varias memorias distintas.** Una por frente, con su propio título. Se
  buscan mejor y se leen mejor.
- **Si es un documento largo de verdad** (un plan, un contrato, un informe), no va adentro del
  cerebro: vive donde le corresponde —el repositorio, el drive— y la memoria guarda el puntero
  más las decisiones que se tomaron. Un documento copiado al cerebro se desincroniza del
  original en días.
- **Recortar a lo bruto para que entre es la peor opción**: perdés justo el final, que suele
  ser dónde está lo que falta hacer.

En perspectiva: la mediana real es de unos 2.000 caracteres y sólo el 0,5% de las memorias
toca el techo. Si estás cerca del límite, casi seguro no destilaste lo suficiente.

Y siempre, sin excepción: **proponer antes de escribir** (paso 3) y guardar sólo con el OK.
Si el usuario descarta, no guardes ni insistas.

## Qué hacés
0. **Chequeá el feature.** Corré en Bash: `onebrain-feature auto-capture`. Si sale con exit 1
   (el usuario desactivó "Captura automática" al cerrar sesión), NO hagas nada: terminá en silencio.
1. Destilá los **avances y decisiones reales** de la sesión (o del transcript indicado). No trivialidades, no cada comando: lo que tenga señal.
2. Para cada uno, armá un entry siguiendo el patrón de `brain_save`:
   - `type`: avance | decision | conocimiento | evento | handoff
   - `title` (3-200), `content_md` (resumen autocontenido, 2-10 líneas)
   - `entities`: clientes/proyectos/personas/temas tocados
   - `level`: por defecto tu nivel; ofrecé cambiarlo si es sensible
   - `supersedes`: si reemplaza o CORRIGE una memoria anterior (de cualquier tipo, no sólo decisiones), su id
3. **Proponé** el/los resúmenes al usuario ANTES de escribir: "voy a guardar esto: […] · ¿ok / editás / descartás?".
4. Con el OK → guardá cada entry corriendo en Bash el comando **`onebrain-save`** (canal Bash,
   funciona aunque la tool MCP esté deferred/no cargada todavía en la sesión):
   `onebrain-save --type <type> --title "<title>" --content "<content_md>" --entities "a,b"`
   - Si imprime un `entry_id` → guardó OK. Reportalo.
   - Si dice **"el server rechazó la memoria"** (un 4xx: título vacío o demasiado largo, contenido
     que no pasa la validación) → **NO quedó encolado** y así no va a entrar nunca. Corregí lo que
     el error señala y reintentá EN EL MOMENTO. No le digas al usuario que quedó pendiente: no lo
     está. Reintentar sin cambiar nada es perder el tiempo, y encolarlo era condenarlo a fallar en
     cada arranque mientras el usuario creía que estaba a salvo.
   - Si dice **"encolo para reintento"** (server caído, sin red, rate limit) → quedó **encolado**
     para el próximo arranque. Avisá al usuario que quedó pendiente, no perdido — no es una falla
     que tengas que resolver vos ahora.
   - Si la decisión que estás guardando **reemplaza a una anterior**, agregá
     `--supersedes <uuid-de-la-vieja>` (el id lo sacás con `brain_search`; sirve para cualquier tipo de memoria, no sólo decisiones — usalo también cuando lo guardado antes resultó estar equivocado): la vieja queda
     invalidada, no borrada. Sin esto el cerebro acumula decisiones contradictorias sin ninguna
     señal de cuál vale. Si el bin avisa que no encontró esa decisión, el id estaba mal: la
     memoria nueva se guardó igual, pero la vieja sigue vigente — buscá el id bueno y decilo.
5. Si el usuario descarta, no guardes. Si hubo varios frentes, varios entries. Si no hubo nada guardable, decilo y no inventes.
6. **Si estabas actuando sobre un rescate** (el aviso de `SessionStart` que menciona un transcript de una sesión anterior sin guardar): el aviso solo trae la RUTA del transcript, no el session-id explícito — sacalo del nombre de archivo del transcript SIN la extensión `.jsonl` (ej: si la ruta es `.../abc-123-def.jsonl`, el session-id es `abc-123-def`). Una vez que el guardado quedó CONFIRMADO (entry_id devuelto), corré en Bash `onebrain-resolve-pending <session-id>` para borrar esa marca. Si el guardado FALLÓ o quedó encolado, **NO** la borres: tiene que seguir avisando hasta que se guarde de verdad. El aviso insiste hasta 3 arranques y después descarta la marca solo (la última vez lo dice explícitamente): si ves esa advertencia, es la última oportunidad de rescatar ese transcript — decíselo al usuario antes de seguir con otra cosa.

## Reglas
- Nunca guardes datos personales sensibles ni secrets.
- Si `brain_save` falla (server pausado, red), avisá al usuario y NO des el avance por perdido: quedará pendiente para el próximo cierre.
