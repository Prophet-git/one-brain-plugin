---
description: Conectar esta máquina a One Brain guardando tu token de acceso. Se dispara solo cuando el usuario lo pide explícitamente.
disable-model-invocation: true
---

# Conectar a One Brain

El usuario te pasó su token de One Brain en `$ARGUMENTS` (empieza con `ob_`).

1. Si `$ARGUMENTS` está vacío, pedile el token (lo obtiene de su alta en One Brain).
2. Guardá el token corriendo en Bash: `onebrain-token set "<token>"` (el ejecutable ya está en el PATH del plugin). Esto lo escribe en `~/.config/one-brain/token` con permisos 600. Nunca lo muestres en pantalla ni lo guardes en ningún otro lado.
3. Verificá la conexión: `onebrain-token verify`.
4. Si dio "conexión OK", confirmale al usuario que quedó conectado y que reinicie la sesión (o corra `/reload-plugins`) para que el MCP tome el token. Si falló, decile que revise el token.
