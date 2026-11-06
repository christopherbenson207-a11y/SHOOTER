"""Receive Studio dumps from tools/dump.luau and rebuild src/ after each one.

Usage: python tools/syncback.py   (Ctrl+C to stop)
Dump lobby and campaign at least once (split.py needs both); zombies.json and duel.json are optional and go to src/zombies and src/duel.
"""
import http.server
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = os.path.join(ROOT, ".dump")
ALLOWED = {"lobby.json", "campaign.json", "zombies.json", "duel.json"}
NEEDED = {"lobby.json", "campaign.json"}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        name = self.headers.get("X-Name", "")
        if name not in ALLOWED:
            self.send_response(400)
            self.end_headers()
            return
        body = self.rfile.read(int(self.headers["Content-Length"]))
        os.makedirs(DUMP, exist_ok=True)
        with open(os.path.join(DUMP, name), "wb") as f:
            f.write(body)
        self.send_response(200)
        self.end_headers()
        print("received", name)
        if all(os.path.exists(os.path.join(DUMP, n)) for n in NEEDED):
            subprocess.run([sys.executable, os.path.join(ROOT, "tools", "split.py")], check=False)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print("waiting for Studio on http://127.0.0.1:34877 ...")
    http.server.HTTPServer(("127.0.0.1", 34877), Handler).serve_forever()
