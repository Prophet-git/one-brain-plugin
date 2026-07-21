# Conectar tu equipo a One Brain

One Brain es la memoria colectiva de tu equipo: guardás decisiones y avances, y tu Claude
Code arranca cada sesión sabiendo en qué está el equipo.

## Requisitos
- Claude Code (terminal).
- `jq` instalado (`brew install jq` en Mac). Se usa para guardar la constitución.
- Tu **token** de acceso (te lo pasa quien te dio de alta; empieza con `ob_`).

## Armá tu espacio (una vez)

Pegá esto en tu terminal (en **Windows**, en **Git Bash**), con el nombre de tu empresa:

    curl -fsSL https://one-brain-kappa.vercel.app/setup.sh | bash -s -- "Tu Empresa"

Te crea la carpeta `Documents/one-brain` ya configurada (con las reglas para que el cerebro se
llene solo) + un acceso directo **"One Brain"** en el escritorio. Desde ahí vas a abrir Claude
Code siempre en el lugar correcto.

## Instalar el plugin (una vez)

Abrí Claude Code (doble clic en "One Brain") y pegá esto, en orden. **Los reinicios NO son
opcionales**: si conectás el token sin reiniciar antes, la skill `connect` todavía no está
cargada y da "unknown skill".

1. Agregá el marketplace e instalá el plugin:

    /plugin marketplace add Prophet-git/one-brain-plugin
    /plugin install one-brain@prophet

2. **Cerrá Claude Code y volvé a abrirlo** (así se cargan las skills del plugin). Verificá
   que al tipear `/one-brain:` te autocompleta los comandos.

3. Conectá tu token:

    /one-brain:connect <tu-token>

4. **Cerrá Claude Code y volvé a abrirlo otra vez** (así el conector toma tu token).

5. Confirmá con `/one-brain:status` que quedó conectado.

> En Windows: cerrar y reabrir la ventana es más confiable que `/reload-plugins`. El plugin
> necesita un entorno POSIX (WSL o Git Bash) y `jq` instalado — ver "¿Algo no anda?".

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
