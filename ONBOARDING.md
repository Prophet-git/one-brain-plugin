# Conectar tu equipo a One Brain

One Brain es la memoria colectiva de tu equipo: guardás decisiones y avances, y tu Claude
Code arranca cada sesión sabiendo en qué está el equipo.

## Antes de empezar

- **Claude Code instalado**, en la terminal o en la app. Si todavía no lo tenés, instalalo
  primero: [cómo instalar Claude Code](https://code.claude.com/docs/es/setup). El comando de
  One Brain lo busca, y si no lo encuentra se corta y tenés que pedir otro.
- Una terminal: en Mac y Linux, la que ya viene; en **Windows**, Git Bash (viene con Git for
  Windows) o WSL.

`jq` **no** hace falta: donde el plugin necesita leer o armar JSON prueba `jq`, después
`python3` y después `perl`, y le alcanza con cualquiera de los tres.

## Conectarte (una vez por computadora)

1. Entrá a [onebrain.prophet.lat](https://onebrain.prophet.lat) con Google, o con tu mail y
   una contraseña si te invitó alguien de tu equipo.
2. Elegí **"Uso Claude Code"**. El panel te muestra un comando de una línea.
3. Pegalo en tu terminal y apretá Enter. Instala el plugin, guarda tu llave de acceso y deja
   las reglas de One Brain en tu `~/.claude/CLAUDE.md`. Lo que ya tenías escrito ahí no se
   toca.
4. Abrí Claude Code en cualquier carpeta y preguntale: "¿Qué sabe el cerebro de mi empresa?".
   En el panel vas a ver cuando llega la primera consulta.

El comando sirve una sola vez y vence a los 15 minutos. Si se te venció, pedí otro en el panel.
No hay que copiar ningún token ni reiniciar nada más: sólo abrir Claude Code **después** de que
el comando terminó (una sesión que ya estaba abierta no lo ve).

**Otra computadora:** en el panel, **Ajustes → Mis computadoras**, pedí un comando nuevo y
corrélo en esa máquina. Cada computadora queda con su nombre y la podés dar de baja sola.

## Mantener el plugin al día

El comando de instalación deja prendida la actualización automática, así que normalmente no
tenés que hacer nada. Si One Brain te avisa al arrancar que tu versión quedó atrás, desde la
**terminal** (no adentro de Claude Code):

    claude plugin marketplace update prophet
    claude plugin update one-brain@prophet

**¿No usás la terminal?** Pedíselo a Claude Code, que puede correrlo él. Escribile:

    Corré esto en Bash, tal cual: claude plugin marketplace update prophet && claude plugin update one-brain@prophet

Después **cerrá Claude Code y volvé a abrirlo**. Mientras el proceso siga vivo usa la copia
vieja, aunque el update haya bajado bien. `/clear` no alcanza: resetea la conversación, no el
proceso.

Para ver qué versión estás usando: `claude plugin list` (la instalada) y `/one-brain:doctor`
(la que está corriendo esta sesión; si no coinciden, te lo dice).

## Primer arranque

Si tu cerebro es nuevo, corré:

    /one-brain:onboard

y escribimos juntos la constitución de tu empresa (misión, cómo trabajan, reglas). En la
misma charla, con lo que nos contaste, dejamos cargadas las primeras memorias del equipo:
así tu primera consulta ya devuelve algo en vez de un cerebro vacío.

## Uso diario

- Guardá lo importante: pedile a Claude "guardá esto en One Brain".
- Preguntá: "¿en qué está <cliente/proyecto>?", "¿qué se decidió sobre X?".
- Al arrancar cada sesión, el contexto del equipo se carga solo.

One Brain tiene más de veinte herramientas y el comando de instalación ya le deja escrito a
Claude cómo usarlas, en tu `~/.claude/CLAUDE.md`. No hace falta pegar nada más.

## ¿Algo no anda?

- Corré `/one-brain:doctor`: te dice qué falta y cuál es el próximo paso.
- "No aparecen las herramientas": cerrá Claude Code y volvé a abrirlo.
- "Token inválido" o te dieron de baja una computadora: pedí un comando nuevo en el panel
  (**Ajustes → Mis computadoras**) y corrélo de nuevo. Sirve también para reparar una
  instalación vieja.
