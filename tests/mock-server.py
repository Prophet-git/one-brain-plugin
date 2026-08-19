#!/usr/bin/env python3
"""Server mínimo que imita las respuestas de la API para testear session-start.sh.
Uso: python3 mock-server.py [puerto]. Responde siempre lo mismo, sin importar el token.

El puerto es opcional y por default es 0 = EFÍMERO: lo elige el sistema entre los libres y
el server lo anuncia por stdout (una línea con el número) para que quien lo lanza lo lea. Con
un puerto fijo, dos corridas solapadas del test se pisaban —la segunda moría con "Address
already in use" y el hook le pegaba al mock de la otra— y el test fallaba sin que hubiera
nada roto."""
import hashlib
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

# El sha256 real de "hola", que es lo que devuelve /api/skills/archivo acá abajo. Se calcula
# en vez de escribirse a mano para que nadie tenga que preguntarse de dónde salió el hash.
SHA_HOLA = hashlib.sha256(b"hola").hexdigest()

RESPUESTAS = {
    "/api/context": {
        "brief": "## Decisiones vigentes\n- **Pasar la carga a Postgres** ([[Fran]] · 24/07/2026): porque el Excel no aguanta.",
    },
    "/api/synthesis": {"period_key": "2026-07-30"},
    "/api/resume": {"resume": "Quedaste a mitad del wizard de alta."},
    "/api/mentions": {"mentions": "Fran te mencionó en una nota de ayer."},
    "/api/features": {"features": {"team-digest": True, "menciones": True}},
    "/api/hello": {"hello": "Bienvenido a One Brain."},
    # La biblioteca de skills. El arranque de Claude Code hace POST acá y, si viene algo en
    # "instalar", lo baja y lo escribe. El de Codex NO lo llama: que este mock igual sepa
    # responder es lo que deja verificar esa diferencia en tests/codex-session-start-test.sh.
    "/api/skills/sync": {
        "instalar": [{
            "slug": "demo",
            "version": "1.0.0",
            "nombre": "Leer WhatsApp",
            "ejemplo": "fijate qué mandó Nacho",
            "archivos": [{"ruta": "SKILL.md", "sha256": SHA_HOLA}],
        }],
        "sacar": [],
    },
    "/api/skills/aplicado": {"ok": True},
}

# Dos ganchos OPCIONALES para el test del arranque de Codex, los dos apagados por default: sin
# las variables de entorno este server responde exactamente lo mismo de siempre, así que el
# golden de Claude Code no se entera de que existen.
#
#  - OB_MOCK_RESPUESTAS: archivo JSON {ruta: cuerpo} que pisa las respuestas de arriba. Sirve
#    para servir un brief HOSTIL (comillas, barras, saltos, tabs, acentos, emojis) y verificar
#    que el sobre JSON del hook de Codex sobrevive al escapeo.
#  - OB_MOCK_HEADERS: archivo donde volcar los headers de cada request. Es la única forma de
#    verificar que el header x-client sale con el valor de cada programa: es un dato que va al
#    server y no aparece en ninguna salida.
_override = os.environ.get("OB_MOCK_RESPUESTAS")
if _override:
    with open(_override, encoding="utf-8") as fh:
        RESPUESTAS.update(json.load(fh))
_headers_log = os.environ.get("OB_MOCK_HEADERS")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        ruta = self.path.split("?")[0]
        # El contenido de un archivo de skill sale como texto plano, no envuelto en JSON: es lo
        # que hace el endpoint real y lo que el plugin escribe tal cual en el disco.
        if ruta == "/api/skills/archivo":
            cuerpo = b"hola"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(cuerpo)))
            self.end_headers()
            self.wfile.write(cuerpo)
            return
        if _headers_log:
            with open(_headers_log, "a", encoding="utf-8") as fh:
                for clave, valor in self.headers.items():
                    fh.write("%s %s: %s\n" % (ruta, clave.lower(), valor))
        # separators compactos (sin espacio tras ":") A PROPÓSITO: así serializa el server real
        # (NextResponse.json → JSON.stringify), y session-start.sh depende de eso en el único
        # campo que NO parsea con ob_json_field — el saludo de primera vez sale de un
        # `sed 's/.*"hello":"\(.*\)"}/\1/p'` que con `"hello": "..."` no matchea y devuelve "".
        # Con json.dumps por default el bloque de saludo desaparecía del golden y esa línea
        # quedaba sin cubrir: el refactor podía romperla sin que ningún test se enterara.
        cuerpo = json.dumps(RESPUESTAS.get(ruta, {}), separators=(",", ":")).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def do_POST(self):
        ruta = self.path.split("?")[0]
        largo = int(self.headers.get("Content-Length") or 0)
        if largo:
            self.rfile.read(largo)
        cuerpo = json.dumps(RESPUESTAS.get(ruta, {}), separators=(",", ":")).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def log_message(self, *_):
        pass


servidor = HTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 0), Handler)
# El constructor de HTTPServer ya hizo bind() y listen(), así que para cuando esta línea sale
# el socket YA acepta conexiones: imprimir el puerto es también la señal de "estoy listo".
print(servidor.server_address[1], flush=True)
servidor.serve_forever()
