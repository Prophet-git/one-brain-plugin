# Conectar tu equipo a One Brain

One Brain es la memoria colectiva de tu equipo: guardás decisiones y avances, y tu Claude
Code arranca cada sesión sabiendo en qué está el equipo.

## Requisitos
- Claude Code (terminal).
- `jq` instalado (`brew install jq` en Mac). Se usa para guardar la constitución.
- Tu **token** de acceso (te lo pasa quien te dio de alta; empieza con `ob_`).

## Instalación (una vez)

Pegá esto en Claude Code, en orden:

    /plugin marketplace add Prophet-git/one-brain-plugin
    /plugin install one-brain@prophet
    /one-brain:connect <tu-token>

Después **reiniciá la sesión** (o corré `/reload-plugins`) para que se active el conector.

## Primer arranque

Al reconectar, One Brain te saluda. Si tu cerebro es nuevo, corré:

    /one-brain:onboard

y escribimos juntos la constitución de tu empresa (misión, cómo trabajan, reglas).

## Uso diario
- Guardá lo importante: pedile a Claude "guardá esto en One Brain" o usá `brain_save`.
- Preguntá: "¿en qué está <cliente/proyecto>?", "¿qué se decidió sobre X?".
- Al arrancar cada sesión, el contexto del equipo se inyecta solo.

## ¿Algo no anda?
- Corré `/one-brain:status` para diagnosticar.
- "No aparecen las tools" → reiniciá la sesión (o `/reload-plugins`).
- "token inválido" → volvé a conectar con `/one-brain:connect <token>`.
