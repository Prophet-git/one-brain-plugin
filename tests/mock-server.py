#!/usr/bin/env python3
"""Server mínimo que imita las respuestas de la API para testear session-start.sh.
Uso: python3 mock-server.py [puerto]. Responde siempre lo mismo, sin importar el token.

El puerto es opcional y por default es 0 = EFÍMERO: lo elige el sistema entre los libres y
el server lo anuncia por stdout (una línea con el número) para que quien lo lanza lo lea. Con
un puerto fijo, dos corridas solapadas del test se pisaban —la segunda moría con "Address
already in use" y el hook le pegaba al mock de la otra— y el test fallaba sin que hubiera
nada roto."""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

RESPUESTAS = {
    "/api/context": {
        "brief": "## Decisiones vigentes\n- **Pasar la carga a Postgres** ([[Fran]] · 24/07/2026): porque el Excel no aguanta.",
    },
    "/api/synthesis": {"period_key": "2026-07-30"},
    "/api/resume": {"resume": "Quedaste a mitad del wizard de alta."},
    "/api/mentions": {"mentions": "Fran te mencionó en una nota de ayer."},
    "/api/features": {"features": {"team-digest": True, "menciones": True}},
    "/api/hello": {"hello": "Bienvenido a One Brain."},
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

    def log_message(self, *_):
        pass


servidor = HTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 0), Handler)
# El constructor de HTTPServer ya hizo bind() y listen(), así que para cuando esta línea sale
# el socket YA acepta conexiones: imprimir el puerto es también la señal de "estoy listo".
print(servidor.server_address[1], flush=True)
servidor.serve_forever()
