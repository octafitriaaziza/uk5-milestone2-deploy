#!/usr/bin/env python3
"""Backend sederhana untuk demo multi-tier: dijalankan oleh webapp.service."""
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

HOST = "127.0.0.1"
PORT = int(os.environ.get("APP_PORT", "8000"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"Webapp OK\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.client_address[0], fmt % args), flush=True)


if __name__ == "__main__":
    HTTPServer((HOST, PORT), Handler).serve_forever()
