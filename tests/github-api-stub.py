#!/usr/bin/env python3
"""The two GitHub release endpoints the `finish` steps call, served from a directory.

A lookup of releases/tags/<tag> answers 200 when <state>/releases/<tag> exists,
and 404 otherwise. <state>/lookup-status, when present, overrides every lookup's
status. A POST to releases appends its body to <state>/created. Every request
appends "METHOD PATH AUTHORIZATION" to <state>/requests. The port it bound is
written to <state>/port once it is listening.
"""

import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

STATE = Path(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def record(self):
        with (STATE / "requests").open("a") as f:
            f.write(f"{self.command} {self.path} {self.headers.get('Authorization')}\n")

    def answer(self, status, body=b"{}"):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.record()
        _, _, tag = self.path.partition("/releases/tags/")
        if not tag:
            self.answer(404)
        elif (STATE / "lookup-status").exists():
            self.answer(int((STATE / "lookup-status").read_text()))
        elif (STATE / "releases" / tag).exists():
            self.answer(200)
        else:
            self.answer(404)

    def do_POST(self):
        self.record()
        body = self.rfile.read(int(self.headers["Content-Length"]))
        with (STATE / "created").open("ab") as f:
            f.write(body + b"\n")
        self.answer(201, b'{"id": 1}')

    def log_message(self, format, *args):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
(STATE / "port.tmp").write_text(str(server.server_port))
(STATE / "port.tmp").rename(STATE / "port")
server.serve_forever()
