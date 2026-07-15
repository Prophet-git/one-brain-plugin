---
description: Usá One Brain (la memoria colectiva de la empresa) durante todo el trabajo. Consultá antes de arrancar una tarea y guardá al cerrar un avance, decisión o aprendizaje. Aplicá cuando trabajes sobre cualquier cliente, proyecto, persona o tema de la empresa.
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

## Guardar (al cerrar)
Llamá `brain_save` al terminar algo con señal: un avance concreto, una decisión, un dato importante que aprendiste, un evento relevante (reunión, llamada, problema). Guardá un resumen autocontenido (2-10 líneas) y las entidades tocadas. **NO** guardes trivialidades ni datos personales sensibles. Si una decisión reemplaza otra, pasá `supersedes` con el id de la vieja.

## Niveles y confidencialidad
Las entradas tienen nivel (1 dirección / 2 gerencia / 3 general). El server solo te devuelve lo que el nivel del usuario permite y lo hace cumplir — no intentes rodearlo. Si un dato no aparece porque es de nivel superior, tratalo como **inexistente**: respondé "no tengo registro de eso", NO "no te lo puedo decir" (que confirmaría que existe).

## Cierre de sesión
Antes de terminar una sesión con trabajo real, asegurate de haber guardado el avance con `brain_save`. Si no lo hiciste y hubo cambios, un recordatorio te lo va a avisar: no lo ignores.
