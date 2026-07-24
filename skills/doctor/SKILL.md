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
   - **curl** — si está la herramienta que usa el plugin para hablar con el cerebro.
   - **parser** — si los hooks pueden leer lo que les manda Claude Code (si esto falla, la captura automática no anda aunque todo lo demás esté bien).
   - **hooks** — si `disableAllHooks` está apagando todos los hooks del sistema.
   - **carpeta** — si existe la carpeta de trabajo con su `CLAUDE.md`.
   - **conexion** — si el cerebro responde con este token.
   - **version** — qué versión del plugin está instalada.

## Cómo lo reportás

Primero **el veredicto en una línea**: "está todo bien" o "encontré N problemas". Después solo lo que no está en verde, con el arreglo concreto:

| Falla | Qué le decís que haga |
|---|---|
| `token` | Pedile el token a quien le dio acceso y corré `/one-brain:connect <token>` |
| `curl` | Instalar curl (en Windows: usar Git Bash o WSL, que ya lo traen) |
| `parser` | Actualizar el plugin: `/plugin marketplace update prophet` y `/plugin install one-brain@prophet`, después reiniciar Claude Code |
| `hooks` | Sacar `"disableAllHooks": true` de `~/.claude/settings.json` y reiniciar |
| `carpeta` | Correr el instalador de la carpeta de trabajo, o abrir Claude Code desde la carpeta donde tenga su `CLAUDE.md` |
| `conexion` 401/403 | El token no vale más: pedir uno nuevo y volver a conectar |
| `conexion` sin respuesta | Probar la red/VPN y reintentar; si sigue, avisarle al operador |

Si todo dio `ok`, decilo derecho y agregá que si igual no ve nada guardado, reinicie la sesión para que el conector tome el token.

## Reglas

- **Nunca imprimas el token** ni lo repitas, aunque aparezca en pantalla.
- No inventes chequeos que el comando no hizo: reportás lo que devolvió, nada más.
- Un `aviso` no es una falla: mencionalo al final, sin alarma.
- Hablá en criollo, sin jerga: quien corre esto suele no ser técnico.
