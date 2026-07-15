# Contrato de adaptador de fuente (reuniones)

El núcleo de la captura (traer → `POST /api/meetings` → ofrecer destilar) es **agnóstico de la
fuente**. Cada fuente implementa este contrato mínimo; el resto del flujo no cambia.

## Interfaz
- `listRecent(sinceDays | sinceExternalId)` → `[{ external_id, title, meeting_date, participants }]`
  (metadatos, SIN transcript — barato).
- `getTranscript(external_id)` → markdown crudo de la reunión.

El `external_id` es el id de la reunión EN la fuente. El dedup del cerebro es por
`(tenant, source, external_id)`, así que cada fuente usa su propio `source` (`granola`, `fathom`,
`fireflies`) y sus ids nativos.

## Fuentes
- **granola** (SP2, implementada): vía el MCP oficial (`mcp__granola__list_meetings` /
  `mcp__granola__get_meeting_transcript`). Semi-automática: Claude en el loop (un hook no puede
  invocar un MCP). Ver `SKILL.md`.
- **fathom** (SP3, pendiente): API REST + OAuth. Al ser REST, el hook puede traer el crudo y
  hacer el `POST` solo (automático puro), sin Claude en el loop.
- **fireflies** (SP3, pendiente): API REST + API key. Igual que Fathom.

## Descartado
Acceso automático a Granola leyendo el token local de la app (`~/Library/Application Support/
Granola/supabase.json`): la API interna rechaza clientes no oficiales (obliga a mandar la versión
exacta de la app, se rompe en cada update), el token dura 6 h y refrescarlo puede desloguear al
usuario de Granola. Frágil → se usa el MCP oficial.
