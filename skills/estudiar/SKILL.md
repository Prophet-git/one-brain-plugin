---
name: estudiar
description: Incorporar al cerebro los documentos que la persona subió por la web. Se activa cuando el arranque avisa que hay material sin estudiar, o cuando el usuario dice "estudiá lo que subí", "procesá los documentos", "incorporá el material".
---

# Estudiar el material subido

Convierte documentos crudos en memorias con autor, fecha y vigencia. **No es un resumidor:**
la mayoría de lo que se sube no genera ninguna memoria, y está bien que así sea.

## Antes de tocar nada: decí lo que va a costar

1. `brain_material({})` para ver qué hay pendiente. Trae la lista y `tokens_estimados`.
2. Decíselo al usuario en una línea y **esperá que confirme**:

   > Tenés 12 documentos sin estudiar (~380.000 caracteres, del orden de 110.000 tokens de
   > entrada). Sale de la misma cuota que usás en claude.ai y en Cowork. ¿Arranco?

   **Por qué esto no se saltea:** el cupo es uno solo y compartido entre los tres. Alguien que
   arranca esto sin saberlo se queda sin cuota a media tarde y no entiende por qué.
3. Si son más de cuatro, ofrecé empezar por una tanda y seguir después. Nadie tiene que elegir
   entre "todo" y "nada".

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

Prompt para cada subagente:

> Sos parte de One Brain, el cerebro de la empresa. Incorporá UN documento.
> 1. `brain_material({id: "<ID>"})`. Si `hay_mas` es `true`, seguí con
>    `brain_material({id, desde: siguiente_desde})` hasta el final. No decidas nada con el
>    documento a medias.
> 2. Por cada cosa que parezca memoria, `brain_search` con sus términos y aplicá las reglas de
>    similitud: <pegar acá la tabla de la sección siguiente>.
> 3. Guardá con `brain_save` sólo decisiones, acuerdos, reglas del negocio o aprendizajes que
>    le sirvan a alguien que no leyó el documento. Citá el nombre del documento en el cuerpo.
> 4. Cerrá con `brain_material({id, cerrar: "amasado", memorias: N})`, o con
>    `cerrar: "descartado"` si era papeleo.
> Devolvé un solo renglón: nombre del documento, cuántas memorias guardaste, cuántas
> reemplazaron a otra, y qué descartaste y por qué.

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
