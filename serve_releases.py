#!/usr/bin/env python3
"""Deadbolt Release Server — sirve ./releases/ con listado dinámico mobile-friendly."""

import os
import signal
import socket
import sys
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

PORT = 8080
RELEASES_DIR = Path(__file__).parent / "releases"

# ANSI colors
RED    = "\033[0;31m"
GREEN  = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE   = "\033[0;34m"
NC     = "\033[0m"

ICONS = {
    ".apk": "📦",
    ".zip": "🗜️",
    ".aab": "🏗️",
}

MIME_TYPES = {
    ".apk": "application/vnd.android.package-archive",
    ".zip": "application/zip",
    ".aab": "application/octet-stream",
}


def human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def build_index_html() -> str:
    files = sorted(
        [f for f in RELEASES_DIR.iterdir() if f.is_file() and not f.name.startswith(".")],
        key=lambda f: f.stat().st_mtime,
        reverse=True,
    )

    cards = ""
    for f in files:
        ext = f.suffix.lower()
        icon = ICONS.get(ext, "📄")
        size = human_size(f.stat().st_size)
        cards += f"""
        <div class="card">
          <div class="card-info">
            <span class="icon">{icon}</span>
            <div class="details">
              <span class="filename">{f.name}</span>
              <span class="size">{size}</span>
            </div>
          </div>
          <a class="btn" href="/{f.name}" download="{f.name}">⬇ Descargar</a>
        </div>"""

    if not cards:
        cards = '<p class="empty">No hay releases disponibles.</p>'

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return f"""<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Deadbolt Releases</title>
  <style>
    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #0d1117;
      color: #e6edf3;
      min-height: 100vh;
      padding: 24px 16px 48px;
    }}
    header {{
      text-align: center;
      margin-bottom: 32px;
    }}
    header h1 {{
      font-size: 1.6rem;
      font-weight: 700;
      letter-spacing: 0.5px;
    }}
    header p {{
      color: #8b949e;
      margin-top: 4px;
      font-size: 0.85rem;
    }}
    .list {{
      max-width: 600px;
      margin: 0 auto;
      display: flex;
      flex-direction: column;
      gap: 12px;
    }}
    .card {{
      background: #161b22;
      border: 1px solid #30363d;
      border-radius: 12px;
      padding: 16px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }}
    .card-info {{
      display: flex;
      align-items: center;
      gap: 12px;
      min-width: 0;
    }}
    .icon {{
      font-size: 2rem;
      flex-shrink: 0;
    }}
    .details {{
      display: flex;
      flex-direction: column;
      min-width: 0;
    }}
    .filename {{
      font-size: 0.9rem;
      font-weight: 500;
      word-break: break-all;
      color: #e6edf3;
    }}
    .size {{
      font-size: 0.78rem;
      color: #8b949e;
      margin-top: 2px;
    }}
    .btn {{
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
      background: #238636;
      color: #fff;
      text-decoration: none;
      border-radius: 8px;
      padding: 10px 16px;
      font-size: 0.85rem;
      font-weight: 600;
      min-height: 48px;
      white-space: nowrap;
      transition: background 0.15s;
    }}
    .btn:active {{ background: #2ea043; }}
    .empty {{
      text-align: center;
      color: #8b949e;
      padding: 32px;
    }}
    footer {{
      text-align: center;
      color: #484f58;
      font-size: 0.75rem;
      margin-top: 40px;
    }}
  </style>
</head>
<body>
  <header>
    <h1>🔒 Deadbolt Releases</h1>
    <p>Selecciona un fichero para descargar</p>
  </header>
  <div class="list">{cards}
  </div>
  <footer>Generado {now}</footer>
</body>
</html>"""


class ReleaseHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"  {BLUE}→{NC} {self.address_string()} — {fmt % args}")

    def do_GET(self):
        path = self.path.split("?")[0]

        if path == "/" or path == "/index.html":
            html = build_index_html().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)
            return

        filename = path.lstrip("/")
        filepath = RELEASES_DIR / filename

        if not filepath.is_file() or not filepath.resolve().is_relative_to(RELEASES_DIR.resolve()):
            self.send_error(404, "Fichero no encontrado")
            return

        ext = filepath.suffix.lower()
        mime = MIME_TYPES.get(ext, "application/octet-stream")
        size = filepath.stat().st_size

        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(size))
        self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
        self.end_headers()

        with open(filepath, "rb") as fh:
            while chunk := fh.read(65536):
                self.wfile.write(chunk)


def main():
    hostname = socket.gethostname()

    print(f"\n{BLUE}════════════════════════════════════════{NC}")
    print(f"{BLUE}  Deadbolt Release Server{NC}")
    print(f"{BLUE}════════════════════════════════════════{NC}\n")

    server = HTTPServer(("0.0.0.0", PORT), ReleaseHandler)

    def shutdown(sig, frame):
        print(f"\n{YELLOW}Cerrando servidor...{NC}")
        server.shutdown()
        print(f"{GREEN}Servidor cerrado. ¡Adiós!{NC}\n")
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    print(f"{GREEN}✓ Servidor iniciado{NC}\n")
    print(f"{BLUE}════════════════════════════════════════{NC}")
    print(f"{GREEN}  ¡Servidor listo!{NC}")
    print(f"{BLUE}════════════════════════════════════════{NC}\n")
    print(f"  {GREEN}http://{hostname}:{PORT}/{NC}\n")
    print(f"{BLUE}────────────────────────────────────────{NC}")
    print(f"Puerto: {GREEN}{PORT}{NC}")
    print(f"Dir:    {GREEN}{RELEASES_DIR}{NC}")
    print(f"{BLUE}────────────────────────────────────────{NC}\n")
    print(f"{YELLOW}Presiona Ctrl+C para detener el servidor{NC}\n")

    server.serve_forever()


if __name__ == "__main__":
    main()
