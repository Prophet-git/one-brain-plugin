---
name: doctor
description: Revisar por qué One Brain no está funcionando en esta máquina y decir el próximo paso concreto. Se activa cuando el usuario dice "no anda el cerebro", "no me guarda nada", "no aparece nada de One Brain", "revisá la instalación", "/one-brain:doctor", o cuando falla algo del plugin y no está claro por qué.
---

# Doctor de One Brain

Diagnosticás la instalación de esta máquina y devolvés un veredicto claro con el próximo paso. **No cambiás nada**: el doctor mira, no toca.

## Qué hacés

1. Corré en Bash: `onebrain-doctor` (ya está en el PATH del plugin).
   Devuelve una línea por chequeo con el formato `clave|estado|detalle`, donde estado es `ok`, `aviso` o `falla`.

2. Leé la salida y armá el reporte. Los chequeos son:
   - **token** — si hay credencial guardada en esta máquina.
   - **perfil** — en qué perfil de esta máquina corre la sesión y qué cerebro tiene conectado (el nombre del cerebro sale del token, sin llamar al server). Si el token todavía es el heredado del perfil de siempre — no se reconectó éste aparte —, avisa en `aviso` con el comando para separarlos.
   - **curl** — si está la herramienta que usa el plugin para hablar con el cerebro.
   - **parser** — si los hooks pueden leer lo que les manda Claude Code (si esto falla, la captura automática no anda aunque todo lo demás esté bien).
   - **hooks** — si `disableAllHooks` está apagando todos los hooks del sistema.
   - **carpeta** — si hay un `CLAUDE.md` con las reglas de One Brain donde la persona está trabajando. Vale por los dos caminos de alta: el de la terminal lo deja en la carpeta fija que arma el instalador, y el de la app lo deja en la carpeta que la persona eligió. Antes se miraba sólo la carpeta fija, así que a todo el camino de la app le daba "no existe" para siempre.
   - **reglas** — si las reglas de One Brain que tiene escritas en su `CLAUDE.md` son de la versión vigente. Un archivo con la política vieja pasa el chequeo de `carpeta` igual (nombra las tools, o sea "está configurado") mientras le pide a su Claude cosas que el producto ya cambió. Si no hay reglas en ninguna parte, este chequeo no dice nada: de eso ya se queja `carpeta`.
   - **entrega** — si el contexto que el cerebro manda al arrancar la sesión llegó entero o hubo que recortarlo por tamaño. Es la falla que más contexto se comió históricamente y desde afuera no se ve.
   - **captura** — cuántas sesiones anteriores quedaron con trabajo sin destilar.
   - **conexion** — si el cerebro responde con este token.
   - **version** — qué versión está corriendo, comparada con la que Claude Code tiene instalada. Si actualizó el plugin sin reiniciar, la sesión sigue usando la vieja y da `aviso`.

## Cómo lo reportás

Primero **el veredicto en una línea**: "está todo bien" o "encontré N problemas". Después solo lo que no está en verde, con el arreglo concreto:

| Falla | Qué le decís que haga |
|---|---|
| `token` | Pedile el token a quien le dio acceso y corré `/one-brain:connect <token>` |
| `perfil` en `aviso` | No es una falla: el token de este perfil es el heredado del de siempre. Si esta persona quiere un cerebro DISTINTO acá, que corra `/one-brain:connect <token>` con el suyo — a partir de ahí este perfil deja de usar el heredado |
| `curl` | Instalar curl (en Windows: usar Git Bash o WSL, que ya lo traen) |
| `parser` | Actualizar el plugin (ver "Cómo se actualiza", abajo) y reiniciar Claude Code |
| `hooks` | Sacar `"disableAllHooks": true` de `~/.claude/settings.json` y reiniciar |
| `carpeta` | Primero preguntale cómo se dio de alta, porque el arreglo es distinto. **Si usa la terminal**: abrir Claude Code parado en la carpeta que armó el instalador (o volver a correrlo). **Si usa la app de escritorio y no toca la consola**: NO le mandes el instalador (`curl … \| bash`) — no tiene dónde pegarlo. Decile que el arreglo es dejar las reglas escritas en el `CLAUDE.md` de esta carpeta, y que te lo puede pedir a vos en el próximo mensaje (el doctor diagnostica, no toca archivos). El texto exacto es el que le dio la web al darse de alta, en `/onboard`; si no lo tiene a mano, la sección "One Brain" tiene que decir `brain_context` al arrancar, `brain_search` para consultar y `brain_save` al cerrar, agregada al final y sin pisar lo que el archivo ya tenga |
| `reglas` en `aviso` | Sus reglas quedaron atrás: siguen pidiendo lo de la versión anterior (por ejemplo, esperar el OK antes de cada guardado, que hacía que se perdieran memorias). El arreglo es de un solo paso y no toca nada más del archivo: que entre al panel → **Herramientas**, copie el pedido de "Actualizá las reglas" y lo pegue en Claude Code. Reemplaza sólo esa sección; lo que el `CLAUDE.md` tenga suyo queda intacto |
| `entrega` en `aviso` | Nada se perdió: el material recortado se vuelve a pedir en el próximo arranque. Si pasa en todos los arranques, desde el panel se pueden apagar los bloques que no use (Digest del equipo, Resumen de sesión) para que el que sí le importa entre completo; si no, avisarle al operador |
| `captura` en `aviso` | No es un problema: hay trabajo de sesiones anteriores esperando destilarse. Ofrecele guardarlo ahora |
| `conexion` 401/403 | El token no vale más: pedir uno nuevo y volver a conectar |
| `conexion` sin respuesta | Probar la red/VPN y reintentar; si sigue, avisarle al operador |
| `version` en `aviso` | Reiniciar Claude Code. Actualizó el plugin con la sesión abierta: quedó corriendo la versión vieja y los comandos nuevos no están disponibles. No hace falta volver a instalar nada |

Si todo dio `ok`, decilo derecho y agregá que si igual no ve nada guardado, reinicie la sesión para que el conector tome el token.

## Cómo se actualiza (decílo cuando haga falta actualizar, o cuando te lo pregunten)

Se corre en la **terminal**, no adentro de Claude Code:

    claude plugin marketplace update prophet
    claude plugin update one-brain@prophet

**Si esta persona no usa la terminal** (se dio de alta por el camino de la app de escritorio),
no la mandes a abrir una consola: ofrecele correrlo vos con Bash, que es exactamente el mismo
comando, y hacelo si te dice que sí. Lo único que no podés hacer por ella es el reinicio: no
podés reiniciar el proceso que te está ejecutando.

Y después **cerrar Claude Code y volver a abrirlo**. El reinicio es parte del arreglo, no una
formalidad: mientras el proceso siga vivo sigue usando la copia vieja aunque el update haya
bajado bien, y la persona concluye que actualizar no sirvió. `/clear` no alcanza — resetea la
conversación, no el proceso.

Para ver versiones: `claude plugin list` dice la instalada; el chequeo `version` de acá arriba
dice la que está corriendo esta sesión.

## Reglas

- **Nunca imprimas el token** ni lo repitas, aunque aparezca en pantalla.
- No inventes chequeos que el comando no hizo: reportás lo que devolvió, nada más.
- Un `aviso` no es una falla: mencionalo al final, sin alarma. La excepción es `version`, que sí pide una acción concreta (reiniciar) — ese decilo aunque el resto esté en verde.
- Hablá en criollo, sin jerga: quien corre esto suele no ser técnico.
