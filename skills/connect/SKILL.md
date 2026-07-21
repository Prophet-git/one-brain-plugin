---
name: connect
description: Conectar esta máquina a One Brain guardando tu token de acceso. Se dispara cuando el usuario lo pide ("/one-brain:connect", "conectar One Brain", "acá está mi token de One Brain").
---

# Conectar a One Brain

El usuario te pasó su token de One Brain en `$ARGUMENTS` (empieza con `ob_`).

1. Si `$ARGUMENTS` está vacío, pedile el token (lo obtiene de su alta en One Brain).
2. Guardá el token corriendo en Bash: `onebrain-token set "<token>"` (el ejecutable ya está en el PATH del plugin). Esto lo escribe en `~/.config/one-brain/token` con permisos 600. Nunca lo muestres en pantalla ni lo guardes en ningún otro lado.
3. Verificá la conexión: `onebrain-token verify`. Si falló, decile que revise el token y cortá acá.
4. **PASO OBLIGATORIO — no lo omitas ni lo pongas como opcional.** Sin este paso el conector NO toma el token y Claude Code le va a ofrecer un login por OAuth por error. Decile al usuario, textual:

   > ✅ Token guardado. **Último paso, imprescindible: reiniciá Claude Code** (cerralo y volvé a abrirlo) o corré **`/reload-plugins`**.
   >
   > Por qué: el conector de One Brain se engancha al ARRANCAR la sesión, cuando tu token todavía no estaba. Hasta que no reinicies, va a pedirte un login por OAuth que **NO tenés que usar**. Después del reinicio, el token se toma solo y las herramientas de One Brain quedan disponibles. Si te aparece un link de OAuth, ignoralo y reiniciá.

## Regla
- El reinicio / `/reload-plugins` del paso 4 es EL paso que hace que funcione. Tratalo como parte de la conexión, no como un extra.
- Nunca imprimas el token en claro.
