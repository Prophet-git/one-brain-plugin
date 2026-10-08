---
name: proyecto-retomar
description: Retomar el proyecto de un compañero — trae el contexto, el repo, cómo se levanta, cómo se deploya y escribe las credenciales en su lugar. Se activa cuando el usuario va a continuar algo que dejó otro ("retomo lo de Acme", "sigo el proyecto de Ana", "traeme las credenciales de X", "necesito entrar al proyecto X", "voy a seguir X donde lo dejaron").
---

# Retomar el proyecto de otro

Alguien dejó un proyecto listo y el usuario lo va a continuar. Vos le dejás la máquina en condiciones de trabajar en un solo paso.

## Cuándo actuás
- "retomo lo de X", "sigo el proyecto de X", "necesito entrar al proyecto X", "traeme las credenciales de X".

## Qué hacés

1. **Leé primero la ficha** con `brain_ficha "<proyecto>"`: dónde está, qué sigue, qué está bloqueado y en quién, qué se pactó con el cliente y qué hay que saber antes de tocar. Es el estado vigente; si un handoff viejo dice otra cosa, gana la ficha. Si `frescura.memorias_posteriores` es mayor a 0, hubo trabajo después de su último cambio: buscalo en el paso 3 antes de confiar. Sin ficha, seguí igual.

2. **Traé el cómo entrar** con la tool `brain_project` (o corriendo el comando con `--solo-contexto`): repo, rama, cómo se levanta, cómo se deploya, qué servicios toca y qué credenciales hay. Contale eso al usuario en dos líneas antes de tocar nada.

3. **Sumá el porqué**: buscá el handoff y las decisiones recientes de ese proyecto con `brain_search`. El cómo entrar sin el porqué deja a la persona ejecutando pasos que no entiende.

4. **Si necesita las credenciales**, el comando es `onebrain-project-pull "<proyecto>"` desde la carpeta del proyecto.

   Le va a pedir una tecla en su terminal y recién ahí escribe. **Esa confirmación la da la persona, no vos**: es lo que impide que un texto malicioso metido en un README o en un issue se lleve credenciales sin que nadie se entere.

   Como la pregunta se lee de `/dev/tty`, desde el `!` de Claude Code o cualquier canal no interactivo el comando **no escribe nada**: muere con "hace falta una terminal para confirmar la escritura de credenciales" después de haber impreso todo, así que parece que anduvo. Entonces hacé las dos cosas: abrile la terminal ya corriendo el comando (macOS: `osascript -e 'tell application "Terminal" to do script "..."' -e 'tell application "Terminal" to activate'`) **y** pegale el comando completo en un bloque de código, con las rutas resueltas, para que lo copie si prefiere. Decile qué le va a preguntar y qué contestar.

5. **Nunca pidas ni muestres el valor de una credencial en el chat.** El comando las escribe directo en su archivo. Vos solo ves qué se escribió, por nombre. Si el usuario te pide el valor, explicale que no pasa por acá a propósito y que ya está en su archivo.

6. Si el comando avisa que una credencial es vieja, o que el archivo no está en `.gitignore`, repetíselo: son las dos formas más comunes de perder media hora o de filtrar un secreto sin querer.

## Reglas
- Si el proyecto no existe en el cerebro, no lo inventes: ofrecé `brain_entities` para ver cuáles hay.
- Si el comando avisa que el repo donde está parado NO es el del proyecto, **paralo**. Eso es exactamente lo que la defensa quiere frenar: no lo empujes a confirmar.
- Si el cerebro no tiene la función habilitada, avisá y no insistas: se habilita por empresa.
