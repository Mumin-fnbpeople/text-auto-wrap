#!/usr/bin/env python3
"""Serve one local font to the explicit Chrome typography validation test."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('font', type=Path)
parser.add_argument('--port', type=int, default=8768)
args = parser.parse_args()
font_bytes = args.font.read_bytes()


class FontHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/font.ttf':
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', 'font/ttf')
        self.send_header('Content-Length', str(len(font_bytes)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(font_bytes)


print(f'Font validation URL: http://127.0.0.1:{args.port}/font.ttf', flush=True)
ThreadingHTTPServer(('127.0.0.1', args.port), FontHandler).serve_forever()
