---
name: reuniones
description: Traer las reuniones nuevas de Granola al cerebro (One Brain) y ofrecer destilar sus decisiones/avances. Se activa cuando un aviso de SessionStart dice que hay reuniones sin sincronizar, o cuando el usuario lo pide ("sincronizá mis reuniones", "meté las calls al cerebro", "traé las reuniones de Granola").
---

# Sincronizar reuniones de Granola al cerebro

Traés las reuniones nuevas de Granola a One Brain: la transcripción cruda (se guarda para
preguntas literales) + un resumen legible (lo que se ve en el panel) + un destilado tipado
(decisiones/avances que entran a la memoria), con el usuario confirmando antes de escribir entries.

## Cuándo actuás
- Un aviso de `SessionStart` dice que puede haber reuniones nuevas sin sincronizar.
- El usuario lo pide ("sincronizá las reuniones", "meté las calls al cerebro").

## Qué necesitás
- El MCP oficial de Granola conectado (`granola` en `.mcp.json`). Si no responde, avisá y cortá.
- El token de One Brain en `~/.config/one-brain/token` (lo usa el POST/GET). Sin token, avisá
  al usuario que corra `/one-brain:connect <token>` y cortá.
- La URL del cerebro: `${ONE_BRAIN_URL:-https://one-brain-kappa.vercel.app}`.

## Qué hacés
0. **Chequeá el feature.** Corré en Bash: `onebrain-feature reuniones`. Si sale con exit 1
   (el usuario desactivó "Sincronizar reuniones"), NO hagas nada: terminá en silencio.
1. **Ventana.** Pedí al cerebro las reuniones que YA están, para no re-bajar:
   `curl -s -H "Authorization: Bearer $(cat ~/.config/one-brain/token)" "$ONE_BRAIN_URL/api/meetings?source=granola"`
   → te da `{ meetings: [{ external_id, title, meeting_date }] }`. Guardá ese set de `external_id`.
   Si el set está vacío (primer sync), la ventana es **los últimos 14 días**; si no, alcanza con
   traer lo reciente y filtrar por los `external_id` que faltan.
2. **Listá Granola** con el MCP (`mcp__granola__list_meetings`) las reuniones recientes (14 días
   en el primer sync). Quedate con las que NO están en el set del paso 1 (dedup por id de Granola).
3. **Por cada reunión nueva:**
   a. Traé la transcripción cruda: `mcp__granola__get_meeting_transcript` (id de Granola).
   b. **Generá un resumen legible** del crudo — es lo que se ve al abrir la reunión en el panel
      (NO se muestra el crudo por default). Markdown simple: secciones con `## Título`, bullets
      con `- `, énfasis con `**bold**`. Estructura sugerida: `## TL;DR` (2-3 líneas), `## Decisiones`,
      `## Próximos pasos`, y lo que tenga señal. Claro y conciso — no repitas el crudo textual.
   c. Metela al cerebro con el token del miembro, incluyendo `transcript_md` (crudo) y `summary_md`
      (el resumen). **Tip:** el crudo es largo y tiene comillas/saltos — armá el body JSON con un
      archivo temporal y mandalo con `--data-binary @archivo`, NO con `-d '...'` inline (rompe el shell):
      `curl -s -X POST -H "Authorization: Bearer $(cat ~/.config/one-brain/token)" -H "Content-Type: application/json" \`
      `  --data-binary @/tmp/meeting.json  "$ONE_BRAIN_URL/api/meetings"`
      donde el JSON es `{"source":"granola","external_id":"<id>","title":"<titulo>","meeting_date":"<ISO>","participants":[...],"transcript_md":"<crudo>","summary_md":"<resumen>","entities":[...]}`.
      El endpoint deduplica solo (201 alta / 200 ya existía) y genera el entry 'evento' puntero.
      Pasá en `entities` los clientes/proyectos/personas que reconozcas del título/participantes.
4. **Ofrecé destilar (mismo pase).** El resumen (paso 3b) es para leer la reunión; el destilado
   son entries tipados que entran a la MEMORIA. Sobre las transcripciones que trajiste, detectá las
   **decisiones y avances reales** (no trivialidades). Para cada uno armá un entry como en
   `brain_save`: `type` (decision | avance), `title` (3-200), `content_md` (2-10 líneas
   autocontenidas), `entities`. **Proponé al usuario ANTES de escribir**: "de estas reuniones
   saqué esto: […] · ¿lo guardo / editás / descartás?".
5. Con el OK → llamá `brain_save` una vez por entry. Reportá: "sincronicé N reuniones nuevas;
   guardé M decisiones/avances". Si no hubo reuniones nuevas, decilo y no inventes.

## Reglas
- Nunca guardes secrets ni datos personales sensibles.
- El crudo va ANTES que el destilado: si `brain_save` falla, la transcripción ya quedó guardada.
- Si el POST o `brain_save` fallan (server pausado, red), avisá y dejá lo pendiente para el
  próximo sync — NO lo des por perdido. El dedup evita duplicados al reintentar.
- Una reunión ya sincronizada NO se re-baja (respetá el set del paso 1).
