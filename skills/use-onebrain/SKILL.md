---
description: Usá One Brain (la memoria colectiva de la empresa) durante todo el trabajo. Consultá antes de arrancar una tarea; guardá apenas se cierra una decisión o un hito importante (no solo al final) y SÍ O SÍ al terminar la sesión. Aplicá cuando trabajes sobre cualquier cliente, proyecto, persona o tema de la empresa.
---

# Usar One Brain

One Brain es la memoria colectiva de la empresa, accesible por las tools MCP `brain_context`, `brain_search`, `brain_entity`, `brain_entities`, `brain_save`. Es la fuente de verdad compartida del equipo. Esta skill sirve para CUALQUIER empresa: el negocio concreto vive en los datos, no acá.

## Cómo resolver cada tipo de pregunta (ruteo)

Antes de contestar, identificá qué tipo de pregunta es y usá el plan correspondiente:

| La persona pregunta… | Hacé |
|---|---|
| "¿en qué estamos?", puesta al día, o arrancás una tarea | `brain_context` (la tarea en una frase + las entidades que sepas) |
| un dato puntual, "¿qué es X?", "¿qué se decidió sobre Y?" | `brain_search` con el término |
| todo sobre un cliente / proyecto / persona / tema | `brain_entity` (acepta nombre **o alias**) |
| "¿qué clientes/personas/temas hay?", "listá los proyectos" | `brain_entities` (filtra por `type` o `search`) |
| qué pasó en un período ("en marzo", "esta semana") | `brain_search` con `since`/`until` (ver Fechas relativas) |
| qué hizo una persona ("¿qué tocó Fran?") | `brain_search` con `author` |
| listar/filtrar sin texto ("todas las decisiones de X") | `brain_search` **sin `query`**, con filtros (`type`, `entity`, `author`, `since`/`until`) |
| cómo se conecta X con Y | `brain_entity` de X con `connect_to: Y` → `path` (directo o puentes a 2 saltos con evidencia) |
| qué rodea a X / qué está fuertemente conectado con X | `brain_entity` de X → `neighbors` (con peso y tipo) |
| qué toca a X **y** a Y a la vez (intersección) | `brain_search` con `entities: [X, Y]` (AND); agregá `type`/fechas para acotar |
| "¿cuántos…?", "listá todos…", un total | traé con `brain_search`/`brain_entity` y **contá vos sobre lo que trajiste**, aclarando que es sobre lo cargado |
| "¿qué falta / qué NO pasó?" | respondé solo si tenés el universo completo cargado; si no, decilo |
| pregunta de varios saltos | descomponé en sub-preguntas y encadená varias llamadas |

### Fechas relativas
Cuando pregunten con referencias relativas ("esta semana", "el mes pasado", "últimos 30 días", "este año"), convertí vos la referencia a fechas concretas `YYYY-MM-DD` y pasalas como `since`/`until`. Si la empresa define un año comercial propio (una temporada/campaña que no coincide con el calendario), usá ESE rango cuando lo mencionen.

### Regla de oro: no inventar
La búsqueda encuentra lo que existe con esas palabras. NO sirve, por sí sola, para **contar**, **listar todo** ni **decir qué falta**. Para esas preguntas, traé lo que haya y sé explícito sobre el alcance ("de lo cargado, hay N"); nunca tires un número o una lista como si fuera exhaustivo si no lo verificaste.

## Regla proactiva (importante)
Cuando en la conversación aparezca una entidad conocida (un cliente, proyecto, persona o tema de la empresa), traé y **citá** lo que el equipo ya sabe de ella —con procedencia: quién lo cargó y cuándo— **sin que te lo pidan**. La gente no siempre sabe qué preguntar.

## Guardar (durante la sesión Y al cerrar)
Guardá con `brain_save` **apenas se cierra algo con señal — no solo al final de la sesión**: cada vez que se toma una **decisión importante**, se completa un **hito o avance concreto** (un deploy, un fix, un entregable, una definición), o aprendés un **dato relevante** (reunión, llamada, problema). No lo dejes para el cierre: volcalo en el momento.

- **Propone-y-confirma**: antes de escribir, mostrá el resumen y pedí OK — "voy a guardar esto: […] · ¿ok / editás / descartás?". Con el OK, llamá `brain_save`.
- Resumen autocontenido (2-10 líneas) + las entidades tocadas. Si una decisión reemplaza otra, pasá `supersedes` con el id de la vieja.
- **NO** guardes trivialidades, pasos intermedios ni datos personales sensibles.

## Continuidad de sesión (OBLIGATORIO — esto nos distingue)
One Brain te da continuidad entre sesiones. No la desperdicies —la mayoría de la gente arranca cada sesión de cero y llena el contexto al pedo; nosotros no:
- **Al abrir**: si el arranque te trae un handoff de la última sesión (empieza con "⏸️ Tenés un handoff…"), **RETOMÁ desde ahí**. Leelo, resumí en 2 líneas dónde quedó y cuál es el próximo paso, y seguí. NO re-explores lo que el handoff ya resolvió.
- **Al cerrar, o cuando el contexto se está llenando**: si quedó trabajo a medio hacer (una tarea en progreso, un próximo paso claro), dejá un **handoff** con la skill `handoff` antes de terminar. Es lo que te deja retomar la próxima vez. Es distinto de guardar avances: el handoff es "dónde quedé y qué sigue", no "qué logré".
- Si la sesión se pone larga y el contexto se llena, **proponé vos**: "conviene que deje un handoff y arranquemos fresco para no perder calidad". No esperes a que el modelo degrade.

## Niveles y confidencialidad
Las entradas tienen nivel (1 dirección / 2 gerencia / 3 general). El server solo te devuelve lo que el nivel del usuario permite y lo hace cumplir — no intentes rodearlo. Si un dato no aparece porque es de nivel superior, tratalo como **inexistente**: respondé "no tengo registro de eso", NO "no te lo puedo decir" (que confirmaría que existe).

## Cierre de sesión (SÍ O SÍ)
Al terminar una sesión con trabajo real, **siempre** revisá que cada avance y decisión con señal haya quedado guardado —aunque ya hayas ido guardando durante la sesión—. Es el piso mínimo, no el único momento. Si algo quedó sin guardar, un recordatorio te lo va a avisar: no lo ignores.
