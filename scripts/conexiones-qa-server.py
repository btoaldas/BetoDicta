#!/usr/bin/env python3
"""Servidor efímero para el E2E de Conexiones API (ConexionesQA _SRV=1).

Simula un API institucional con login→token y flujo proponer→confirmar:
  POST /login            {user, pass} → {"data": {"access_token": "tok-N"}}
  GET  /saldo            (auth) → {"saldo": 42}
  POST /preview          (auth) → {"previewId": "p-N", "resumen": "..."}
  POST /confirm          (auth) {previewId} → {"ok": true, "entryId": 99} · 410 si caducó
  POST /caducar-token    caduca el token vigente (prueba de re-login)
  POST /caducar-preview  caduca el preview vigente (prueba de re-propuesta)
  GET  /stats            conteos para verificación externa

Solo escucha en 127.0.0.1. Credenciales de juguete, sin datos reales.
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

ESTADO = {"logins": 0, "previews": 0, "confirms": 0,
          "token": None, "preview": None, "caducados": set()}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        cuerpo = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return {}

    def _auth_ok(self):
        h = self.headers.get("Authorization") or ""
        return ESTADO["token"] and h == f"Bearer {ESTADO['token']}"

    def do_POST(self):
        if self.path == "/login":
            b = self._body()
            if b.get("user") == "beto" and b.get("pass") == "clave-qa-123":
                ESTADO["logins"] += 1
                ESTADO["token"] = f"tok-{ESTADO['logins']}"
                self._json(200, {"data": {"access_token": ESTADO["token"]}})
            else:
                self._json(401, {"error": "credenciales"})
        elif self.path == "/caducar-token":
            ESTADO["token"] = None
            self._json(200, {"ok": True})
        elif self.path == "/caducar-preview":
            if ESTADO["preview"]:
                ESTADO["caducados"].add(ESTADO["preview"])
            self._json(200, {"ok": True})
        elif self.path == "/preview":
            if not self._auth_ok():
                self._json(401, {"error": "sin token"})
                return
            ESTADO["previews"] += 1
            # previewId LARGO a propósito (~2700 chars, como un JWT real): el
            # bug del truncado a 2000 chars en el merge se pinnea aquí.
            ESTADO["preview"] = f"p-{ESTADO['previews']}-" + ("x" * 2700)
            self._json(200, {"previewId": ESTADO["preview"],
                             "resumen": f"propuesta {ESTADO['previews']} lista",
                             "summary": {"create": [{"actividad": "nota de prueba",
                                                     "estado": "Hecho", "minutos": 60}],
                                         "totals": {"items": 1, "minutos": 60}}})
        elif self.path == "/confirm":
            if not self._auth_ok():
                self._json(401, {"error": "sin token"})
                return
            pid = self._body().get("previewId")
            if not pid or pid in ESTADO["caducados"] or pid != ESTADO["preview"]:
                self._json(410, {"error": "previewId caducado"})
                return
            ESTADO["confirms"] += 1
            ESTADO["caducados"].add(pid)   # un preview se confirma UNA vez
            self._json(200, {"ok": True, "entryId": 99})
        else:
            self._json(404, {"error": "no existe"})

    def do_GET(self):
        if self.path == "/saldo":
            if not self._auth_ok():
                self._json(401, {"error": "sin token"})
                return
            self._json(200, {"saldo": 42})
        elif self.path == "/stats":
            self._json(200, {k: v for k, v in ESTADO.items() if k in
                             ("logins", "previews", "confirms")})
        else:
            self._json(404, {"error": "no existe"})


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 8765), H).serve_forever()
