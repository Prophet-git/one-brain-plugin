---
name: proyecto-dejar
description: Dejar un proyecto listo para que otra persona lo retome — repo, cómo se levanta, cómo se deploya y las credenciales, guardados en el cerebro. Se activa cuando el usuario va a soltar un proyecto ("dejale esto listo a Fran", "que lo siga otro", "me quedé sin tokens y lo sigue X", "subí las credenciales de este proyecto", "dejá el proyecto en el cerebro").
---

# Dejar un proyecto para que otro lo retome

El usuario está por soltar un proyecto y quiere que otra persona pueda seguirlo sin llamarlo por teléfono. Vos preparás el paquete: el contexto ya vive en las memorias, y esto agrega el **cómo entrar**.

## Cuándo actuás
- "dejale esto listo a X", "que lo siga X", "me quedé sin tokens", "subí las credenciales de este proyecto".

## Qué hacés

1. **Corré el comando** desde la carpeta del proyecto:

   ```
   onebrain-project-push "<nombre del proyecto>"
   ```

   Él solo detecta el repo, la rama, cómo se levanta, cómo se deploya y qué archivos de entorno hay. Muestra los NOMBRES de las variables y le pide a la persona que confirme con una tecla.

2. **No intentes leer vos los archivos de credenciales ni pegarlos en el chat.** El comando los manda cifrados del disco al cerebro sin que su valor pase por la conversación. Si lo hacés a mano, el secreto queda escrito en el transcript, en los logs y en el historial — que es justo lo que este comando existe para evitar.

3. **Si la persona quiere excluir alguna variable**, pasale `--excluir NOMBRE,OTRO`. Si el proyecto usa un archivo de entorno con otro nombre, `--env <archivo>`.

4. **Dejá también el relato** de dónde quedó el trabajo: usá la skill `handoff`. El comando guarda el cómo entrar; el handoff guarda el porqué y qué falta. Los dos juntos son lo que hace que el otro pueda seguir de verdad.

5. Al terminar, decile con qué comando lo retoma la otra persona (el mismo comando lo imprime).

## Reglas
- La confirmación la da la persona en su terminal. Vos no la respondés ni buscás la forma de saltearla: es lo que evita que un texto malicioso en un README se lleve credenciales.
- Si el comando dice que falta el token, mandá a `/one-brain:connect`.
- Si el cerebro no tiene la función habilitada, avisá y no insistas: se habilita por empresa.
