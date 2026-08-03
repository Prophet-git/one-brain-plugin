---
name: estudiar
description: Incorporar al cerebro los documentos que la persona subió por la web. Se activa cuando el arranque avisa que hay material sin estudiar, o cuando el usuario dice "estudiá lo que subí", "procesá los documentos", "incorporá el material".
---

# Estudiar el material subido

Convierte documentos crudos en memorias con autor, fecha y vigencia. **No es un resumidor:**
la mayoría de lo que se sube no genera ninguna memoria, y está bien que así sea.

## Antes de tocar nada: decí lo que va a costar

1. `brain_material({})` para ver qué hay pendiente. Trae la lista, `tokens_estimados` (lo que
   CUESTA) y `tokens_texto` (lo que PESA el texto, que es otra cosa).
2. Decile el número de `tokens_estimados` y **esperá que confirme**:

   > Tenés 3 documentos sin estudiar. Leerlos con criterio lleva un par de minutos cada uno y
   > consume de la misma cuota que usás en claude.ai y en Cowork. ¿Arranco con los tres, o
   > preferís que haga uno primero y ves qué sale?

   **NUNCA le tires la cantidad de tokens.** Decisión de Bauti (2-ago-2026): a un cliente
   "220.000 tokens" no le dice nada, suena carísimo y la respuesta natural es que no —
   información en un idioma que no habla. Lo que sí entiende es el tiempo y la opción de
   arrancar de a poco. El número está en `tokens_estimados` por si alguien lo PIDE; ahí se lo
   das, no antes.

   **Para qué sigue existiendo el aviso, entonces:** el cupo es uno solo y compartido entre
   Claude Code, claude.ai y Cowork. Alguien que larga veinte documentos sin saber que es una
   tarea larga se queda sin cuota a media tarde y no entiende por qué. Avisar el tamaño de lo
   que va a pasar y ofrecer hacerlo por tandas lo cubre igual, sin números que asustan.

   **NO REPORTES EL CONTADOR QUE VES EN PANTALLA si te preguntan el gasto.** En la corrida del
   2-ago el agente informó "63k y 64k" cuando el costo real era 219.000 por documento: ese
   contador no incluye las lecturas de caché y da unas 3,5 veces menos. El número real sale de
   sumar `message.usage` en los transcripts de los subagentes.

   **El tamaño del documento casi no influye:** en esa corrida, el de 11.000 caracteres costó lo
   mismo que el de 3.500. Lo que manda son los pasos y el contexto que se arrastra en cada uno.
3. **Con más de dos o tres, ofrecé arrancar por uno.** A este costo, una tanda de veinte
   documentos es una sesión entera de cuota. Nadie tiene que elegir entre "todo" y "nada".

## Cómo se procesa: un documento por subagente, en tandas de a cuatro

**No leas los documentos en esta conversación.** Por cada documento despachá un subagente que
haga el ciclo entero y vuelva con un renglón.

Dos razones, y las dos importan:

- **El texto crudo no tiene que entrar acá.** Treinta documentos llenan la ventana y disparan
  compactación tras compactación, y cada compactación pierde detalle. Esa pérdida se acumula:
  para el documento 20 estarías amasando con un recuerdo borroso de los primeros 19. El
  subagente se lleva el texto sucio y devuelve la conclusión.
- **En tandas cortas el usuario ve el gasto y puede frenar.** Al terminar cada tanda de cuatro,
  contá qué salió y cuánto llevás, y preguntá si seguís.

**En serie, no en paralelo.** Cada subagente tiene que ver lo que guardó el anterior: si dos
corren a la vez sobre documentos del mismo tema, ninguno ve las memorias del otro y quedan dos
memorias casi iguales — justo lo que las reglas de similitud existen para evitar.

**EL SUBAGENTE TIENE QUE HACER POCOS TURNOS, y esto no es una preferencia de estilo.** Medido
el 2-ago-2026: cada turno del subagente reenvía todo su contexto —incluidos ~64.000 caracteres
de catálogo de herramientas y skills que hereda de la sesión y no usa— así que el costo es
`contexto × turnos`. Un documento en 30 turnos costó 414.000 tokens; el mismo trabajo en 6
cuesta una fracción. El documento en sí son 1.100 tokens: nunca fue el problema.

Por eso `brain_material` ya te devuelve **`parecidas`**: lo que el cerebro tiene sobre ese tema,
buscado por el servidor con el vector del documento entero. No salgas a buscar tema por tema.

Prompt para cada subagente:

> Sos parte de One Brain, el cerebro de la empresa. Incorporá UN documento, en la MENOR
> cantidad de pasos posible.
> 1. `brain_material({id: "<ID>"})`. Te devuelve el texto y `parecidas`: lo que el cerebro ya
>    tiene sobre este tema. Si `hay_mas` es `true`, seguí con
>    `brain_material({id, desde: siguiente_desde})` hasta el final. No decidas nada con el
>    documento a medias.
> 2. Leé el documento entero y decidí TODO de una: por cada cosa que sea una decisión, un
>    acuerdo, una regla del negocio o un aprendizaje, mirá `parecidas` y aplicá las reglas de
>    similitud: <pegar acá la tabla de la sección siguiente>. Usá `brain_search` SOLO si te
>    queda una duda puntual que `parecidas` no responde — no como paso obligatorio.
> 3. Guardá las memorias que decidiste, una tras otra, sin volver a analizar entre medio. Citá
>    el nombre del documento en el cuerpo.
> 4. Cerrá con `brain_material({id, cerrar: "amasado", memorias: N})`, o con
>    `cerrar: "descartado"` si era papeleo.
> Devolvé un solo renglón: nombre del documento, cuántas memorias guardaste, cuántas
> reemplazaron a otra, y qué descartaste y por qué.

**Dónde conviene correr esto:** en una sesión con pocos MCP servers y skills cargados. El
catálogo que el subagente hereda sale de la sesión que lo despacha, no de One Brain: la misma
tarea en un proyecto liviano cuesta bastante menos que en uno con quince conectores prendidos.

Si el documento es puro papeleo —una factura, un remito, una versión vieja de algo que ya
está— se cierra con `cerrar: "descartado"` y se sigue. No se inventa una memoria para
justificar el archivo.

## Reglas de similitud: qué hacer cuando ya hay algo parecido

Antes de guardar nada, `brain_search` con los términos centrales de lo que ibas a guardar. No
es opcional y no es "fijate si está repetido": es la decisión más importante del flujo.

**Por qué:** lo que arruina un cerebro no son las memorias largas, son las memorias parecidas
entre sí. Con cinco versiones de la misma regla dando vueltas, la búsqueda las trae a las
cinco, el que pregunta no sabe cuál manda, y el cerebro pasa de contestar a hacer dudar.

Con lo que devuelve la búsqueda, elegí una de cuatro:

| Lo que encontraste | Qué hacés |
|---|---|
| Nada parecido | `brain_save` normal |
| Lo mismo pero **desactualizado** (la política nueva contra la vieja, el contrato renovado contra el anterior) | `brain_save` con `supersedes` apuntando al id viejo. **Esto es lo más importante de todo el flujo:** es lo que hace que el cerebro sepa qué sigue vigente en vez de contestar las dos versiones |
| Lo mismo dicho a medias, y el documento lo **completa** | Fusionar: una sola memoria que diga las dos cosas, con `supersedes` a la vieja. Dos memorias que se complementan valen menos que una que se entiende |
| Ya está dicho, igual o mejor | **No guardes nada.** Es la opción correcta bastante más seguido de lo que parece |

Si dudás entre reemplazar y guardar aparte, preguntate si las dos pueden ser ciertas al mismo
tiempo. Si no pueden, va `supersedes`.

## Qué SÍ es memoria

- "A los mayoristas no se les baja más del 15%" (regla, con quién la decidió y cuándo)
- "El contrato con X vence en marzo y se renueva solo salvo aviso con 60 días"
- "Probamos vender por catálogo impreso en 2025 y no funcionó porque…"

## Qué NO es memoria

- El texto completo del contrato (eso es el documento, no la decisión)
- Una factura, un remito, un presupuesto
- Un resumen genérico de lo que dice el archivo
- Datos operativos fila por fila de una planilla

## Reglas

- **Una memoria por idea.** Un documento largo casi siempre son varias memorias chicas, no
  una gigante. El tope de `brain_save` son 20.000 caracteres y la búsqueda funciona mucho
  mejor con memorias cortas.
- **Citá de dónde salió** en el cuerpo: nombre del documento y, si aplica, la página.
- **No inventes el autor.** La memoria queda a nombre de quien está en la sesión, que es
  quien subió el documento — también cuando la guarda un subagente, porque usa el mismo token.
  Si en el texto figura que la decisión la tomó otra persona, escribilo en el cuerpo.
- Al terminar cada tanda, decí en una línea cuántos documentos procesaste, cuántas memorias
  salieron, **cuántas reemplazaron a una anterior** y cuántos descartaste. Las que reemplazan
  son la señal de que el cerebro está quedando ordenado en vez de creciendo.
