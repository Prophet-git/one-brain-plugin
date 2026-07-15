---
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
4. Con el OK → llamá `brain_save` una vez por entry. Reportá el/los `entry_id`.
5. Si el usuario descarta, no guardes. Si hubo varios frentes, varios entries. Si no hubo nada guardable, decilo y no inventes.

## Reglas
- Nunca guardes datos personales sensibles ni secrets.
- Si `brain_save` falla (server pausado, red), avisá al usuario y NO des el avance por perdido: quedará pendiente para el próximo cierre.
