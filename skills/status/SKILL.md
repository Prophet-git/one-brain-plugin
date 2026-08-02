---
name: status
description: Ver el estado de la conexión de esta máquina a One Brain — si hay token, a qué URL apunta y si el conector responde. Se activa cuando el usuario lo pide ("¿estoy conectado a One Brain?", "chequeá la conexión", "estado de One Brain", "por qué no anda el brain", "/one-brain:status").
---

# Estado de One Brain

Reportás si esta máquina está conectada a One Brain y, si algo falla, el próximo paso concreto. NO cambies nada: esta skill solo diagnostica.

## Qué hacés

1. **Token configurado.** Corré en Bash: `onebrain-token check`. El ejecutable ya está en el PATH del plugin y responde si hay token en `~/.config/one-brain/token` **sin imprimirlo**.
   - "hay token guardado" → está conectado.
   - "sin token" (o exit ≠ 0) → NO hay token. Saltá al reporte: "no conectado, falta el token".
   - Es `check` y no `get` a propósito: `get` imprime la credencial en claro y todo lo que sale por pantalla queda escrito en el transcript de esta sesión. Para saber si hay token no hace falta verlo.

2. **El conector responde.** Solo si hay token, corré: `onebrain-token verify`. Hace un `tools/list` contra el endpoint MCP y espera HTTP 200.
   - "conexión OK" → el conector responde.
   - "falló (<código>)" → el token existe pero el server lo rechaza o no responde (ej. 401 = token inválido/revocado, 000 = sin red).

3. **URL de destino.** Es `https://onebrain.prophet.lat` por default, o el valor de `ONE_BRAIN_URL` si está seteada. Reportá a cuál apunta.

## Reporte (claro y corto)

Decile al usuario:
- **Conectado sí/no** — con verde/rojo conceptual, sin rodeos.
- **A qué URL** apunta el conector.
- **Próximo paso** si algo falla:
  - Sin token → "corré `/one-brain:connect <tu-token>` para conectar".
  - `verify` falló con 401/403 → "el token no es válido o fue revocado; volvé a conectar con `/one-brain:connect`".
  - `verify` falló con 000/timeout → "no hay red o el server no responde; reintentá en un rato".
  - Todo OK pero las tools MCP no aparecen → "reiniciá la sesión (o `/reload-plugins`) para que el MCP tome el token".

## Reglas
- No inventes: el estado que reportás sale de lo que devuelven `onebrain-token check` y `verify`, nada más.
- Nunca imprimas el token en claro.
