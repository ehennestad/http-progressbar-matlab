"""Local HTTP server for the upload tests.

A PUT or POST request to /<code> receives HTTP status <code> with an empty
body. The server binds a free port on 127.0.0.1 and writes the port number
to the file given as the first command-line argument.
"""
import http.server
import os
import signal
import sys

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
