"""Local HTTP server for the upload and download tests.

A PUT or POST request to /<code> receives HTTP status <code> with an empty
body. A GET request to /<code> receives status <code> with an HTML error
page. A GET request to /files/<name> receives status 200 with a text/plain
body. Its query can set the body with content=<text>, add a
Content-Disposition header with filename=<name>, and keep the transfer in
progress for at least delay=<seconds> by pausing after the first byte of
the body.

The server binds a free port on 127.0.0.1 and writes the port number to
the file given as the first command-line argument.
"""
import http.server
import os
import signal
import sys
import time
from urllib.parse import parse_qs, unquote, urlsplit

# MATLAB runs system commands with SIGTERM blocked, and a child process
# inherits the set of blocked signals. Unblock SIGTERM so that kill stops
# the server when the fixture tears down.
signal.pthread_sigmask(signal.SIG_UNBLOCK, [signal.SIGTERM])


class StatusHandler(http.server.BaseHTTPRequestHandler):
    def _respond(self):
        # Read the whole request body before responding, so the client
        # finishes sending the file.
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
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
        elif segments[0] == "files":
            code = 200
            content_type = "text/plain; charset=utf-8"
            name = unquote("/".join(segments[1:]))
            body = query.get("content", [f"Content of {name}"])[0].encode()
        else:
            code = 404
            content_type = "text/plain"
            body = b"Not found"

        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        if "filename" in query:
            self.send_header("Content-Disposition",
                             f'attachment; filename="{query["filename"][0]}"')
        self.end_headers()

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
