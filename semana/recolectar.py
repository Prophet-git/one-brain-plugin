"""Semana: junta las sesiones de Claude Code de esta Mac y las sube a One Brain.

Lee ~/.claude/projects (o $CLAUDE_CONFIG_DIR/projects), parte cada sesión en bloques de trabajo
(una pausa de más de 30 minutos corta el bloque) y sube a /api/semana/bloques sólo lo que cambió
desde la última corrida. También sube las muestras nuevas del % del plan que anota el statusline
en ~/.semana/plan.jsonl.

El proyecto NO se decide acá: cada bloque lleva señales crudas (los repos que tocó, las entidades
que nombró en brain_save) y el servidor lo resuelve al leer, con las entidades y fichas del
cerebro. Lo pesado (leer los logs) lo hace la Mac.

Port de ~/Code/semana/scripts/recolectar.py, el prototipo aprobado. Cada regla del parseo salió de
un bug real (respuestas repetidas por bloque, worktrees, tramos automáticos por origin.kind,
agentes de workflows); no simplificar sin mirar sus tests.

Compatible con Python 3.9 (el que trae macOS) y sin dependencias. Estado en ~/.onebrain/semana/.

Uso (lo lanza plugin/bin/onebrain-semana-push):
  python3 recolectar.py            sube lo que cambió y dice en una línea qué subió
  python3 recolectar.py --aviso    una línea si Semana dejó de andar (arranque de sesión), o nada
  python3 recolectar.py --estado   la línea del doctor: semana|ok|... o semana|aviso|...
"""
from __future__ import annotations

import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from collections import Counter
from datetime import datetime
from pathlib import Path

HOME = Path.home()
CODE = HOME / "Code"
PAUSA_MS = 30 * 60 * 1000
# El servidor acepta hasta 500 por request. Un bloque con muchos subagentes pesa: 200 deja margen
# para no rozar el tope de tamaño de body de Vercel (4,5 MB).
LOTE = 200

# USD por millón de tokens. Fuente: skill claude-api, tabla cacheada el 2026-09-25.
# Escritura de cache: 1,25x la entrada (5 min) y 2x (1 h). Lectura: propia por modelo.
PRECIOS = {
    "claude-opus-5-5": {"input": 4.00, "output": 20.00, "cache_read": 0.20},
    "claude-opus-5": {"input": 5.00, "output": 25.00, "cache_read": 0.50},
    "claude-opus-4-8": {"input": 5.00, "output": 25.00, "cache_read": 0.50},
    "claude-opus-4-7": {"input": 5.00, "output": 25.00, "cache_read": 0.50},
    "claude-sonnet-5-5": {"input": 2.00, "output": 10.00, "cache_read": 0.20},
    "claude-sonnet-5": {"input": 2.00, "output": 10.00, "cache_read": 0.20},
    "claude-fable-5-1": {"input": 10.00, "output": 50.00, "cache_read": 0.25},
    "claude-fable-5": {"input": 10.00, "output": 50.00, "cache_read": 1.00},
    "claude-haiku-4-5": {"input": 1.00, "output": 5.00, "cache_read": 0.10},
}

RE_REPO = re.compile(r"(?:/Users/[^/\"\s]+/Code/|~/Code/)([A-Za-z0-9_.-]+)(?:/([A-Za-z0-9_.-]+))?")
CLAVES_TOKENS = ("input", "output", "cache_read", "cache_write_5m", "cache_write_1h")
VAULT = "vault"


class ErrorEnvio(Exception):
    """El servidor no recibió el lote (red, 5xx, token). Se reintenta en la próxima corrida.
    `codigo` es el HTTP ("000" sin respuesta): 401, 403 y 404 frenan las corridas (ver pausas)."""

    def __init__(self, mensaje, codigo=""):
        super().__init__(mensaje)
        self.codigo = codigo


class Rechazo(Exception):
    """El servidor rechazó el lote (400/413/422): el dato no le sirve. El mensaje es su motivo."""


def normalizar_modelo(m):
    if not m:
        return ""
    m = m.split("[")[0]
    return re.sub(r"-\d{8}$", "", m)


def normalizar_repo(nombre):
    nombre = nombre.rstrip(".")
    if nombre == "bats-second-brain":
        return VAULT
    return re.sub(r"-worktrees?$", "", nombre)


_RESUELTOS = {}


def resolver_repo(nombre, sub=None, code=None):
    """Lleva una ruta de ~/Code al repo real: un worktree cuenta como su repo base."""
    code = code or CODE
    nombre = nombre.rstrip(".")
    clave = (str(code), nombre, sub)
    if clave in _RESUELTOS:
        return _RESUELTOS[clave]
    d = None
    if sub and (code / nombre / sub).is_dir() and not (code / nombre / ".git").exists():
        d = code / nombre / sub
    elif (code / nombre).is_dir():
        d = code / nombre
    resultado = normalizar_repo(nombre)
    if d is not None:
        r = subprocess.run(["git", "-C", str(d), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            comun = Path(r.stdout.strip())
            base = (comun.parent if comun.name == ".git" else comun).name
            # un worktree del vault es un proyecto propio (radar-compras-sdd), no "vault"
            resultado = normalizar_repo(base) if base != "bats-second-brain" or d == code / base else normalizar_repo(d.name)
    _RESUELTOS[clave] = resultado
    return resultado


def costo(modelo, tok):
    p = PRECIOS.get(normalizar_modelo(modelo))
    if not p:
        return 0
    return (
        tok.get("input", 0) * p["input"]
        + tok.get("output", 0) * p["output"]
        + tok.get("cache_read", 0) * p["cache_read"]
        + tok.get("cache_write_5m", 0) * p["input"] * 1.25
        + tok.get("cache_write_1h", 0) * p["input"] * 2
    ) / 1_000_000


def tokens_de(usage):
    cc = usage.get("cache_creation") or {}
    w1h = cc.get("ephemeral_1h_input_tokens", 0) or 0
    w5m = cc.get("ephemeral_5m_input_tokens")
    if w5m is None:
        w5m = (usage.get("cache_creation_input_tokens", 0) or 0) - w1h
    return {
        "input": usage.get("input_tokens", 0) or 0,
        "output": usage.get("output_tokens", 0) or 0,
        "cache_read": usage.get("cache_read_input_tokens", 0) or 0,
        "cache_write_5m": max(w5m or 0, 0),
        "cache_write_1h": w1h,
    }


def sumar(a, b):
    return {k: a.get(k, 0) + b.get(k, 0) for k in CLAVES_TOKENS}


def a_ms(ts):
    if not ts:
        return None
    try:
        return int(datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return None


def texto_usuario(contenido):
    if isinstance(contenido, list):
        partes = [c.get("text", "") for c in contenido if isinstance(c, dict) and c.get("type") == "text"]
        contenido = " ".join(partes) if partes else None
    if not isinstance(contenido, str):
        return None
    t = contenido.strip()
    if not t or t.startswith("<") or t.startswith("Caveat:") or t.startswith("[Request interrupted"):
        return None
    return t[:400]


def leer_mensajes(path):
    """Devuelve (mensajes del asistente sin repetir, marcas de actividad, extra)."""
    por_id = {}
    actividad = []
    extra = {"titulo_ia": None, "titulo_custom": None, "primer_mensaje": None, "cwd": None, "entrypoint": None}
    with open(path, errors="replace") as f:
        for linea in f:
            try:
                d = json.loads(linea)
            except json.JSONDecodeError:
                continue
            if not isinstance(d, dict):
                continue
            t = d.get("type")
            if t == "ai-title":
                extra["titulo_ia"] = d.get("aiTitle") or extra["titulo_ia"]
            elif t == "custom-title":
                extra["titulo_custom"] = d.get("customTitle") or extra["titulo_custom"]
            if t not in ("user", "assistant"):
                continue
            ms = a_ms(d.get("timestamp"))
            if ms is None:
                continue
            extra["cwd"] = extra["cwd"] or d.get("cwd")
            extra["entrypoint"] = extra["entrypoint"] or d.get("entrypoint")
            if t == "user":
                if d.get("isMeta"):
                    continue
                txt = texto_usuario((d.get("message") or {}).get("content"))
                if txt:
                    actividad.append(ms)
                    extra["primer_mensaje"] = extra["primer_mensaje"] or txt
                    if (d.get("origin") or {}).get("kind", "human") == "human":
                        extra.setdefault("humanos", []).append(ms)
                continue
            m = d.get("message") or {}
            mid = m.get("id") or d.get("uuid")
            actividad.append(ms)
            repos = Counter()
            entidades = Counter()
            for b in m.get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    for nombre, sub in RE_REPO.findall(json.dumps(b.get("input"))):
                        repos[resolver_repo(nombre, sub or None)] += 1
                    if str(b.get("name", "")).endswith("brain_save"):
                        ents = (b.get("input") or {}).get("entities") or []
                        entidades.update(e for e in ents if isinstance(e, str))
            previo = por_id.get(mid)
            if previo:
                previo["repos"].update(repos)
                previo["entidades"].update(entidades)
                if m.get("usage"):
                    previo["tokens"] = tokens_de(m["usage"])
                continue
            por_id[mid] = {
                "ts": ms,
                "modelo": normalizar_modelo(m.get("model")),
                "tokens": tokens_de(m.get("usage") or {}),
                "repos": repos,
                "entidades": entidades,
            }
    mensajes = sorted((x for x in por_id.values() if x["modelo"] and x["modelo"] != "<synthetic>"), key=lambda x: x["ts"])
    return mensajes, sorted(actividad), extra


def parsear_subagentes(path):
    carpeta = path.with_suffix("") / "subagents"
    if not carpeta.is_dir():
        return []
    subs = []
    for f in sorted(carpeta.rglob("agent-*.jsonl")):
        meta_p = f.with_suffix(".meta.json")
        try:
            meta = json.loads(meta_p.read_text()) if meta_p.exists() else {}
        except ValueError:
            meta = {}
        if "workflows" in f.relative_to(carpeta).parts and not meta.get("agentType"):
            meta["agentType"] = "workflow"
        mensajes, actividad, _ = leer_mensajes(f)
        if not actividad:
            continue
        tok = {k: 0 for k in CLAVES_TOKENS}
        modelos = Counter()
        repos_sub = Counter()
        c = 0.0
        for m in mensajes:
            repos_sub.update(m["repos"])
            tok = sumar(tok, m["tokens"])
            modelos[m["modelo"]] += 1
            c += costo(m["modelo"], m["tokens"])
        subs.append({
            "tipo": meta.get("agentType") or "general-purpose",
            "descripcion": meta.get("description") or "",
            "inicio": actividad[0],
            "fin": actividad[-1],
            "modelos": dict(modelos),
            "tokens": tok,
            "costo": round(c, 6),
            # no viaja: se suma a los repos del bloque, que es donde el servidor lo lee
            "_repos": repos_sub,
        })
    return subs


def parsear_sesion(path):
    path = Path(path)
    mensajes, actividad, extra = leer_mensajes(path)
    return {
        "id": path.stem,
        "titulo": extra["titulo_custom"] or extra["titulo_ia"],
        "primer_mensaje": extra["primer_mensaje"],
        "cwd": extra["cwd"],
        # claude -p y el Agent SDK: rutinas que corren solas, no trabajo frente a la pantalla
        "automatica": extra["entrypoint"] == "sdk-cli",
        "humanos": extra.get("humanos", []),
        "mensajes": mensajes,
        "actividad": actividad,
        "subagentes": parsear_subagentes(path),
    }


def repo_de_cwd(cwd):
    if not cwd:
        return None
    m = RE_REPO.search(cwd)
    if not m:
        return None
    r = resolver_repo(m.group(1), m.group(2))
    return None if r == VAULT else r


def bloques(s):
    """Los bloques de una sesión, con las señales crudas del contrato de /api/semana/bloques."""
    if not s["actividad"]:
        return []
    tramos = [[s["actividad"][0], s["actividad"][0]]]
    for ms in s["actividad"][1:]:
        if ms - tramos[-1][1] > PAUSA_MS:
            tramos.append([ms, ms])
        else:
            tramos[-1][1] = ms
    cwd = repo_de_cwd(s["cwd"])
    salida = []
    for i, (ini, fin) in enumerate(tramos):
        msjs = [m for m in s["mensajes"] if ini <= m["ts"] <= fin]
        subs = [x for x in s["subagentes"] if ini <= x["inicio"] <= fin + PAUSA_MS]
        repos = Counter()
        entidades = Counter()
        tok = {k: 0 for k in CLAVES_TOKENS}
        modelos = Counter()
        c = 0.0
        for m in msjs:
            repos.update(m["repos"])
            entidades.update(m["entidades"])
            tok = sumar(tok, m["tokens"])
            modelos[m["modelo"]] += 1
            c += costo(m["modelo"], m["tokens"])
        for x in subs:
            tok = sumar(tok, x["tokens"])
            c += x["costo"]
            repos.update(x["_repos"])
        # el vault no dice nada: Bauti trabaja siempre desde ahí
        repos.pop(VAULT, None)
        salida.append({
            "bloque_id": f"{s['id']}#{i}",
            "sesion": s["id"],
            # un tramo sin ningún mensaje escrito por una persona lo disparó un /loop, un cron o un aviso
            "automatica": s.get("automatica", False) or not any(ini <= h <= fin for h in s.get("humanos", [])),
            "inicio": ini,
            "fin": max(fin, ini + 60_000),
            "titulo": s["titulo"],
            "primer_mensaje": s["primer_mensaje"] if i == 0 else None,
            "modelos": dict(modelos),
            "tokens": tok,
            "costo": round(c, 4),
            "repos": dict(repos),
            "entidades": dict(entidades),
            "cwd_repo": cwd,
            "subagentes": [{k: v for k, v in x.items() if k != "_repos"} for x in subs],
            "commits": [],
        })
    return salida


def email_git():
    try:
        return subprocess.run(["git", "config", "--global", "user.email"], capture_output=True, text=True).stdout.strip()
    except OSError:
        return ""


def commits(repo, ini, fin, email):
    """Los commits propios en ~/Code/<repo> durante el bloque (y diez minutos después)."""
    if not repo or repo == VAULT:
        return []  # el vault hace commit solo en cada cierre: no dice nada
    d = CODE / repo
    if not (d / ".git").exists():
        return []
    cmd = ["git", "-C", str(d), "log", "--all", f"--since=@{ini // 1000}", f"--until=@{fin // 1000 + 600}",
           "--format=%x1e%h%x09%s", "--name-only"]
    if email:
        cmd.insert(5, f"--author={email}")
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    salida = []
    for trozo in out.split("\x1e")[1:]:
        lineas = [l for l in trozo.strip().split("\n") if l]
        if not lineas:
            continue
        sha, _, msg = lineas[0].partition("\t")
        salida.append({"sha": sha, "mensaje": msg[:300], "archivos": len(lineas) - 1})
    return salida


def commits_de_repos(repos, ini, fin, email):
    """Los commits de todos los repos que tocó el bloque, sin repetir sha. Port de df3ff2e: el
    prototipo los buscaba en la carpeta del nombre del proyecto ("Lempriere"), que no existe."""
    vistos, salida = set(), []
    for nombre in repos:
        for c in commits(nombre, ini, fin, email):
            if c["sha"] not in vistos:
                vistos.add(c["sha"])
                salida.append(c)
    return salida


# ── Estado y envío ─────────────────────────────────────────────────────────────────────────────

def leer_json(p, defecto):
    try:
        return json.loads(p.read_text())
    except (OSError, ValueError):
        return defecto


def escribir_json(p, datos):
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(datos))
    os.replace(str(tmp), str(p))


def firma(f):
    st = f.stat()
    sub = f.with_suffix("") / "subagents"
    sub_mtime = max((x.stat().st_mtime for x in sub.rglob("*")), default=0) if sub.is_dir() else 0
    return f"{st.st_mtime}:{st.st_size}:{sub_mtime}"


def leer_plan(plan, desde_ts):
    if not plan or not plan.exists():
        return []
    muestras = []
    for l in plan.read_text(errors="replace").splitlines():
        try:
            m = json.loads(l)
        except ValueError:
            continue
        if isinstance(m, dict) and isinstance(m.get("ts"), int) and isinstance(m.get("rate_limits"), dict) and m["ts"] > desde_ts:
            muestras.append({"ts": m["ts"], "rate_limits": m["rate_limits"]})
    return muestras


def recolectar(proyectos, estado, enviar, plan=None, email=None):
    """Sube lo que cambió desde la última corrida. Devuelve cuántos bloques y muestras subió.

    Un archivo se marca como subido sólo cuando todos sus bloques llegaron: si el envío se corta a
    mitad de camino, lo que falta se reintenta en la próxima corrida (el upsert del servidor hace
    que reenviar no duplique)."""
    estado.mkdir(parents=True, exist_ok=True)
    cache_p = estado / "cache.json"
    ultimo_p = estado / "ultimo-envio.json"
    cache = leer_json(cache_p, {})
    ultimo = leer_json(ultimo_p, {})
    email = email_git() if email is None else email

    pendientes = []  # (archivo, firma, bloques)
    for f in sorted(proyectos.glob("*/*.jsonl")):
        try:
            fi = firma(f)
            if cache.get(str(f)) == fi:
                continue
            bs = bloques(parsear_sesion(f))
        except OSError:
            continue  # Claude Code lo borró o lo está rotando: va en la próxima
        for b in bs:
            b["commits"] = commits_de_repos(b["repos"], b["inicio"], b["fin"], email)
        pendientes.append((str(f), fi, bs))

    # El mismo bloque_id dos veces (dos carpetas de proyecto con el mismo id de sesión) viaja una
    # sola vez: el último gana, igual que en el servidor.
    por_id = {}
    for _, _, bs in pendientes:
        for b in bs:
            por_id[b["bloque_id"]] = b
    todos = list(por_id.values())
    aceptados = set()  # bloque_id que el servidor confirmó
    rechazados, motivo = 0, None
    log_p = estado / "rechazos.log"
    try:
        for i in range(0, len(todos), LOTE):
            lote = todos[i:i + LOTE]
            ids = [b["bloque_id"] for b in lote]
            try:
                resp = enviar("/api/semana/bloques", {"bloques": lote})
            except Rechazo as e:
                # El cuerpo entero no le sirvió: no se marca ninguno y queda anotado.
                rechazados += len(lote)
                motivo = str(e)
                continue
            # El server valida bloque por bloque: se marcan sólo los que confirmó. Lo rechazado se
            # reintenta en la próxima corrida (un plugin o un server actualizado lo puede hacer entrar).
            rech = (resp or {}).get("rechazados") or [] if isinstance(resp, dict) else []
            malos = {x.get("bloque_id") for x in rech if isinstance(x, dict)}
            aceptados.update(b for b in ids if b not in malos)
            if rech:
                rechazados += len(rech)
                motivo = f"{rech[0].get('campo')}: {rech[0].get('motivo')}"
                with open(log_p, "a") as log:
                    for x in rech:
                        log.write(f"{datetime.now().isoformat(timespec='seconds')}\t{x.get('bloque_id')}\t{x.get('campo')}\t{x.get('motivo')}\n")
    finally:
        for f, fi, bs in pendientes:
            if all(b["bloque_id"] in aceptados for b in bs):
                cache[f] = fi
        escribir_json(cache_p, cache)

    muestras = leer_plan(plan, ultimo.get("plan_ts", 0))
    for i in range(0, len(muestras), LOTE):
        lote = muestras[i:i + LOTE]
        try:
            enviar("/api/semana/plan", {"muestras": lote})
        except Rechazo as e:
            rechazados += len(lote)
            motivo = str(e)
        ultimo["plan_ts"] = max(m["ts"] for m in lote)

    ahora = int(time.time() * 1000)
    rech_p = estado / "rechazos.json"
    if rechazados:
        escribir_json(rech_p, {"bloques": rechazados, "motivo": (motivo or "")[:300], "ts": ahora})
    else:
        # Una corrida entera sin errores ni rechazos: el envío está al día.
        ultimo["ok_ts"] = ahora
        if rech_p.exists():
            rech_p.unlink()
    ultimo.pop("pausa", None)  # llegó al server: si había una pausa por 401/404/403, se terminó
    ultimo.update({"ts": ahora, "bloques": len(todos), "plan": len(muestras)})
    escribir_json(ultimo_p, ultimo)
    return {"bloques": len(todos), "plan": len(muestras), "rechazados": rechazados}


# ── Pausas: un 401, 404 o 403 no se reintenta cada 10 minutos ───────────────────────────────
#
# Cada corrida relee los logs que cambiaron: con un token vencido o un server sin la ruta, eso era
# trabajo tirado cada 10 minutos (QA, 5-oct). 401 frena hasta que cambie el token; 404 (server sin
# Semana) y 403 (Semana apagada en el cerebro) frenan un día. `--ahora` prueba igual.

DIA_S = 86400


def _sha(token):
    import hashlib
    return hashlib.sha256(token.encode()).hexdigest()[:16]


def anotar_pausa(estado, codigo, token, ahora=None):
    estado.mkdir(parents=True, exist_ok=True)
    p = estado / "ultimo-envio.json"
    u = leer_json(p, {}) or {}
    u["pausa"] = {"codigo": str(codigo), "desde": ahora or time.time(), "token": _sha(token)}
    escribir_json(p, u)


def limpiar_pausa(estado):
    p = estado / "ultimo-envio.json"
    u = leer_json(p, None)
    if u and u.pop("pausa", None) is not None:
        escribir_json(p, u)


def debe_correr(estado, token, ahora=None, forzar=False):
    """(True, None) si hay que correr; (False, motivo) si una pausa lo frena."""
    ahora = ahora or time.time()
    pausa = (leer_json(estado / "ultimo-envio.json", {}) or {}).get("pausa")
    if forzar or not pausa:
        return True, None
    if pausa.get("codigo") == "401":
        if pausa.get("token") == _sha(token):
            return False, "el servidor no acepta el token de esta Mac (401)"
        return True, None
    if ahora - pausa.get("desde", 0) < DIA_S:
        return False, "Semana está apagada en este cerebro (403)" if pausa.get("codigo") == "403" else "el servidor no tiene la ruta de Semana (404)"
    return True, None


# ── Que el agente sepa si Semana dejó de andar ────────────────────────────────────────────────

ARREGLO = "onebrain-semana-push --ahora"


def _hace(ms, ahora):
    h = (ahora * 1000 - ms) / 3_600_000
    return f"{int(h)} h" if h < 48 else f"{int(h // 24)} días"


def sesiones_sin_subir(proyectos, ok_ts, ahora):
    """¿Hay sesiones que la Mac tocó después del último envío y que ya debían haber subido? No
    cuentan la cola de los 15 minutos después del envío (el tope de 10 minutos deja el último turno
    de un día para la corrida siguiente) ni lo de los últimos 10 (la sesión que se está abriendo)."""
    desde = ok_ts / 1000 + 15 * 60
    hasta = ahora - 10 * 60
    for f in proyectos.glob("*/*.jsonl"):
        try:
            m = f.stat().st_mtime
        except OSError:
            continue
        if desde < m < hasta:
            return True
    return False


def aviso(proyectos, estado, ahora=None):
    """UNA línea si algo está mal (para el arranque de sesión), o None si está todo bien. Si nunca
    corrió no dice nada: puede ser una Mac sin python3 o recién instalada."""
    ahora = ahora or time.time()
    ultimo = leer_json(estado / "ultimo-envio.json", None)
    if not ultimo:
        return None
    pausa = ultimo.get("pausa") or {}
    if pausa.get("codigo") == "401":
        return "Semana no puede subir tus sesiones: el servidor no acepta el token de esta Mac. Reconectá con `/one-brain:connect <token>`."
    if pausa.get("codigo") == "404":
        return f"Semana no puede subir tus sesiones: el servidor todavía no tiene Semana. Se reintenta mañana; para probar ya, `{ARREGLO}`."
    if pausa.get("codigo") == "403":
        return None  # apagada en el cerebro a propósito: no es un error de esta Mac
    rech = leer_json(estado / "rechazos.json", None)
    if rech and rech.get("bloques"):
        return (f"Semana: el servidor rechazó {rech['bloques']} bloques ({rech.get('motivo') or 'sin motivo'}). "
                f"Corré `{ARREGLO}`; si vuelve a pasar, actualizá el plugin.")
    ok = ultimo.get("ok_ts")
    if ok and ahora * 1000 - ok > 24 * 3_600_000 and sesiones_sin_subir(proyectos, ok, ahora):
        return f"Semana no sube tus sesiones de Claude Code desde hace {_hace(ok, ahora)}. Corré `{ARREGLO}` para ver qué pasa."
    return None


def estado_doctor(proyectos, estado, ahora=None):
    """La línea del doctor: `semana|ok|...`, `semana|aviso|...`."""
    ahora = ahora or time.time()
    ultimo = leer_json(estado / "ultimo-envio.json", None)
    if ultimo and (ultimo.get("pausa") or {}).get("codigo") == "403":
        return "semana|ok|Semana está apagada en este cerebro; la prende el operador de One Brain"
    if not ultimo or not ultimo.get("ok_ts"):
        if leer_json(estado / "rechazos.json", None):
            return f"semana|aviso|el servidor rechazó lo que subió esta Mac; corré `{ARREGLO}`"
        return f"semana|aviso|esta Mac todavía no subió sesiones a Semana; corré `{ARREGLO}`"
    if (ultimo.get("pausa") or {}).get("codigo") == "403":
        return "semana|ok|Semana está apagada en este cerebro; la prende el operador de One Brain"
    linea = aviso(proyectos, estado, ahora)
    if linea:
        return "semana|aviso|" + linea.replace("|", "/")
    return f"semana|ok|último envío hace {_hace(ultimo['ok_ts'], ahora)}"


def preguntar_llave(enviar):
    """Un POST con la lista vacía: el server valida token y llave antes que nada. Levanta
    ErrorEnvio (401, 403 o 404) si no hay que seguir; con 200 no guarda nada."""
    enviar("/api/semana/bloques", {"bloques": []})


def enviar_con_curl(url, token, estado):
    """El POST va por curl, como el resto del plugin (capture-lib.sh): el Python de macOS no
    siempre tiene los certificados que urllib necesita. El token viaja por stdin (--config -), no
    por los argumentos, para que no aparezca en `ps`."""
    if not re.match(r"^[A-Za-z0-9_.\-]+$", token):
        raise ErrorEnvio("token con forma inesperada")
    config = f'header = "Authorization: Bearer {token}"\nheader = "content-type: application/json"\n'

    def enviar(ruta, cuerpo):
        fd, tmp = tempfile.mkstemp(dir=str(estado), suffix=".json")
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(cuerpo, f)
            r = subprocess.run(
                ["curl", "-s", "--max-time", "60", "-w", "%{http_code}", "-X", "POST",
                 "--config", "-", "--data-binary", f"@{tmp}", url.rstrip("/") + ruta],
                input=config, capture_output=True, text=True)
        finally:
            os.unlink(tmp)
        salida = r.stdout
        codigo = salida[-3:] if len(salida) >= 3 else "000"
        cuerpo = salida[:-3]
        if codigo == "200":
            try:
                return json.loads(cuerpo)
            except ValueError:
                return {}
        if codigo in ("400", "413", "422"):
            # El cuerpo entero no le sirvió. El motivo sale de su respuesta (campo y regla).
            try:
                m = json.loads(cuerpo).get("error")
            except ValueError:
                m = None
            raise Rechazo(m or f"HTTP {codigo}")
        if codigo == "000":
            raise ErrorEnvio(f"{ruta}: sin respuesta del servidor", codigo)
        raise ErrorEnvio(f"{ruta}: HTTP {codigo}", codigo)

    return enviar


def main(args):
    claude = Path(os.environ.get("CLAUDE_CONFIG_DIR") or HOME / ".claude")
    estado = Path(os.environ.get("ONE_BRAIN_SEMANA_DIR") or HOME / ".onebrain" / "semana")
    plan = Path(os.environ.get("ONE_BRAIN_SEMANA_PLAN") or HOME / ".semana" / "plan.jsonl")
    if "--aviso" in args:
        # Para el arranque de sesión: una línea sólo si algo está mal; si no, nada.
        linea = aviso(claude / "projects", estado)
        if linea:
            print(linea)
        return 0
    if "--estado" in args:
        print(estado_doctor(claude / "projects", estado))
        return 0
    url = os.environ.get("ONE_BRAIN_URL") or "https://onebrain.prophet.lat"
    token_p = os.environ.get("ONE_BRAIN_TOKEN_FILE")
    token = Path(token_p).read_text().strip() if token_p and Path(token_p).is_file() else ""
    if not token:
        return 0  # sin conectar todavía: nada que subir, y no es un error
    estado.mkdir(parents=True, exist_ok=True)
    seguir, por_que = debe_correr(estado, token, forzar="--ahora" in args)
    if not seguir:
        if "--ahora" in args:
            print(f"semana: en pausa, {por_que}")
        return 0
    # Una corrida a la vez: dos cierres seguidos no pueden pisarse el cache.
    with open(estado / "lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            print("semana: ya hay una corrida en curso; probá en un minuto")
            return 0
        try:
            enviar = enviar_con_curl(url, token, estado)
            # Antes de leer los logs (unos 13 s de CPU en una Mac con historia), un lote vacío:
            # si Semana está apagada en el cerebro el server contesta 403 y no se lee nada.
            preguntar_llave(enviar)
            res = recolectar(claude / "projects", estado, enviar, plan=plan)
        except ErrorEnvio as e:
            if e.codigo in ("401", "403", "404"):
                anotar_pausa(estado, e.codigo, token)
            raise
    linea = f"semana: subí {res['bloques']} bloques y {res['plan']} muestras del plan"
    if res["rechazados"]:
        motivo = (leer_json(estado / "rechazos.json", {}) or {}).get("motivo") or "sin motivo"
        linea += f"; el servidor rechazó {res['rechazados']} ({motivo}), se reintentan en la próxima corrida"
    print(linea)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except ErrorEnvio as e:
        claro = {
            "401": "el servidor no acepta el token de esta Mac; reconectá con /one-brain:connect <token>",
            "403": "Semana está apagada en este cerebro; la prende el operador de One Brain",
            "404": "el servidor todavía no tiene Semana; se reintenta mañana",
        }.get(e.codigo)
        print(f"semana: {claro}" if claro else f"semana: no se pudo subir ({e}); se reintenta en la próxima corrida", file=sys.stderr)
        sys.exit(1)
