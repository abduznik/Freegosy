"""A small fake RomM for live tests of the Freegosy UI (see docs/live-testing.md).

Serves a library with a Switch bundle, a 60-file game, a DOS game and one large
single-file game (throttled, so it can be paused), including RomM's
`/api/roms/<id>/content/...?file_ids=` download (a zip for several files, the
bare file for one) with Range support.

    python3 tool/fake_romm/fake_romm.py 18080 [request-log-file]
"""
import io
import json
import re
import sys
import time
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


def file_entry(i, name, size=1048576, path=None):
    return {'id': i, 'file_name': name, 'file_size_bytes': size, **({'file_path': path} if path else {})}


NSP = {11: 'base.nsp', 12: 'update.nsp', 13: 'alt.nsp'}
MANY = {200 + i: f'manual_page_{i:02d}.pdf' for i in range(60)}
DOS = {
    31: ('PLAY.BAT', b'darkside\r\n'),
    32: ('Darkside/DARKSIDE.EXE', b'E' * 1000),
    33: ('Darkside/SETUP.EXE', b'S' * 5000),
    34: ('Darkside/ANIMATE.SON', b'A' * 90000),
}
BIG = 6 * 1024 * 1024

# rom id -> {file id: (path inside the zip, bytes)}
CONTENT = {
    1: {i: (n, n.encode() * 50) for i, n in NSP.items()},
    2: {i: ('media/' + n, b'm' * 200) for i, n in MANY.items()},
    3: dict(DOS),
    4: {41: ('big.gba', b'\x07' * BIG)},
}


def game(i, name, slug, platform_id, fs_name, files, multi, ext=''):
    return {
        'id': i, 'name': name, 'platform_id': platform_id, 'platform_slug': slug, 'platform_display_name': slug.upper(),
        'file_name': fs_name, 'fs_name': fs_name, 'fs_extension': ext,
        'fs_size_bytes': sum(x['file_size_bytes'] for x in files), 'has_multiple_files': multi, 'files': files,
    }


GAMES = [
    game(1, 'Zelda Bundle', 'switch', 1, 'zelda_bundle_v1', [file_entry(i, n) for i, n in NSP.items()], True),
    game(2, 'Manual Collection', 'switch', 1, 'manual_collection',
         [file_entry(i, n, path='switch/roms/manual_collection/media') for i, n in MANY.items()], True),
    game(3, 'Darkside Story', 'dos', 2, 'darkside_story', [file_entry(i, n[0], len(n[1])) for i, n in DOS.items()], True),
    game(4, 'Big Game', 'gba', 3, 'big.gba', [file_entry(41, 'big.gba', BIG)], False, 'gba'),
]
PLATFORMS = [
    {'id': 1, 'name': 'Switch', 'slug': 'switch', 'fs_slug': 'switch', 'display_name': 'Nintendo Switch', 'rom_count': 2},
    {'id': 2, 'name': 'DOS', 'slug': 'dos', 'fs_slug': 'dos', 'display_name': 'DOS', 'rom_count': 1},
    {'id': 3, 'name': 'GBA', 'slug': 'gba', 'fs_slug': 'gba', 'display_name': 'Game Boy Advance', 'rom_count': 1},
]
LOG = open(sys.argv[2], 'a', buffering=1) if len(sys.argv) > 2 else open('/dev/null', 'a')


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        path = url.path
        LOG.write(f'GET {self.path} range={self.headers.get("Range")}\n')
        if path == '/api/heartbeat':
            return self.send_json({'SYSTEM': {'VERSION': '5.0.0'}})
        if path == '/api/platforms':
            return self.send_json(PLATFORMS)
        if path == '/api/roms':
            ids = [int(x) for x in query.get('platform_ids', [])] or (
                [int(query['platform_id'][0])] if 'platform_id' in query else [])
            items = [g for g in GAMES if not ids or g['platform_id'] in ids]
            return self.send_json({'items': items, 'total': len(items), 'offset': 0, 'limit': 50})
        match = re.fullmatch(r'/api/roms/(\d+)', path)
        if match:
            return self.send_json(next(g for g in GAMES if g['id'] == int(match.group(1))))
        match = re.fullmatch(r'/api/roms/(\d+)/content/.*', path)
        if match:
            return self.send_content(int(match.group(1)), query)
        if path == '/api/users/me':
            return self.send_json({'id': 1, 'username': 'test'})
        if path in ('/api/collections', '/api/saves', '/api/states', '/api/firmware'):
            return self.send_json([])
        self.send_response(404)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def send_content(self, rom_id, query):
        files = CONTENT[rom_id]
        ids = [int(x) for x in query.get('file_ids', [''])[0].split(',') if x] or list(files)
        selected = [files[i] for i in ids]
        if len(selected) == 1:
            body, content_type = selected[0][1], 'application/octet-stream'
        else:
            buffer = io.BytesIO()
            with zipfile.ZipFile(buffer, 'w') as archive:
                for name, data in selected:
                    archive.writestr(name, data)
            body, content_type = buffer.getvalue(), 'application/zip'
        start, code = 0, 200
        requested = self.headers.get('Range')
        if requested:
            start, code = int(re.match(r'bytes=(\d+)-', requested).group(1)), 206
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body) - start))
        self.end_headers()
        bytes_per_second = 1024 * 1024 if rom_id == 4 else 0  # the big game is slow, so it can be paused
        try:
            for offset in range(start, len(body), 64 * 1024):
                self.wfile.write(body[offset:offset + 64 * 1024])
                self.wfile.flush()
                if bytes_per_second:
                    time.sleep(64 * 1024 / bytes_per_second)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        LOG.write(f'POST {self.path}\n')
        self.send_json({})

    do_PUT = do_POST


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()
