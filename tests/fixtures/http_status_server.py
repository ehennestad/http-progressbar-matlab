"""Local HTTP server for the upload and download tests.

A PUT or POST request to /<code> receives HTTP status <code> with an empty
body. A PUT or POST request to /echo receives status 200 with a JSON body
that describes the request body: its length, the sum of its bytes, its
first and last bytes, the Content-Length and Transfer-Encoding headers of
the request (null when absent), and the list of its Content-Type headers. A GET request to /<code> receives status <code> with an HTML error
page. A GET request to /files/<name> receives status 200 with a text/plain
body. Its query can set the body with content=<text>, or with
size=<bytes> to a body of that many bytes that repeat the values 0 to
250, add a
Content-Disposition header with filename=<name>, keep the transfer in
progress for at least delay=<seconds> by pausing after the first byte of
the body, close the connection after truncate=<bytes> bytes of the body
while Content-Length still announces the whole body, and send a second
Content-Length header with the value extra_length=<bytes>.

A file response carries a strong ETag made from the body. The query can
set its opaque part with etag=<text>, make it weak with weak=1, or leave
it out with no_etag=1. A request with "Range: bytes=<first>-" receives
status 206 with the bytes from first onward, or status 416 without
Content-Range when first is at or past the end of the body. If-Range is
ignored, as some object stores do. ignore_range=1 makes the server ignore
Range and send status 200. range_start=<n> makes a 206 response start at
byte n instead of the byte the request asked for, and complete_length=*
makes it give the complete length as "*". gzip=1 sends the body gzipped
with "Content-Encoding: gzip". truncate and delay apply to the bytes
sent.

A GET request to /requests receives a JSON list of the file requests
received so far, each with its path and headers.

The server binds a free port on 127.0.0.1 and writes the port number to
the file given as the first command-line argument.
"""
import gzip
import hashlib
import http.server
import json
import os
import re
import signal
import sys
import time
from urllib.parse import parse_qs, unquote, urlsplit

# MATLAB runs system commands with SIGTERM blocked, and a child process
# inherits the set of blocked signals. Unblock SIGTERM so that kill stops
# the server when the fixture tears down.
signal.pthread_sigmask(signal.SIG_UNBLOCK, [signal.SIGTERM])


file_requests = []


class StatusHandler(http.server.BaseHTTPRequestHandler):
    def _read_body(self):
        """Return the request body, decoding a chunked transfer coding."""
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            body = b""
            while True:
                size = int(self.rfile.readline().split(b";")[0], 16)
                if size == 0:
                    # Skip any trailer fields and the final empty line.
                    while self.rfile.readline() not in (b"\r\n", b"\n", b""):
                        pass
                    return body
                body += self.rfile.read(size)
                self.rfile.readline()
        return self.rfile.read(int(self.headers.get("Content-Length", 0)))

    def _respond(self):
        # Read the whole request body before responding, so the client
        # finishes sending the file.
        body = self._read_body()
        if self.path.strip("/") == "echo":
            reply = json.dumps({
                "length": len(body),
                "sum": sum(body),
                "head": list(body[:16]),
                "tail": list(body[-16:]),
                "content_length": self.headers.get("Content-Length"),
                "transfer_encoding": self.headers.get("Transfer-Encoding"),
                "content_types": self.headers.get_all("Content-Type") or [],
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(reply)))
            self.end_headers()
            self.wfile.write(reply)
            return
        code = int(self.path.strip("/").split("/")[0] or 200)
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.end_headers()

    do_PUT = _respond
    do_POST = _respond

    def do_GET(self):
        url = urlsplit(self.path)
        segments = url.path.strip("/").split("/")
        query = parse_qs(url.query, keep_blank_values=True)

        if segments[0].isdigit():
            code = int(segments[0])
            content_type = "text/html"
            body = b"<html><body>Error page</body></html>"
        elif segments[0] == "requests":
            code = 200
            content_type = "application/json"
            body = json.dumps(file_requests).encode()
        elif segments[0] == "files":
            file_requests.append({"path": self.path,
                                  "headers": dict(self.headers.items())})
            code = 200
            content_type = "text/plain; charset=utf-8"
            name = unquote("/".join(segments[1:]))
            if "size" in query:
                size = int(query["size"][0])
                body = (bytes(range(251)) * (size // 251 + 1))[:size]
            else:
                body = query.get("content", [f"Content of {name}"])[0].encode()
        else:
            code = 404
            content_type = "text/plain"
            body = b"Not found"

        headers = []
        if segments[0] == "files":
            code, body, headers = self._select_range(body, query)
            if query.get("gzip", ["0"])[0] == "1":
                body = gzip.compress(body)
                headers.append(("Content-Encoding", "gzip"))

        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for header in headers:
            self.send_header(*header)
        if "extra_length" in query:
            self.send_header("Content-Length", query["extra_length"][0])
        if "filename" in query:
            self.send_header("Content-Disposition",
                             f'attachment; filename="{query["filename"][0]}"')
        self.end_headers()

        if "truncate" in query:
            # A connection that closes before the announced length, as a
            # dropped network connection does.
            self.wfile.write(body[:int(query["truncate"][0])])
            self.wfile.flush()
            self.close_connection = True
            return

        delay = float(query.get("delay", ["0"])[0])
        if delay > 0:
            # The pause comes after the first byte, so that it is part of
            # the body transfer whichever point the client times it from.
            self.wfile.write(body[:1])
            self.wfile.flush()
            time.sleep(delay)
            self.wfile.write(body[1:])
        else:
            self.wfile.write(body)

    def _select_range(self, body, query):
        """Return the status, body and extra headers for a file request."""
        headers = [("Accept-Ranges", "bytes")]
        if query.get("no_etag", ["0"])[0] != "1":
            opaque = query.get("etag", [hashlib.md5(body).hexdigest()])[0]
            etag = f'"{opaque}"'
            if query.get("weak", ["0"])[0] == "1":
                etag = "W/" + etag
            headers.append(("ETag", etag))

        match = re.fullmatch(r"bytes=(\d+)-", self.headers.get("Range", ""))
        if match is None or query.get("ignore_range", ["0"])[0] == "1":
            return 200, body, headers

        first = int(match.group(1))
        if first >= len(body):
            return 416, b"", headers
        first = int(query.get("range_start", [first])[0])
        complete = query.get("complete_length", [str(len(body))])[0]
        headers.append(("Content-Range",
                        f"bytes {first}-{len(body) - 1}/{complete}"))
        return 206, body[first:], headers

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), StatusHandler)
port_file = sys.argv[1]
# Write to a temporary file and rename it, so a reader never sees a
# partially written port number.
with open(port_file + ".tmp", "w") as file:
    file.write(str(server.server_address[1]))
os.replace(port_file + ".tmp", port_file)
server.serve_forever()
