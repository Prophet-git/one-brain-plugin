---
name: proyecto-dejar
description: Dejar un proyecto listo para que otra persona lo retome — repo, cómo se levanta, cómo se deploya y las credenciales, guardados en el cerebro. Se activa cuando el usuario va a soltar un proyecto ("dejale esto listo a Fran", "que lo siga otro", "me quedé sin tokens y lo sigue X", "subí las credenciales de este proyecto", "dejá el proyecto en el cerebro").
---

# Dejar un proyecto para que otro lo retome

El usuario está por soltar un proyecto y quiere que otra persona pueda seguirlo sin llamarlo por teléfono. Vos preparás el paquete: el contexto ya vive en las memorias, y esto agrega el **cómo entrar**.

## Cuándo actuás
- "dejale esto listo a X", "que lo siga X", "me quedé sin tokens", "subí las credenciales de este proyecto".

## Qué hacés

1. **El comando es** `onebrain-project-push "<nombre del proyecto>"`, desde la carpeta del proyecto o con `--dir <ruta>`.

   Él solo detecta el repo, la rama, cómo se levanta, cómo se deploya, qué archivos de entorno hay, y propone una descripción sacada del README. Muestra los NOMBRES de las variables y le pide a la persona que confirme con una tecla.

2. **Completá los tres campos que el comando no puede adivinar**, porque son los que hacen que el proyecto se entienda desde el panel:

   - `--descripcion "qué hace este proyecto"` — dos líneas, para alguien que no lo conoce. Si el README ya lo explica bien, no hace falta: el comando lo propone solo. Esa propuesta se usa **sólo si el proyecto todavía no tiene descripción**: nunca reemplaza la que alguien haya escrito. Para corregir una descripción ya cargada hay que pasar `--descripcion` a propósito.
   - `--prod <url>` — dónde se lo mira andando. No se puede detectar; si no lo sabés, preguntáselo a la persona antes de correr el comando.
   - `--roadmap-file <archivo>` — para dónde va el proyecto. Si hay un plan escrito en el repo, pasalo. Si no, proponé vos un roadmap corto a partir de lo que se habló en la sesión, guardalo en un archivo y mostráselo a la persona ANTES de subirlo: es texto que va a quedar publicado en el panel de la empresa con su nombre.

   Sin `--roadmap-file` el roadmap que ya estuviera cargado no se toca, ni se mueve su fecha. Eso es a propósito: el panel muestra cuándo se actualizó por última vez, y esa fecha tiene que decir la verdad.

   Mirá también qué va a decir "Se deploya": el comando lee `docs/runbooks/deploy.md` o `DEPLOY.md` si existen, y si no adivina del `vercel.json` un `vercel deploy --prod` que suele quedar incompleto (sin el `--scope` del team, por ejemplo). Si lo que adivinó está mal, escribí el runbook en el repo antes de subir el perfil: es el dato que el otro va a ejecutar sin pensar.

3. **Si la persona quiere excluir alguna variable**, pasale `--excluir NOMBRE,OTRO`. Si el proyecto usa un archivo de entorno con otro nombre, `--env <archivo>`.

4. **No lo corras vos.** La confirmación se lee de `/dev/tty`, así que desde el `!` de Claude Code, desde Codex o desde cualquier canal no interactivo **no sube nada**: imprime la vista previa entera, prolija, y muere con "hace falta una terminal para confirmar qué credenciales se suben". Se ve igual que si hubiera funcionado y la persona se queda creyendo que subió. Es la trampa más común de este comando, y la pregunta se hace siempre, aunque el proyecto no tenga ninguna credencial.

5. **Abrile la terminal Y dale el texto para pegar. Las dos cosas, siempre.** No alcanza con decirle "correlo en una terminal": armá el comando completo, con las rutas ya resueltas y sin un solo `<placeholder>` sin completar.

   Guardá el comando (o los comandos, si son varios proyectos) en un `.sh` y abrí la terminal ejecutándolo. En macOS:

   ```
   osascript -e 'tell application "Terminal" to do script "sh <ruta del .sh>"' \
             -e 'tell application "Terminal" to activate'
   ```

   Y en el mismo mensaje pegale el comando en un bloque de código, listo para copiar, por si prefiere hacerlo a mano o la ventana no se abrió. Decile textual qué le va a preguntar (`¿Subo esto al cerebro?`) y qué tiene que contestar (`s`). Si no estás en macOS, no inventes el equivalente: dale el bloque para copiar y listo.

6. **Verificá vos que haya entrado**, no le preguntes si funcionó: `brain_project "<proyecto>"` tiene que devolver el perfil cargado y no `profile: null`.

7. **No intentes leer vos los archivos de credenciales ni pegarlos en el chat.** El comando los manda cifrados del disco al cerebro sin que su valor pase por la conversación. Si lo hacés a mano, el secreto queda escrito en el transcript, en los logs y en el historial — que es justo lo que este comando existe para evitar.

8. **Dejá también el relato** de dónde quedó el trabajo: usá la skill `handoff`. El comando guarda el cómo entrar; el handoff guarda el porqué y qué falta. Los dos juntos son lo que hace que el otro pueda seguir de verdad.

9. Al terminar, decile con qué comando lo retoma la otra persona (el mismo comando lo imprime).

## Reglas
- La confirmación la da la persona en su terminal. Vos no la respondés ni buscás la forma de saltearla (nada de `script`, `expect`, pipes ni un `yes` por delante): es lo que evita que un texto malicioso en un README se lleve credenciales. Abrirle la ventana con el comando ya cargado NO es saltearla — la pregunta le sigue apareciendo a ella y la contesta ella. Eso es justamente lo que tenés que hacer.
- Si el comando dice que falta el token, mandá a `/one-brain:connect`.
- Si el cerebro no tiene la función habilitada, avisá y no insistas: se habilita por empresa.
