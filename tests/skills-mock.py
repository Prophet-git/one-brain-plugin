#!/usr/bin/env python3
"""Server mínimo para testear la bajada de skills del plugin.
Uso: python3 skills-mock.py [puerto]. Puerto 0 (default) = efímero, anunciado por stdout.

Archivo aparte de mock-server.py a propósito: aquel sólo responde GET y su forma está atada
al golden del arranque. Éste necesita POST y un cuerpo que NO es JSON (el contenido crudo de
un archivo de skill), así que tocarlo arrastraría el golden de session-start sin motivo.

Dos ganchos por variable de entorno, los dos opcionales:
 - OB_MOCK_ARCHIVOS: JSON {ruta: contenido} para servir una skill de varios archivos con
   contenidos distintos. Sin él, cualquier ruta devuelve "hola".
 - OB_MOCK_POSTS: archivo donde anotar cada POST a /api/skills/aplicado, una línea por cuerpo.
   Es la única forma de verificar que el plugin CONFIRMA cada skill: es un dato que va al
   server y no aparece en el disco de la máquina.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

_archivos = {}
if os.environ.get("OB_MOCK_ARCHIVOS"):
    with open(os.environ["OB_MOCK_ARCHIVOS"], encoding="utf-8") as fh:
        _archivos = json.load(fh)
_posts = os.environ.get("OB_MOCK_POSTS")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        ruta = self.path.split("?")[0]
        if ruta != "/api/skills/archivo":
            self.send_response(404)
            self.end_headers()
            return
        pedido = ""
        for par in self.path.split("?")[1].split("&") if "?" in self.path else []:
            if par.startswith("ruta="):
                pedido = par[5:]
        cuerpo = _archivos.get(pedido, "hola").encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def do_POST(self):
        largo = int(self.headers.get("Content-Length") or 0)
        crudo = self.rfile.read(largo).decode("utf-8", "replace")
        if _posts:
            with open(_posts, "a", encoding="utf-8") as fh:
                fh.write(crudo + "\n")
        cuerpo = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def log_message(self, *_):
        pass


servidor = HTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 0), Handler)
# El constructor ya hizo bind() y listen(): imprimir el puerto es también la señal de "listo".
print(servidor.server_address[1], flush=True)
servidor.serve_forever()
