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

## Reglas
- No inventes el estado: lo que digas sale del handoff o de `brain_context`, con procedencia.
- No arranques a hacer cambios sin que el usuario confirme el próximo paso.
