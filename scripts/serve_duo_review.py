#!/usr/bin/env python3
"""Serve only a local review directory, with byte ranges for video seeking."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
import re


class ReviewHandler(SimpleHTTPRequestHandler):
    def send_head(self):
        self.byte_range = None
        path = self.translate_path(self.path)
        requested = self.headers.get('Range')
        if not requested or not os.path.isfile(path):
            return super().send_head()
        match = re.fullmatch(r'bytes=(\d*)-(\d*)', requested.strip())
        if not match:
            self.send_error(416)
            return None
        stream = open(path, 'rb')
        size = os.fstat(stream.fileno()).st_size
        start, end = match.groups()
        if not start:
            first, last = max(0, size - int(end or 0)), size - 1
        else:
            first, last = int(start), min(size - 1, int(end) if end else size - 1)
        if first > last or first >= size:
            stream.close()
            self.send_response(416)
            self.send_header('Content-Range', f'bytes */{size}')
            self.end_headers()
            return None
        self.send_response(206)
        self.send_header('Content-Type', self.guess_type(path))
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Range', f'bytes {first}-{last}/{size}')
        self.send_header('Content-Length', str(last - first + 1))
        self.end_headers()
        stream.seek(first)
        self.byte_range = last - first + 1
        return stream

    def copyfile(self, source, output):
        if self.byte_range is None:
            return super().copyfile(source, output)
        remaining = self.byte_range
        while remaining:
            chunk = source.read(min(1024 * 1024, remaining))
            if not chunk:
                break
            output.write(chunk)
            remaining -= len(chunk)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    handler = partial(ReviewHandler, directory=os.path.abspath(args.directory))
    print(f'Local review: http://127.0.0.1:{args.port}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), handler).serve_forever()


if __name__ == '__main__':
    main()
