---
name: semana
description: "Usar cuando el usuario pregunta por su semana de trabajo con Claude Code o la del equipo: \"qué hice esta semana\", \"reporte semanal\", \"cuántas horas le dediqué a X\", \"cuánto gastamos en Y\", \"Semana no se actualiza\", \"este proyecto está mal asignado\", \"/one-brain:semana\". Lee la semana con brain_semana, corrige asignaciones con brain_semana_asignar y fuerza el envío con onebrain-semana-push --ahora, sin pedirle nada a la persona."
---

# Semana

Semana es el calendario de las sesiones de Claude Code de cada persona: horas por proyecto, costo, % del plan, modelos y subagentes. El plugin sube las sesiones de esta Mac solo (al cerrar cada turno, como mucho cada 10 minutos) y el cerebro resuelve a qué cliente va cada bloque. Esta skill la usás, la corregís y la mantenés andando **vos**, sin pedirle a la persona que haga nada.

## 1. Leer la semana

Llamá `brain_semana`:

- `semana`: `"actual"` (default), `"pasada"` o una fecha `YYYY-MM-DD` de cualquier día de esa semana. La semana va de lunes 7:00 a lunes 7:00, en hora de Argentina.
- `persona`: `"yo"` (default), el nombre de alguien (`"Fran"`) o `"equipo"`.
- `detalle: true` si hace falta la lista de sesiones (título, proyecto, horario, commits).

Devuelve datos, no texto: `horas` (de reloj, lo paralelo cuenta una vez), `proyectos` (horas, costo y `pct_plan`), `dias`, `costo`, `tokens`, `modelos`, `subagentes`, `rutinas` (corridas automáticas: tienen costo pero no suman horas), `crecimiento` (las últimas 8 semanas por proyecto), `sin_asignar` y `estado`.

## 2. Corregir lo mal asignado (antes de reportar)

Mirá `sin_asignar`. Cada entrada es tiempo que no cayó en ningún cliente:

- **Un repo sin cliente** (`tipo: "repo sin cliente"`, ej. `whatsapp-responder`): si por el nombre, los `ejemplos` (títulos) o las `pistas` está claro de qué cliente es, asignalo con `brain_semana_asignar({ nombre: "whatsapp-responder", proyecto: "PEM" })`. Si no está claro, preguntá en una línea, con tu mejor candidato.
- **`General`** (`tipo: "sin señal"`): el bloque no tocó ningún repo ni nombró a nadie. Mirá sus `pistas` y `ejemplos`; si aparece un repo o un nombre de cliente, asigná ESE nombre. `General` en sí no se asigna.
- Si la persona dice que un proyecto está mal ("eso es de Lempriere, no de PEM"), asigná el repo o el nombre que lo causó.

`brain_semana_asignar` suma un alias al cliente y corrige **todas** las semanas, también las viejas. Devuelve `bloques_que_cambian` y `cambios` (de qué a qué): decí en una línea qué movió. Rechaza personas, nombres que ya son otra entidad y proyectos que no existen; no lo fuerces, leé el motivo.

Después de asignar, volvé a llamar `brain_semana` para reportar con los números corregidos.

## 3. Verificar que se esté actualizando

Mirá `estado` (una entrada por persona):

- `atrasado: true`: la persona usó One Brain más de 24 h después del último envío aceptado. Su Mac tiene sesiones sin subir.
- `rechazos > 0` con `motivo`: el server rechazó lo que mandó el plugin.
- `nunca_envio: true`: esa Mac nunca subió nada (falta el plugin actualizado, `python3` o el token).

Si es **tu** Mac (o la persona te lo pide), corré en Bash:

    onebrain-semana-push --ahora

Saltea el tope de 10 minutos y dice en una línea qué subió. Después volvé a llamar `brain_semana` y confirmá que `estado` quedó bien. Si dice que falta `python3` o el token, decí exactamente eso y el arreglo que trae la línea. Para el diagnóstico completo: `onebrain-semana-push --estado` (o la skill doctor). Si es la Mac de otra persona, decile en una línea que corra ese mismo comando.

## 4. El reporte semanal

Tres líneas, con los números de `brain_semana` (después de corregir lo asignado):

1. **Qué se hizo**: los 2 o 3 proyectos principales y lo concreto (sale de los títulos con `detalle: true`), y el total de horas.
2. **Qué se llevó más**: el proyecto con más horas y el de más costo (si son distintos, los dos), con su número.
3. **El plan**: qué % del plan se usó en la semana (`plan.pct_semana`). Si `plan` viene en null, decí que no hay muestras del plan esa semana; no lo estimes.

Horas en formato `12 h 30 min`, costo en `US$` (es a precio de API, no lo que se paga con el plan). Sin adjetivos ni relleno.
