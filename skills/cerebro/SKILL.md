---
name: cerebro
description: Ver en qué cerebro de One Brain está esta carpeta, cambiarla de cerebro o sumar la llave de otro cerebro. Se dispara con "/one-brain:cerebro", "¿en qué cerebro estoy?", "este repo es de El Profeta", "cambiá de cerebro", "pasá esta carpeta a X", "acá está la llave de otro cerebro".
---

# Cerebros por carpeta

Una persona puede estar en varios cerebros (uno por equipo). El archivo `.onebrain` en la raíz del repo dice a qué cerebro pertenece la carpeta, y la llave de cada cerebro vive aparte, en esta Mac. Sin `.onebrain`, la carpeta usa el cerebro por defecto, como siempre.

El ejecutable `onebrain-cerebro` ya está en el PATH del plugin. Según `$ARGUMENTS`:

1. **Sin argumentos o "ver"**: corré `onebrain-cerebro` y mostrale la salida tal cual: qué cerebro usa esta carpeta y qué llaves hay en la Mac. Listo cuando el usuario vio las dos cosas.
2. **"usar <cerebro>"**: corré `onebrain-cerebro usar <cerebro>`. Escribe `.onebrain` en la raíz del repo. Después:
   - Decile que lo commitee: así lo tienen las otras copias del repo y su compañero cuando clona.
   - Si la salida dice que falta la llave, pedile el token de ese cerebro y seguí con el paso 3.
   - Decile que abra una sesión nueva en esa carpeta: la conexión de esta sesión ya quedó armada con el cerebro anterior.
   Listo cuando existe `.onebrain` y el usuario sabe que tiene que commitearlo y abrir una sesión nueva.
3. **"conectar <token>"**: corré `onebrain-cerebro conectar "<token>"`. Guarda la llave sin tocar la del cerebro por defecto. Nunca muestres el token ni lo guardes en otro lado. Listo cuando la salida dice "Listo: guardé la llave".

## Reglas

- Nunca guardes algo de un cerebro en otro para "destrabar": si el arranque dice que la carpeta no tiene llave, no se lee ni se guarda nada hasta conectarla.
- No escribas `.onebrain` en la carpeta del usuario (`~`): haría que todo fuera de ese cerebro. El comando ya se niega.
- El nombre del cerebro es el slug que va adentro del token (`ob_<cerebro>_…`), por ejemplo `el-profeta`.
