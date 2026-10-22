#!/usr/bin/env python3
# LeyzS: Spicetify "LeyzS Playlist" eklentisinin yolladigi bilgiyi alir ve
# her gelen JSON'u tek satir olarak stdout'a basar. Quickshell bu scripti
# kendisi baslatir ve ciktisini okur; elle calistirmana gerek yok.
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 38145
son = None
# Dock da ayni bilgiyi okusun diye son durum bu dosyaya da yazilir
DOSYA = os.path.expanduser("~/.cache/quickshell/spotify-playlist.json")


def dosyaya_yaz(satir):
    try:
        os.makedirs(os.path.dirname(DOSYA), exist_ok=True)
        gecici = DOSYA + ".tmp"
        with open(gecici, "w", encoding="utf-8") as f:
            f.write(satir + "\n")
        os.replace(gecici, DOSYA)
    except OSError as e:
        print("dosya yazilamadi: %s" % e, file=sys.stderr, flush=True)


class H(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Private-Network", "true")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_POST(self):
        global son
        try:
            n = int(self.headers.get("Content-Length") or 0)
            veri = json.loads(self.rfile.read(n).decode("utf-8") or "{}")
            satir = json.dumps({
                "type": str(veri.get("type") or ""),
                "name": str(veri.get("name") or ""),
                "image": str(veri.get("image") or ""),
            }, ensure_ascii=False)
            if satir != son:
                son = satir
                print(satir, flush=True)
                dosyaya_yaz(satir)
        except Exception as e:
            print("hata: %s" % e, file=sys.stderr, flush=True)
        self.send_response(204)
        self._cors()
        self.end_headers()

    def log_message(self, *a):
        pass


class S(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    try:
        S(("127.0.0.1", PORT), H).serve_forever()
    except OSError as e:
        print("port %d acilamadi: %s" % (PORT, e), file=sys.stderr, flush=True)
        sys.exit(1)
