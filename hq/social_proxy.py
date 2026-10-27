"""Opt-in, loopback-only social preview proxy; every other HQ route stays local."""
import http.client
import os
from urllib.parse import urlsplit

import social

ENV = "HQ_SOCIAL_PREVIEW_UPSTREAM"
_HEADERS = {"content-type", "content-length", "content-range", "accept-ranges",
            "cache-control", "x-content-type-options"}


def social_path(path):
    return path == "/api/social" or path.startswith(("/api/social/", "/social-media/", "/social-art/"))


def _upstream(raw, own_port):
    try:
        parsed = urlsplit(raw)
        if (parsed.scheme != "http" or parsed.hostname != "127.0.0.1"
                or parsed.username or parsed.password or parsed.path not in ("", "/")
                or parsed.query or parsed.fragment or not parsed.port
                or parsed.port < 1024 or parsed.port == own_port):
            raise ValueError()
        return parsed.port
    except ValueError:
        raise social.SocialError("The Social videos preview upstream is invalid.", 503, "preview_unavailable")


def forward(handler, path):
    raw = os.environ.get(ENV)
    if ENV not in os.environ or not social_path(path):
        return False
    port = _upstream(raw, handler.server.server_address[1])
    body = None
    if handler.command == "POST":
        body = handler.rfile.read(social.guard_write(handler))
    headers = {key: handler.headers[key] for key in
               ("Host", "Origin", "Content-Type", "Content-Length", "Range") if key in handler.headers}
    # Never accept arbitrary forwarded hosts. The social guard recognizes only
    # the documented tailnet authority, preserved in Host by tailscale serve.
    if (handler.headers.get("Host") and "https://" + handler.headers["Host"] in social.TRUSTED_PROXY_ORIGINS
            and handler.client_address[0] in ("127.0.0.1", "::1")
            and handler.headers.get("X-Forwarded-Proto") == "https"):
        headers["X-Forwarded-Proto"] = "https"
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=15)
    started = False
    try:
        connection.request(handler.command, handler.path, body=body, headers=headers)
        response = connection.getresponse()
        handler.send_response(response.status)
        for key, value in response.getheaders():
            if key.lower() in _HEADERS:
                handler.send_header(key, value)
        handler.send_header("X-HQ-Social-Preview", "isolated")
        handler.send_header("Connection", "close")
        handler.end_headers()
        handler.close_connection = True
        started = True
        while True:
            chunk = response.read(256 * 1024)
            if not chunk:
                break
            handler.wfile.write(chunk)
    except (OSError, http.client.HTTPException):
        if not started:
            handler._send(503, {"error": "The Social videos preview is unavailable. Your other HQ pages are still available.",
                                "code": "preview_unavailable", "preview": True})
    finally:
        connection.close()
    return True
