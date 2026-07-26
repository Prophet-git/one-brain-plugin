---
name: onboard
description: Dar la bienvenida a un equipo nuevo en One Brain, escribir juntos su constitución (la misión, cómo trabajan y sus reglas) y dejarle el cerebro con sus primeros hechos adentro. Se activa cuando el cerebro está recién creado o el usuario lo pide ("/one-brain:onboard", "armemos la constitución", "configurar mi One Brain", "arrancar mi cerebro").
---

# Onboarding de One Brain — constitución + primeras memorias

Tu trabajo tiene DOS mitades y las dos son obligatorias:

1. Acompañar a la persona a redactar la **constitución** de su empresa: el manifiesto que One
   Brain usa como marco en cada consulta.
2. **Sembrar el cerebro** con 8-12 hechos reales sacados de esa misma conversación.

La segunda no es opcional ni "un extra si sobra tiempo". Un cerebro que queda vacío después
del onboarding no devuelve nada en la primera consulta, y a la segunda la persona deja de
preguntarle. Es exactamente lo que pasó con la mayoría de los cerebros dados de alta hasta hoy.

Es una conversación corta y guiada, NO un formulario.

## Cómo lo hacés

1. **Presentate en una línea.** "La constitución es el norte de tu equipo: con esto, cada
   vez que trabajes, One Brain arranca sabiendo quiénes son y cómo trabajan." No abrumes.

2. **Entrevistá de a UNA pregunta** (esperá la respuesta antes de la siguiente). Cubrí:
   - **Qué es la empresa**: nombre, a qué se dedica, en una frase.
   - **Misión / norte**: qué persiguen, el para qué.
   - **Cómo trabajan**: 2-4 principios de método (lo no negociable).
   - **El equipo**: quiénes son y qué rol tienen.
   - **Reglas de oro**: las cosas que NUNCA se hacen y las que SIEMPRE se hacen.
   - **Con quién y con qué trabajan hoy**: sus clientes o proyectos activos, y las
     herramientas que usan todos los días.
   Si la persona no sabe algo, seguí — nada es obligatorio.

   La última pregunta no va a la constitución: va al cerebro. Sin nombres de clientes,
   proyectos y personas no hay entidades, y sin entidades las búsquedas del equipo no
   encuentran nada. Igual, si no quiere contestarla, seguís.

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
     usa como marco.
   - Si responde **403** ("sólo un admin puede editar la constitución") → avisá que la
     constitución la escribe la dirección, y **seguí igual con el paso 5**: sembrar memorias
     no requiere ser admin. Cortar acá dejaría a esa persona con el cerebro tan vacío como
     si nunca hubiera hecho el onboarding.
   - Cualquier otro error → mostrá el mensaje, ofrecé reintentar, y seguí con el paso 5.

5. **Sembrá el cerebro con 8-12 hechos.** Releé la conversación entera (la entrevista + la
   constitución que acaban de escribir) y cortá lo que la persona contó en hechos sueltos.

   Cada hecho es **una unidad de sentido**, autocontenida: tiene que entenderse dentro de seis
   meses, leído por alguien del equipo que no estuvo en esta charla. Ni la constitución partida
   en frases sueltas, ni un resumen gigante de todo.

   De dónde suelen salir los 8-12 (el orden es el de la entrevista):

   | Material que ya te dio | `--type` | `--entities` |
   |---|---|---|
   | Qué hace la empresa y para quién | `conocimiento` | la empresa |
   | La misión / el norte | `conocimiento` | la empresa |
   | Cada principio de método, **uno por hecho** | `conocimiento` | el tema que toca |
   | Cada persona del equipo: rol y de qué se ocupa | `conocimiento` | esa persona |
   | Cada regla de oro (las que NUNCA y las que SIEMPRE) | `decision` si el equipo la definió, `conocimiento` si es costumbre | el tema |
   | Cada cliente o proyecto activo que nombró | `conocimiento` | ese cliente/proyecto |
   | Las herramientas con las que trabajan | `conocimiento` | la herramienta |
   | Algo que decidieron y sigue vigente (por qué dejaron X, por qué eligieron Y) | `decision` | lo que toca |

   **Mostrale la lista numerada antes de guardar** — título + una línea cada uno — y pedile
   que corte o corrija lo que no vaya: "esto es lo que entendí, ¿lo guardo así?". Ninguno se
   guarda sin su OK. Es la red que atrapa cualquier cosa que hayas entendido de más.

   Con el OK, guardá **uno por uno** en Bash:

   ```
   onebrain-save --type conocimiento \
     --title "<título corto y concreto>" \
     --content "<2-6 líneas autocontenidas>" \
     --entities "cliente,persona,tema"
   ```

   - Imprime un `entry_id` → guardado.
   - No imprime id → quedó **encolado** para el próximo arranque. Avisale que quedó pendiente,
     no perdido, y seguí con los demás.

6. **Cerrá mostrando que el cerebro ya contesta.** Hacé una `brain_search` con una palabra
   que ella misma usó (un cliente, un principio) y mostrale el resultado: es la primera vez
   que ve al cerebro devolver algo suyo. Aclarale que la búsqueda trae un recorte, y que para
   leer una memoria entera está `brain_get` con el id de esa entrada.

   Cerrá en una línea: de ahora en más, cuando cierre algo importante lo guardan igual que
   recién, y el cerebro se lo devuelve a cualquiera del equipo.

## Reglas
- **No inventes.** Ni la constitución ni los hechos. Cada hecho que sembrás tiene que poder
  **señalar la frase** que la persona dijo. Si no podés señalarla, no es un hecho: es un
  invento con formato de hecho, y ensucia la memoria del equipo para siempre. Podés proponer
  redacción; los hechos son de ella.
- **Nunca rellenes para llegar al número.** Si de la conversación salen menos de 8 hechos
  reales, sembrá los que haya y decilo tal cual: "quedaron 5 — cuando me cuentes de tus
  clientes sumamos más". Frases de relleno tipo "trabajan en equipo" o "buscan la excelencia"
  no son hechos: no dicen nada de esta empresa y son peores que no tener nada. Tampoco te
  pases de 12 en el arranque: con 12 hechos buenos la primera consulta ya trae algo.
- **Lo que sabés del rubro no cuenta.** Aunque estés seguro de cómo funciona una agencia, una
  clínica o una inmobiliaria, si no lo dijo ella no se guarda.
- No guardes la constitución entera como una memoria más: ya quedó guardada aparte en el paso 4.
- No guardes datos personales sensibles ni claves.
- Una pregunta a la vez. Tono cálido y concreto, en español.
- No muestres ni pidas el token; el bin lo maneja solo.
