"""Tests del recolector de Semana. Corren con el Python que trae macOS (3.9):

    /usr/bin/python3 -m pytest plugin/semana        (con pytest instalado en ese intérprete)

Los casos salen del prototipo aprobado (~/Code/semana/tests): cada uno fue un bug real. Los que
allá resolvían el proyecto (tabla, sueltos, herencia por sesión, horas en paralelo) se mudaron al
servidor (tests/semana-proyecto.test.ts); acá se prueba que las SEÑALES crudas salgan bien.
"""
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import recolectar as r  # noqa: E402

HOME = "/Users/bautistafilippini"
T0 = 1_790_000_000_000  # epoch ms
CONTRATO = {"bloque_id", "sesion", "inicio", "fin", "automatica", "titulo", "primer_mensaje", "modelos",
            "tokens", "costo", "repos", "entidades", "cwd_repo", "subagentes", "commits"}


def iso(ms):
    from datetime import datetime, timezone
    return datetime.fromtimestamp(ms / 1000, timezone.utc).isoformat().replace("+00:00", "Z")


def asistente(ms, msg_id, model="claude-opus-5-5", usage=None, tool_input=None, cwd=f"{HOME}/Code/bats-second-brain"):
    content = [{"type": "text", "text": "ok"}]
    if tool_input is not None:
        content.append({"type": "tool_use", "name": "Edit", "input": tool_input})
    return {
        "type": "assistant", "timestamp": iso(ms), "cwd": cwd, "sessionId": "s1",
        "message": {"id": msg_id, "model": model, "content": content,
                    "usage": usage or {"input_tokens": 10, "output_tokens": 100,
                                       "cache_read_input_tokens": 1000,
                                       "cache_creation_input_tokens": 0}},
    }


def usuario(ms, texto, cwd=f"{HOME}/Code/bats-second-brain"):
    return {"type": "user", "timestamp": iso(ms), "cwd": cwd, "sessionId": "s1",
            "message": {"role": "user", "content": texto}}


def guardado(ms, msg_id, entidades):
    a = asistente(ms, msg_id)
    a["message"]["content"].append({"type": "tool_use", "name": "mcp__plugin_one-brain_one-brain__brain_save",
                                    "input": {"title": "x", "entities": entidades}})
    return a


def escribir(tmp_path, lineas, nombre="s1.jsonl"):
    p = tmp_path / nombre
    p.write_text("\n".join(json.dumps(l) for l in lineas))
    return p


def bloques_de(p):
    return r.bloques(r.parsear_sesion(p))


# ── Parseo (del prototipo) ─────────────────────────────────────────────────────────────────────

def test_respuesta_repetida_por_bloque_se_cuenta_una_vez(tmp_path):
    a = asistente(T0 + 1000, "msg_1")
    b = bloques_de(escribir(tmp_path, [usuario(T0, "arreglá el login"), a, a, a]))[0]
    assert b["tokens"]["output"] == 100
    assert b["tokens"]["cache_read"] == 1000


def test_pausa_de_mas_de_30_min_parte_la_sesion_en_dos_bloques(tmp_path):
    p = escribir(tmp_path, [
        usuario(T0, "hola"), asistente(T0 + 60_000, "m1"),
        usuario(T0 + 45 * 60_000, "sigo"), asistente(T0 + 46 * 60_000, "m2"),
    ])
    bs = bloques_de(p)
    assert [b["bloque_id"] for b in bs] == ["s1#0", "s1#1"]
    assert bs[0]["fin"] == T0 + 60_000
    assert bs[1]["inicio"] == T0 + 45 * 60_000


def test_los_repos_que_toco_viajan_como_senal_y_el_vault_no(tmp_path):
    p = escribir(tmp_path, [
        usuario(T0, "fix pem"),
        asistente(T0 + 1000, "m1", tool_input={"file_path": f"{HOME}/Code/plata-en-mano-dashboard/src/a.ts"}),
        asistente(T0 + 2000, "m2", tool_input={"file_path": f"{HOME}/Code/plata-en-mano-dashboard/src/b.ts"}),
        asistente(T0 + 3000, "m3", tool_input={"file_path": f"{HOME}/Code/bats-second-brain/brain/hot.md"}),
    ])
    b = bloques_de(p)[0]
    assert b["repos"] == {"plata-en-mano-dashboard": 2}
    assert b["cwd_repo"] is None  # se abrió en el vault


def test_worktrees_cuentan_como_el_repo_base(tmp_path):
    assert r.normalizar_repo("one-brain-worktrees") == "one-brain"
    assert r.normalizar_repo("bats-second-brain") == "vault"
    assert r.normalizar_repo("bats-second-brain.") == "vault"
    base = tmp_path / "edu-pioli-dashboard"
    base.mkdir()
    subprocess.run(["git", "init", "-q", str(base)], check=True)
    subprocess.run(["git", "-C", str(base), "-c", "user.email=a@b", "-c", "user.name=a", "commit", "-q", "--allow-empty", "-m", "x"], check=True)
    subprocess.run(["git", "-C", str(base), "worktree", "add", "-q", str(tmp_path / "edu-wt-int")], check=True)
    assert r.resolver_repo("edu-wt-int", "src", code=tmp_path) == "edu-pioli-dashboard"


def test_sesion_de_claude_p_queda_marcada_como_automatica(tmp_path):
    a = asistente(T0 + 1000, "m1")
    a["entrypoint"] = "sdk-cli"
    assert bloques_de(escribir(tmp_path, [usuario(T0, "actualizá el plantel"), a]))[0]["automatica"] is True


def test_sesion_sin_ninguna_senal_viaja_vacia(tmp_path):
    b = bloques_de(escribir(tmp_path, [usuario(T0, "pensemos algo"), asistente(T0 + 1000, "m1")]))[0]
    assert (b["repos"], b["entidades"], b["cwd_repo"]) == ({}, {}, None)


def test_entidades_nombradas_en_one_brain_se_cuentan(tmp_path):
    p = escribir(tmp_path, [usuario(T0, "armá la campaña"), guardado(T0 + 1000, "m1", ["Bauti", "VETTA Motors", "Meta Ads"]),
                            guardado(T0 + 2000, "m2", ["VETTA Motors"])])
    assert bloques_de(p)[0]["entidades"] == {"Bauti": 1, "VETTA Motors": 2, "Meta Ads": 1}


def test_primer_mensaje_solo_en_el_primer_tramo(tmp_path):
    p = escribir(tmp_path, [
        usuario(T0, "seguí con vetta"), asistente(T0 + 1000, "m1"),
        usuario(T0 + 60 * 60_000, "y ahora?"), asistente(T0 + 61 * 60_000, "m2"),
    ])
    assert [b["primer_mensaje"] for b in bloques_de(p)] == ["seguí con vetta", None]


def test_repo_y_entidad_viajan_los_dos_y_decide_el_servidor(tmp_path):
    a = guardado(T0 + 1000, "m1", ["VETTA Motors"])
    a["message"]["content"].append({"type": "tool_use", "name": "Edit", "input": {"file_path": f"{HOME}/Code/lempriere-app/a.ts"}})
    b = bloques_de(escribir(tmp_path, [usuario(T0, "x"), a]))[0]
    assert b["repos"] == {"lempriere-app": 1}
    assert b["entidades"] == {"VETTA Motors": 1}


def test_repos_que_toca_un_subagente_cuentan(tmp_path):
    p = escribir(tmp_path, [usuario(T0, "x"), asistente(T0 + 1000, "m1")])
    sub = tmp_path / "s1" / "subagents"
    sub.mkdir(parents=True)
    (sub / "agent-a1.jsonl").write_text(json.dumps(asistente(T0 + 2000, "sm1", tool_input={"file_path": f"{HOME}/Code/edu-pioli-dashboard/x.ts"})))
    assert bloques_de(p)[0]["repos"] == {"edu-pioli-dashboard": 1}


def test_costo_opus_5_5_con_precios_oficiales():
    tok = {"input": 1_000_000, "output": 1_000_000, "cache_read": 1_000_000,
           "cache_write_5m": 1_000_000, "cache_write_1h": 1_000_000}
    # 4 + 20 + 0.20 + 4*1.25 + 4*2
    assert r.costo("claude-opus-5-5[1m]", tok) == 4 + 20 + 0.20 + 5 + 8


def test_modelo_desconocido_no_inventa_precio():
    assert r.costo("<synthetic>", {"input": 10, "output": 10}) == 0


def test_primer_mensaje_ignora_comandos_y_resultados(tmp_path):
    p = escribir(tmp_path, [
        usuario(T0, "<command-name>/clear</command-name>"),
        {"type": "user", "timestamp": iso(T0 + 1), "message": {"content": [{"type": "tool_result", "content": "x"}]}},
        usuario(T0 + 2, "che me encantó esto"),
        asistente(T0 + 3, "m1"),
    ])
    assert r.parsear_sesion(p)["primer_mensaje"] == "che me encantó esto"


def test_titulo_custom_le_gana_al_de_ia(tmp_path):
    p = escribir(tmp_path, [
        usuario(T0, "x"), asistente(T0 + 1, "m1"),
        {"type": "ai-title", "aiTitle": "Título IA"},
        {"type": "custom-title", "customTitle": "Mi título"},
    ])
    assert r.parsear_sesion(p)["titulo"] == "Mi título"


def test_el_bloque_cumple_el_contrato(tmp_path):
    p = escribir(tmp_path, [usuario(T0, "x" * 900), asistente(T0 + 1000, "m1")])
    sub = tmp_path / "s1" / "subagents"
    sub.mkdir(parents=True)
    (sub / "agent-a1.jsonl").write_text(json.dumps(asistente(T0 + 2000, "sm1")))
    b = bloques_de(p)[0]
    assert set(b) == CONTRATO
    assert set(b["subagentes"][0]) == {"tipo", "descripcion", "inicio", "fin", "modelos", "tokens", "costo"}
    assert len(b["primer_mensaje"]) == 400
    assert b["fin"] >= b["inicio"] + 60_000  # un tramo de un instante se ve igual en el calendario
    json.dumps(b)  # serializable tal cual


def test_subagentes_suman_a_su_sesion(tmp_path):
    p = escribir(tmp_path, [usuario(T0, "x"), asistente(T0 + 1000, "m1")])
    sub = tmp_path / "s1" / "subagents"
    sub.mkdir(parents=True)
    (sub / "agent-a1.meta.json").write_text(json.dumps({"agentType": "buscador", "description": "buscar X"}))
    (sub / "agent-a1.jsonl").write_text(json.dumps(asistente(T0 + 2000, "sm1", model="claude-sonnet-5-5")))
    s = r.parsear_sesion(p)
    assert len(s["subagentes"]) == 1
    assert s["subagentes"][0]["tipo"] == "buscador"
    assert s["subagentes"][0]["descripcion"] == "buscar X"
    assert s["subagentes"][0]["modelos"] == {"claude-sonnet-5-5": 1}
    b = r.bloques(s)[0]
    assert b["costo"] > r.costo("claude-opus-5-5", s["mensajes"][0]["tokens"])


def test_agentes_de_workflow_tambien_cuentan(tmp_path):
    p = escribir(tmp_path, [usuario(T0, "x"), asistente(T0 + 1000, "m1")])
    wf = tmp_path / "s1" / "subagents" / "workflows" / "wf_1"
    wf.mkdir(parents=True)
    (wf / "agent-w1.jsonl").write_text(json.dumps(asistente(T0 + 2000, "wm1")))
    assert [x["tipo"] for x in r.parsear_sesion(p)["subagentes"]] == ["workflow"]


def test_tramo_sin_mensaje_humano_es_automatico(tmp_path):
    aviso = usuario(T0 + 60 * 60_000, "<task-notification>listo</task-notification>")
    p = escribir(tmp_path, [
        usuario(T0, "arreglá esto"), asistente(T0 + 1000, "m1"),
        aviso, asistente(T0 + 61 * 60_000, "m2"),
    ])
    a, b = bloques_de(p)
    assert a["automatica"] is False
    assert b["automatica"] is True


def test_mensaje_de_otro_origen_no_cuenta_como_humano(tmp_path):
    m = usuario(T0, "revisá el deploy")
    m["origin"] = {"kind": "peer"}
    assert bloques_de(escribir(tmp_path, [m, asistente(T0 + 1000, "m1")]))[0]["automatica"] is True


def test_cwd_en_un_worktree_va_al_repo_base(tmp_path, monkeypatch):
    base = tmp_path / "one-brain"
    base.mkdir()
    subprocess.run(["git", "init", "-q", str(base)], check=True)
    subprocess.run(["git", "-C", str(base), "-c", "user.email=a@b", "-c", "user.name=a", "commit", "-q", "--allow-empty", "-m", "x"], check=True)
    (tmp_path / "one-brain-worktrees").mkdir()
    subprocess.run(["git", "-C", str(base), "worktree", "add", "-q", str(tmp_path / "one-brain-worktrees" / "semana")], check=True)
    monkeypatch.setattr(r, "CODE", tmp_path)
    cwd = f"{tmp_path}/one-brain-worktrees/semana"
    assert r.repo_de_cwd(cwd.replace(str(tmp_path), f"{HOME}/Code")) == "one-brain"


def test_commits_del_repo_que_toco(tmp_path, monkeypatch):
    repo = tmp_path / "lempriere-app"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    (repo / "a.ts").write_text("x")
    subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
    subprocess.run(["git", "-C", str(repo), "-c", "user.email=yo@x", "-c", "user.name=yo", "commit", "-q", "-m", "fix: login"], check=True)
    monkeypatch.setattr(r, "CODE", tmp_path)
    import time
    ahora = int(time.time() * 1000)
    cs = r.commits("lempriere-app", ahora - 60_000, ahora, "yo@x")
    assert [(c["mensaje"], c["archivos"]) for c in cs] == [("fix: login", 1)]
    assert r.commits("lempriere-app", ahora - 60_000, ahora, "otro@x") == []
    assert r.commits("vault", ahora - 60_000, ahora, "yo@x") == []


def test_commits_se_buscan_en_los_repos_tocados_sin_repetir_sha(tmp_path, monkeypatch):
    # Bug del prototipo (df3ff2e): se buscaban en la carpeta del NOMBRE del proyecto ("Lempriere"),
    # que no existe, y daba 0 commits. Ahora en cada repo crudo del bloque, sin repetir sha.
    import time
    for nombre in ("lempriere-app", "lempriere-data"):
        repo = tmp_path / nombre
        repo.mkdir()
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        subprocess.run(["git", "-C", str(repo), "-c", "user.email=a@b", "-c", "user.name=a", "commit", "-q", "--allow-empty", "-m", f"arreglo {nombre}"], check=True)
    monkeypatch.setattr(r, "CODE", tmp_path)
    ahora = int(time.time() * 1000)
    cs = r.commits_de_repos({"lempriere-app": 3, "lempriere-data": 1, "vault": 9}, ahora - 3_600_000, ahora, "a@b")
    assert sorted(c["mensaje"] for c in cs) == ["arreglo lempriere-app", "arreglo lempriere-data"]
    assert r.commits_de_repos({}, ahora - 3_600_000, ahora, "a@b") == []
    # Dos nombres para el mismo repo (un symlink en ~/Code) no duplican el commit.
    (tmp_path / "otro-nombre").symlink_to(tmp_path / "lempriere-app")
    duplicado = r.commits_de_repos({"lempriere-app": 1, "otro-nombre": 1}, ahora - 3_600_000, ahora, "a@b")
    assert [c["mensaje"] for c in duplicado] == ["arreglo lempriere-app"]


# ── Envío incremental (nuevo: el prototipo escribía un HTML; esto sube al servidor) ────────────

def armar_home(tmp_path):
    proyectos = tmp_path / "claude" / "projects" / "-Users-x-Code-algo"
    proyectos.mkdir(parents=True)
    estado = tmp_path / "estado"
    escribir(proyectos, [usuario(T0, "hola"), asistente(T0 + 1000, "m1")], "s1.jsonl")
    escribir(proyectos, [usuario(T0, "otra"), asistente(T0 + 1000, "m1")], "s2.jsonl")
    return proyectos, estado


def correr(proyectos, estado, enviados, falla=False, plan=None):
    def enviar(ruta, cuerpo):
        if falla:
            raise r.ErrorEnvio("caído")
        enviados.append((ruta, cuerpo))
    return r.recolectar(proyectos=proyectos.parent, estado=estado, enviar=enviar, plan=plan, email="")


def test_la_segunda_corrida_no_reenvia_lo_que_no_cambio(tmp_path):
    proyectos, estado = armar_home(tmp_path)
    enviados = []
    assert correr(proyectos, estado, enviados)["bloques"] == 2
    assert [e[0] for e in enviados] == ["/api/semana/bloques"]
    enviados.clear()
    assert correr(proyectos, estado, enviados)["bloques"] == 0
    assert enviados == []
    with open(proyectos / "s1.jsonl", "a") as f:
        f.write("\n" + json.dumps(usuario(T0 + 5000, "sigo")))
    assert correr(proyectos, estado, enviados)["bloques"] == 1
    assert [b["sesion"] for b in enviados[0][1]["bloques"]] == ["s1"]


def test_si_el_envio_falla_se_reintenta_la_proxima(tmp_path):
    proyectos, estado = armar_home(tmp_path)
    enviados = []
    try:
        correr(proyectos, estado, enviados, falla=True)
        assert False, "tenía que fallar"
    except r.ErrorEnvio:
        pass
    assert correr(proyectos, estado, enviados)["bloques"] == 2


def test_manda_en_lotes_de_200(tmp_path, monkeypatch):
    assert r.LOTE == 200  # el server acepta hasta 500; 200 deja margen de tamaño de body
    proyectos, estado = armar_home(tmp_path)
    monkeypatch.setattr(r, "LOTE", 1)
    enviados = []
    correr(proyectos, estado, enviados)
    assert [len(c["bloques"]) for _, c in enviados] == [1, 1]


def test_el_plan_sube_solo_las_muestras_nuevas(tmp_path):
    proyectos, estado = armar_home(tmp_path)
    plan = tmp_path / "plan.jsonl"
    plan.write_text('{"ts": 10, "rate_limits": {"a": 1}}\nbasura\n{"ts": 20, "rate_limits": {"a": 2}}\n')
    enviados = []
    correr(proyectos, estado, enviados, plan=plan)
    muestras = [c for ruta, c in enviados if ruta == "/api/semana/plan"]
    assert [m["ts"] for m in muestras[0]["muestras"]] == [10, 20]
    enviados.clear()
    with open(plan, "a") as f:
        f.write('{"ts": 30, "rate_limits": {"a": 3}}\n')
    correr(proyectos, estado, enviados, plan=plan)
    assert [[m["ts"] for m in c["muestras"]] for ruta, c in enviados if ruta == "/api/semana/plan"] == [[30]]


# ── Estado local: que el agente sepa si Semana dejó de andar (pieza 3) ─────────────────────────

def test_un_lote_rechazado_no_se_marca_y_queda_anotado_con_el_motivo(tmp_path):
    proyectos, estado = armar_home(tmp_path)
    enviados = []

    def enviar(ruta, cuerpo):
        if any(b["sesion"] == "s1" for b in cuerpo.get("bloques", [])):
            raise r.Rechazo("bloques.0.inicio: se esperaba un número")
        enviados.append(cuerpo)

    import pytest
    r.LOTE, lote_antes = 1, r.LOTE
    try:
        res = r.recolectar(proyectos=proyectos.parent, estado=estado, enviar=enviar, email="")
    finally:
        r.LOTE = lote_antes
    assert res["rechazados"] == 1 and res["bloques"] == 2
    rech = json.loads((estado / "rechazos.json").read_text())
    assert rech["bloques"] == 1 and "inicio" in rech["motivo"]
    assert "ok_ts" not in json.loads((estado / "ultimo-envio.json").read_text())
    # La próxima corrida reintenta sólo lo rechazado; si entra, el rechazo queda resuelto.
    enviados.clear()
    res = r.recolectar(proyectos=proyectos.parent, estado=estado, enviar=lambda ruta, c: enviados.append(c), email="")
    assert res == {"bloques": 1, "plan": 0, "rechazados": 0}
    assert not (estado / "rechazos.json").exists()
    assert json.loads((estado / "ultimo-envio.json").read_text())["ok_ts"] > 0


def test_aviso_calla_si_esta_todo_bien_o_si_nunca_corrio(tmp_path):
    proyectos, estado = armar_home(tmp_path)
    assert r.aviso(proyectos.parent, estado) is None  # nunca corrió: no hay nada que decir
    r.recolectar(proyectos=proyectos.parent, estado=estado, enviar=lambda *a: None, email="")
    assert r.aviso(proyectos.parent, estado) is None


def test_aviso_si_hace_mas_de_24h_que_no_sube_y_hubo_sesiones_despues(tmp_path):
    import os
    proyectos, estado = armar_home(tmp_path)
    r.recolectar(proyectos=proyectos.parent, estado=estado, enviar=lambda *a: None, email="")
    ahora = time_now = __import__("time").time()
    ok = ahora - 3 * 86400
    u = json.loads((estado / "ultimo-envio.json").read_text())
    u["ok_ts"] = int(ok * 1000)
    (estado / "ultimo-envio.json").write_text(json.dumps(u))
    # Una sesión del fin de semana tocada justo después del último envío (cola del throttle): no avisa.
    os.utime(proyectos / "s1.jsonl", (ok + 300, ok + 300))
    os.utime(proyectos / "s2.jsonl", (ok + 300, ok + 300))
    assert r.aviso(proyectos.parent, estado, ahora=ahora) is None
    # La sesión que se está abriendo ahora tampoco cuenta.
    os.utime(proyectos / "s2.jsonl", (ahora - 60, ahora - 60))
    assert r.aviso(proyectos.parent, estado, ahora=ahora) is None
    # Una sesión de ayer que no subió: avisa, con el comando que lo arregla.
    os.utime(proyectos / "s1.jsonl", (ahora - 86400, ahora - 86400))
    linea = r.aviso(proyectos.parent, estado, ahora=ahora)
    assert "onebrain-semana-push --ahora" in linea and "\n" not in linea


def test_aviso_y_estado_con_rechazos(tmp_path):
    proyectos, estado = armar_home(tmp_path)
    r.recolectar(proyectos=proyectos.parent, estado=estado, enviar=lambda *a: None, email="")
    (estado / "rechazos.json").write_text(json.dumps({"bloques": 3, "motivo": "bloques.0.fin: fin anterior a inicio", "ts": 1}))
    linea = r.aviso(proyectos.parent, estado)
    assert "3 bloques" in linea and "onebrain-semana-push --ahora" in linea
    clave, nivel, detalle = r.estado_doctor(proyectos.parent, estado).split("|", 2)
    assert (clave, nivel) == ("semana", "aviso") and "rechaz" in detalle


def test_estado_doctor_ok_y_nunca(tmp_path):
    proyectos, estado = armar_home(tmp_path)
    assert r.estado_doctor(proyectos.parent, estado).startswith("semana|aviso|")  # nunca subió
    r.recolectar(proyectos=proyectos.parent, estado=estado, enviar=lambda *a: None, email="")
    assert r.estado_doctor(proyectos.parent, estado).startswith("semana|ok|")


# ── QA 5-oct ──────────────────────────────────────────────────────────────────────────────────

def test_solo_se_marcan_los_bloques_que_el_server_confirmo(tmp_path):
    proyectos, estado = armar_home(tmp_path)

    def enviar(ruta, cuerpo):
        ids = [b["bloque_id"] for b in cuerpo["bloques"]]
        rech = [{"bloque_id": "s1#0", "campo": "fin", "motivo": "es anterior a inicio"}] if "s1#0" in ids else []
        return {"ok": True, "guardados": len(ids) - len(rech), "rechazados": rech}

    res = r.recolectar(proyectos=proyectos.parent, estado=estado, enviar=enviar, email="")
    assert res["rechazados"] == 1
    log = (estado / "rechazos.log").read_text()
    assert "s1#0" in log and "fin" in log and "es anterior a inicio" in log
    # s2 entró: no se reenvía; s1 no: se reintenta.
    vistos = []
    r.recolectar(proyectos=proyectos.parent, estado=estado, enviar=lambda ruta, c: vistos.extend(b["bloque_id"] for b in c["bloques"]) or {}, email="")
    assert vistos == ["s1#0"]


def test_el_mismo_bloque_no_viaja_dos_veces_en_un_request(tmp_path):
    proyectos, estado = armar_home(tmp_path)
    otro = proyectos.parent / "-Users-x-Code-otro"
    otro.mkdir()
    escribir(otro, [usuario(T0, "hola"), asistente(T0 + 1000, "m1")], "s1.jsonl")  # mismo id de sesión
    vistos = []
    r.recolectar(proyectos=proyectos.parent, estado=estado, enviar=lambda ruta, c: vistos.extend(b["bloque_id"] for b in c["bloques"]) or {}, email="")
    assert sorted(vistos) == ["s1#0", "s2#0"]


def test_con_401_frena_hasta_que_cambie_el_token(tmp_path):
    estado = tmp_path / "estado"
    r.anotar_pausa(estado, "401", "ob_viejo", ahora=1000.0)
    assert r.debe_correr(estado, "ob_viejo", ahora=999999.0)[0] is False
    assert r.debe_correr(estado, "ob_nuevo", ahora=1001.0)[0] is True
    assert r.debe_correr(estado, "ob_viejo", ahora=1001.0, forzar=True)[0] is True
    # el token nunca queda escrito tal cual
    assert "ob_viejo" not in (estado / "ultimo-envio.json").read_text()


def test_con_404_o_403_frena_hasta_el_dia_siguiente(tmp_path):
    estado = tmp_path / "estado"
    r.anotar_pausa(estado, "404", "ob_x", ahora=1000.0)
    assert r.debe_correr(estado, "ob_x", ahora=1000.0 + 3600)[0] is False
    assert r.debe_correr(estado, "ob_x", ahora=1000.0 + 86401)[0] is True
    r.anotar_pausa(estado, "403", "ob_x", ahora=1000.0)
    assert r.debe_correr(estado, "ob_x", ahora=1000.0 + 3600)[0] is False


def test_el_aviso_dice_que_hacer_con_un_401_o_un_404(tmp_path):
    proyectos, estado = armar_home(tmp_path)
    r.recolectar(proyectos=proyectos.parent, estado=estado, enviar=lambda *a: None, email="")
    r.anotar_pausa(estado, "401", "ob_x")
    assert "/one-brain:connect" in r.aviso(proyectos.parent, estado)
    r.anotar_pausa(estado, "404", "ob_x")
    assert "onebrain-semana-push --ahora" in r.aviso(proyectos.parent, estado)
    r.anotar_pausa(estado, "403", "ob_x")
    assert r.aviso(proyectos.parent, estado) is None  # apagada a propósito: no es un error
    assert "apagada" in r.estado_doctor(proyectos.parent, estado)
    r.limpiar_pausa(estado)
    assert r.aviso(proyectos.parent, estado) is None


def test_sin_respuesta_del_servidor_lo_dice_asi(tmp_path):
    (tmp_path / "e").mkdir()
    enviar = r.enviar_con_curl("http://127.0.0.1:1", "ob_x", tmp_path / "e")
    try:
        enviar("/api/semana/bloques", {"bloques": []})
        assert False, "tenía que fallar"
    except r.ErrorEnvio as e:
        assert "sin respuesta del servidor" in str(e) and "000" not in str(e)


def test_con_semana_apagada_no_lee_los_logs(tmp_path, monkeypatch):
    proyectos, estado = armar_home(tmp_path)
    token = tmp_path / "token"
    token.write_text("ob_prueba")
    monkeypatch.setenv("CLAUDE_CONFIG_DIR", str(tmp_path / "claude"))
    monkeypatch.setenv("ONE_BRAIN_SEMANA_DIR", str(estado))
    monkeypatch.setenv("ONE_BRAIN_TOKEN_FILE", str(token))
    llamadas = []

    def enviar_apagada(ruta, cuerpo):
        llamadas.append(cuerpo)
        raise r.ErrorEnvio("apagada", "403")

    monkeypatch.setattr(r, "enviar_con_curl", lambda url, tok, est: enviar_apagada)
    leidos = []
    monkeypatch.setattr(r, "recolectar", lambda *a, **k: leidos.append(1) or {"bloques": 0, "muestras": 0})
    import pytest
    with pytest.raises(r.ErrorEnvio):
        r.main([])
    assert llamadas == [{"bloques": []}]
    assert leidos == []
    seguir, motivo = r.debe_correr(estado, "ob_prueba")
    assert seguir is False and "403" in motivo
