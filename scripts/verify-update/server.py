import http.server
import socket
import sys
import time

LATEST = "/releases/latest/download/"
TAGGED = "/releases/download/test/"


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith(LATEST):
            self.send_response(302)
            self.send_header("Location", TAGGED + self.path[len(LATEST):])
            self.end_headers()
        elif self.path.startswith(TAGGED):
            self.path = "/" + self.path[len(TAGGED):]
            super().do_GET()
        else:
            self.send_error(404)

    def log_message(self, fmt, *args):
        now = time.time()
        stamp = time.strftime("%H:%M:%S", time.localtime(now)) + f".{int(now * 1000) % 1000:03d}"
        print(stamp, self.client_address[0], fmt % args, getattr(self, "headers", {}).get("User-Agent", ""), flush=True)


# `localhost` names ::1 and 127.0.0.1, and clients try ::1 first. Answering on both keeps the feed on ::1:
# on this Mac a connect to 127.0.0.1 once went unanswered for 8 seconds while ::1 was fine.
class Server(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


port, directory = int(sys.argv[1]), sys.argv[2]
server = Server(("::", port), lambda *a, **k: Handler(*a, directory=directory, **k))
print(f"listening on {port}", flush=True)
server.serve_forever()
