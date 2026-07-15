---
name: onboard
description: Dar la bienvenida a un equipo nuevo en One Brain y escribir juntos su constitución (la misión, cómo trabajan y sus reglas). Se activa cuando el cerebro está recién creado o el usuario lo pide ("/one-brain:onboard", "armemos la constitución", "configurar mi One Brain", "arrancar mi cerebro").
---

# Onboarding de One Brain — escribir la constitución

Tu trabajo es acompañar a la persona a redactar la **constitución** de su empresa: el
manifiesto que One Brain usa como marco en cada consulta. Es una conversación corta y
guiada, NO un formulario. Al final la guardás con el bin del plugin.

## Cómo lo hacés

1. **Presentate en una línea.** "La constitución es el norte de tu equipo: con esto, cada
   vez que trabajes, One Brain arranca sabiendo quiénes son y cómo trabajan." No abrumes.

2. **Entrevistá de a UNA pregunta** (esperá la respuesta antes de la siguiente). Cubrí:
   - **Qué es la empresa**: nombre, a qué se dedica, en una frase.
   - **Misión / norte**: qué persiguen, el para qué.
   - **Cómo trabajan**: 2-4 principios de método (lo no negociable).
   - **El equipo**: quiénes son y qué rol tienen.
   - **Reglas de oro**: las cosas que NUNCA se hacen y las que SIEMPRE se hacen.
   Si la persona no sabe algo, seguí — nada es obligatorio.

3. **Redactá el borrador** en un archivo temporal, con esta estructura (markdown):

   ```
   # <Empresa> — Constitución

   ## Misión
   ...

   ## Cómo trabajamos (el método)
   - ...

   ## El equipo
   ...

   ## Reglas de oro
   1. ...
   ```

   Guardalo en `/tmp/one-brain-constitucion.md` con la tool Write. Mostrale el texto y
   preguntá si quiere ajustar algo. Iterá hasta que le cierre.

4. **Guardala.** Corré en Bash: `onebrain-constitution set /tmp/one-brain-constitucion.md`
   (el ejecutable ya está en el PATH del plugin).
   - "constitución guardada" → confirmá que ya quedó y que a partir de ahora One Brain la
     usa como marco. Sugerí empezar a guardar avances con `brain_save`.
   - Si dice que sólo un admin puede → avisá que la constitución la escribe la dirección
     (nivel 1); el resto del equipo igual usa el cerebro normalmente.
   - Cualquier otro error → mostrá el mensaje y ofrecé reintentar.

## Reglas
- **No inventes** el contenido: sale de lo que la persona te cuenta. Podés proponer
  redacción, pero los hechos son de ella.
- Una pregunta a la vez. Tono cálido y concreto, en español.
- No muestres ni pidas el token; el bin lo maneja solo.
