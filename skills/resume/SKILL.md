---
name: resume
description: Retomar trabajo desde el último handoff guardado en One Brain. Se activa cuando el usuario quiere ponerse al día o continuar algo ("retomemos X", "ponete al día con X", "dónde quedamos", "sigamos con X", "en qué estábamos con X").
---

# Retomar desde One Brain

Traés el último handoff del cerebro y armás un arranque claro: dónde se quedó y cuál es el próximo paso.

## Cuándo actuás
- El usuario quiere retomar o ponerse al día: "retomemos X", "sigamos con X", "dónde quedamos con X", "ponete al día".

## Qué hacés
1. Buscá el handoff más reciente en el cerebro con `brain_search` usando `type: "handoff"`. Si el usuario nombró un proyecto/tema, pasalo como `entity` para filtrar; si no, traé el más reciente en general.
2. Si hay varios, tomá el más reciente (ordená por fecha / usá `since`).
3. Armá un resumen breve: **dónde quedó** + **qué falta** + **próximo paso** (leídos del handoff). Citá quién y cuándo lo dejó (procedencia).
4. Si el handoff menciona estado técnico (rama, comando de validación), ofrecé correrlo antes de seguir.
5. Si NO hay ningún handoff para eso, decilo claramente y ofrecé un `brain_context` del proyecto como alternativa.
6. **Cerrá lo que ya terminó.** Si al retomar ves que el trabajo del handoff ya está hecho (la rama está juntada, el deploy salió, el pedido se resolvió o se abandonó), cerralo con `brain_cerrar_handoffs`: `ids` con su id, `motivo` en una frase y `fuente` con la prueba (el commit, el deploy o el id de la memoria que lo cerró). No sumes una memoria nueva para eso. Si el trabajo sigue, no lo cierres: al terminar, el handoff nuevo del mismo hilo lo reemplaza solo.
7. **Los que esperan hace días.** Un handoff con `esperando hace N días` es uno vigente de más de 48 h. Antes de seguirlo, mirá si ya se resolvió (git log, el deploy, la ficha): si se resolvió, cerralo como en el paso 6; si sigue trabado, decí en qué y a quién espera.

## Reglas
- No inventes el estado: lo que digas sale del handoff o de `brain_context`, con procedencia.
- No arranques a hacer cambios sin que el usuario confirme el próximo paso.
- Cerrar un handoff no borra nada: lo marca resuelto con su motivo y su prueba. Sólo el autor (o alguien de rango más alto) puede cerrarlo; si la respuesta lo rechaza, avisá a quién le toca.
