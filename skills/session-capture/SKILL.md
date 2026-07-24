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

## Qué hacés
0. **Chequeá el feature.** Corré en Bash: `onebrain-feature auto-capture`. Si sale con exit 1
   (el usuario desactivó "Captura automática" al cerrar sesión), NO hagas nada: terminá en silencio.
1. Destilá los **avances y decisiones reales** de la sesión (o del transcript indicado). No trivialidades, no cada comando: lo que tenga señal.
2. Para cada uno, armá un entry siguiendo el patrón de `brain_save`:
   - `type`: avance | decision | conocimiento | evento | handoff
   - `title` (3-200), `content_md` (resumen autocontenido, 2-10 líneas)
   - `entities`: clientes/proyectos/personas/temas tocados
   - `level`: por defecto tu nivel; ofrecé cambiarlo si es sensible
   - `supersedes`: si reemplaza una decisión anterior, su id
3. **Proponé** el/los resúmenes al usuario ANTES de escribir: "voy a guardar esto: […] · ¿ok / editás / descartás?".
4. Con el OK → guardá cada entry corriendo en Bash el comando **`onebrain-save`** (canal Bash,
   funciona aunque la tool MCP esté deferred/no cargada todavía en la sesión):
   `onebrain-save --type <type> --title "<title>" --content "<content_md>" --entities "a,b"`
   - Si imprime un `entry_id` → guardó OK. Reportalo.
   - Si NO imprime id (el server estaba caído o sin red) → quedó **encolado** para reintento en
     el próximo arranque. Avisá al usuario que quedó pendiente, no perdido — no es una falla que
     tengas que resolver vos ahora.
   - Si necesitás `level` o `supersedes` no-default, `onebrain-save` no los expone: usá la tool
     MCP `brain_save` en su lugar si está cargada en la sesión (mismo lugar de guardado, ambas
     sirven — la MCP cuando está disponible, `onebrain-save` siempre).
5. Si el usuario descarta, no guardes. Si hubo varios frentes, varios entries. Si no hubo nada guardable, decilo y no inventes.
6. **Si estabas actuando sobre un rescate** (el aviso de `SessionStart` que menciona un transcript de una sesión anterior sin guardar): el aviso solo trae la RUTA del transcript, no el session-id explícito — sacalo del nombre de archivo del transcript SIN la extensión `.jsonl` (ej: si la ruta es `.../abc-123-def.jsonl`, el session-id es `abc-123-def`). Una vez que el guardado quedó CONFIRMADO (entry_id devuelto), corré en Bash `onebrain-resolve-pending <session-id>` para borrar esa marca — recién ahí para de insistir en cada arranque. Si el guardado FALLÓ o quedó encolado, **NO** la borres: tiene que seguir avisando hasta que se guarde de verdad.

## Reglas
- Nunca guardes datos personales sensibles ni secrets.
- Si `brain_save` falla (server pausado, red), avisá al usuario y NO des el avance por perdido: quedará pendiente para el próximo cierre.
