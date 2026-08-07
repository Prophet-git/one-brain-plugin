# Conectar tu equipo a One Brain

One Brain es la memoria colectiva de tu equipo: guardás decisiones y avances, y tu Claude
Code arranca cada sesión sabiendo en qué está el equipo.

## Requisitos
- Claude Code (terminal). Si lo usás en la **app de escritorio**, tu alta se hace desde
  la web (`/onboard`): ahí los pasos son los mismos salvo el primero, que no lleva `curl`.
- Un entorno POSIX: Mac y Linux ya lo son; en **Windows**, Git Bash o WSL.
- Tu **token** de acceso (te lo pasa quien te dio de alta; empieza con `ob_`).

`jq` **no** hace falta: donde el plugin necesita leer o armar JSON prueba `jq`, después
`python3` y después `perl`, y le alcanza con cualquiera de los tres. Instalarlo no molesta,
pero no instalarlo tampoco rompe nada — el `/one-brain:doctor` lo trata como opcional.

## Armá tu espacio (una vez)

Pegá esto en tu terminal (en **Windows**, en **Git Bash**), con el nombre de tu empresa:

    curl -fsSL https://onebrain.prophet.lat/setup.sh | bash -s -- "Tu Empresa"

Te deja la carpeta `Documents/one-brain` **lista para trabajar**, no una carpeta vacía:

- las reglas para que el cerebro se llene solo (`CLAUDE.md`);
- la estructura de trabajo: `notas/`, `clientes/` (con una plantilla para dar de alta), `proyectos/`, `material/` y `tareas.md`;
- **guardado automático**: cada vez que Claude termina, commitea lo que cambió. No hay que acordarse de guardar;
- protecciones: no se pisan archivos con claves ni se corren comandos que borren cosas;
- un acceso directo **"One Brain"** en el escritorio, para abrir Claude Code siempre en el lugar correcto.

Es seguro correrlo de nuevo: sólo el `CLAUDE.md` se regenera (así las reglas quedan al día).
Lo que hayas escrito vos no se toca.

> **¿Ya tenés tu carpeta de trabajo?** Entonces NO corras esto: te crearía una carpeta paralela
> que no vas a abrir nunca. En la web de alta elegí "Ya tengo mi carpeta de trabajo" y seguí por
> ahí — las reglas se te instalan en el `CLAUDE.md` global.

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
> necesita un entorno POSIX (WSL o Git Bash) — ver "¿Algo no anda?".

## Mantener el plugin al día

Los arreglos del plugin (la captura automática, los chequeos, los comandos) viajan en la
versión: una instalación vieja falla de maneras que ya están resueltas. Desde la **terminal**
(no adentro de Claude Code):

    claude plugin marketplace update prophet
    claude plugin update one-brain@prophet

**¿No usás la terminal?** Si trabajás en la app de escritorio, no hace falta que abras una
consola: pedíselo a Claude Code, que puede correrlo él. Escribile:

    Corré esto en Bash, tal cual: claude plugin marketplace update prophet && claude plugin update one-brain@prophet

Es el mismo comando; sólo cambia quién lo tipea. El reinicio de abajo sigue siendo tuyo:
Claude no puede reiniciar el proceso que lo está ejecutando.

Después **cerrá Claude Code y volvé a abrirlo**. Esto último no es opcional ni cosmético:
mientras el proceso siga vivo sigue usando la copia vieja, aunque el update haya bajado bien.
`/clear` NO alcanza — resetea la conversación, no el proceso.

Para ver qué versión estás usando: `claude plugin list` (la instalada) y `/one-brain:doctor`
(la que está corriendo esta sesión; si no coinciden, te lo dice).

Desde el arranque, si tu versión quedó atrás, One Brain te avisa solo al empezar la sesión.

## Primer arranque

Al reconectar, One Brain te saluda. Si tu cerebro es nuevo, corré:

    /one-brain:onboard

y escribimos juntos la constitución de tu empresa (misión, cómo trabajan, reglas). En la
misma charla, con lo que nos contaste, dejamos cargadas las primeras memorias del equipo:
así tu primera consulta ya devuelve algo en vez de un cerebro vacío.

## Uso diario
- Guardá lo importante: pedile a Claude "guardá esto en One Brain" o usá `brain_save`.
- Preguntá: "¿en qué está <cliente/proyecto>?", "¿qué se decidió sobre X?".
- Al arrancar cada sesión, el contexto del equipo se inyecta solo.

## Sacarle todo el provecho

One Brain tiene doce herramientas y la mayoría de la gente usa tres. En el panel web, en la
pestaña **Tools**, arriba de todo hay un pedido para copiar: lo pegás una vez en Claude Code y
te deja escrito en tu `CLAUDE.md` cómo usarlas todas y cómo manejar las sesiones (cuándo conviene
cortar y arrancar de nuevo en vez de compactar, por ejemplo). Se pega una vez y vale para siempre.

## ¿Algo no anda?
- Corré `/one-brain:status` para diagnosticar.
- "No aparecen las tools" → reiniciá la sesión (o `/reload-plugins`).
- "token inválido" → volvé a conectar con `/one-brain:connect <token>`.
