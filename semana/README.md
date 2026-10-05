# Semana (plugin)

Sube las sesiones de Claude Code de esta Mac a la vista Semana de One Brain.

- `recolectar.py`: lee `~/.claude/projects` (o `$CLAUDE_CONFIG_DIR/projects`), parte cada sesión en
  bloques (una pausa de más de 30 minutos corta) y sube a `/api/semana/bloques` sólo lo que cambió.
  Python 3.9 sin dependencias. Estado en `~/.onebrain/semana/` (`cache.json`, `ultimo-envio.json`,
  `rechazos.log`).
- `../bin/onebrain-semana-push`: lo corre con el token del perfil. A mano sirve para ver qué subió.
- `../scripts/semana-stop.sh`: el hook Stop. Lo lanza en segundo plano, como mucho una vez cada 10
  minutos, y no imprime nada. Sin `python3` o sin token no hace nada.

Tests (con pytest instalado en el Python de macOS): `/usr/bin/python3 -m pytest plugin/semana`.

## El % del plan (opcional)

La vista muestra qué % del plan se llevó cada proyecto si el statusline anota los límites cuando
cambian. Sumar esto a `~/.claude/statusline.sh` (necesita `jq`), donde `$input` es el JSON que
Claude Code le pasa por stdin:

```sh
RL=$(printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
if [ -n "$RL" ]; then
  mkdir -p "$HOME/.semana"
  LAST=$(tail -1 "$HOME/.semana/plan.jsonl" 2>/dev/null | jq -c '.rate_limits' 2>/dev/null)
  [ "$RL" != "$LAST" ] && printf '{"ts":%s,"rate_limits":%s}\n' "$(date +%s)" "$RL" >> "$HOME/.semana/plan.jsonl"
fi
```

El recolector sube las muestras nuevas de `~/.semana/plan.jsonl` (otra ruta: `ONE_BRAIN_SEMANA_PLAN`).
