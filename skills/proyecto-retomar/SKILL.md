---
name: proyecto-retomar
description: Retomar el proyecto de un compañero — trae el contexto, el repo, cómo se levanta, cómo se deploya y escribe las credenciales en su lugar. Se activa cuando el usuario va a continuar algo que dejó otro ("retomo lo de Lempriere", "sigo el proyecto de Fran", "traeme las credenciales de X", "necesito entrar al proyecto X", "voy a seguir X donde lo dejaron").
---

# Retomar el proyecto de otro

Alguien dejó un proyecto listo y el usuario lo va a continuar. Vos le dejás la máquina en condiciones de trabajar en un solo paso.

## Cuándo actuás
- "retomo lo de X", "sigo el proyecto de X", "necesito entrar al proyecto X", "traeme las credenciales de X".

## Qué hacés

1. **Traé primero el contexto** con la tool `brain_project` (o corriendo el comando con `--solo-contexto`): repo, rama, cómo se levanta, cómo se deploya, qué servicios toca y qué credenciales hay. Contale eso al usuario en dos líneas antes de tocar nada.

2. **Sumá el porqué**: buscá el handoff y las decisiones recientes de ese proyecto con `brain_search`. El cómo entrar sin el porqué deja a la persona ejecutando pasos que no entiende.

3. **Si necesita las credenciales**, que corra desde la carpeta del proyecto:

   ```
   onebrain-project-pull "<proyecto>"
   ```

   El comando le va a pedir una tecla en su terminal y recién ahí escribe. **Esa confirmación la da la persona, no vos**: es lo que impide que un texto malicioso metido en un README o en un issue se lleve credenciales sin que nadie se entere.

4. **Nunca pidas ni muestres el valor de una credencial en el chat.** El comando las escribe directo en su archivo. Vos solo ves qué se escribió, por nombre. Si el usuario te pide el valor, explicale que no pasa por acá a propósito y que ya está en su archivo.

5. Si el comando avisa que una credencial es vieja, o que el archivo no está en `.gitignore`, repetíselo: son las dos formas más comunes de perder media hora o de filtrar un secreto sin querer.

## Reglas
- Si el proyecto no existe en el cerebro, no lo inventes: ofrecé `brain_entities` para ver cuáles hay.
- Si el comando avisa que el repo donde está parado NO es el del proyecto, **paralo**. Eso es exactamente lo que la defensa quiere frenar: no lo empujes a confirmar.
- Si el cerebro no tiene la función habilitada, avisá y no insistas: se habilita por empresa.
