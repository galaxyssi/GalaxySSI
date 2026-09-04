"""Per-task allowlisted HTTP and HTTPS proxy for the GalaxySSI Linux guest."""

from __future__ import annotations

import base64
import hmac
import ipaddress
import re
import select
import socket
import socketserver
import threading
from dataclasses import dataclass
from urllib.parse import urlsplit


MAX_HEADER_BYTES = 64 * 1024
SOCKET_TIMEOUT_SECONDS = 20
ALLOWED_PORTS = {80, 443}
DOMAIN_LABEL = re.compile(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?")


def normalize_domain(value: str) -> str:
    domain = value.strip().rstrip(".").lower()
    try:
        encoded = domain.encode("idna").decode("ascii")
    except UnicodeError as error:
        raise ValueError("Network domain is invalid") from error
    if not encoded or len(encoded) > 253:
        raise ValueError("Network domain is invalid")
    labels = encoded.split(".")
    if any(DOMAIN_LABEL.fullmatch(label) is None for label in labels):
        raise ValueError("Network domain is invalid")
    return encoded


def domain_allowed(host: str, allowed_domains: tuple[str, ...]) -> bool:
    normalized = normalize_domain(host)
    return any(normalized == domain or normalized.endswith(f".{domain}") for domain in allowed_domains)


def resolve_public_address(host: str, port: int) -> tuple[int, tuple]:
    try:
        ipaddress.ip_address(host)
    except ValueError:
        pass
    else:
        raise ValueError("Direct IP network targets are not allowed")
    for family, socket_type, protocol, _, address in socket.getaddrinfo(
        host,
        port,
        family=socket.AF_INET,
        type=socket.SOCK_STREAM,
    ):
        if socket_type != socket.SOCK_STREAM:
            continue
        candidate = ipaddress.ip_address(address[0])
        if candidate.is_global:
            return family, address
    raise ValueError("Network target does not resolve to a public address")


@dataclass(frozen=True)
class ProxyEnvironment:
    values: dict[str, str]


class AllowlistedHttpProxy:
    def __init__(self, allowed_domains: list[str], token: str, max_transfer_bytes: int):
        normalized = tuple(sorted({normalize_domain(value) for value in allowed_domains}))
        if not normalized:
            raise ValueError("Network access requires an explicit domain allowlist")
        if not token or len(token) > 256:
            raise ValueError("Network proxy token is invalid")
        self.allowed_domains = normalized
        self.token = token
        self.max_transfer_bytes = max_transfer_bytes
        self._transferred = 0
        self._transfer_lock = threading.Lock()
        self._server = _ProxyServer(("127.0.0.1", 0), _ProxyHandler, self)
        self._thread = threading.Thread(
            target=self._server.serve_forever,
            name="galaxyssi-network-proxy",
            daemon=True,
        )

    def start(self) -> ProxyEnvironment:
        self._thread.start()
        port = self._server.server_address[1]
        proxy_url = f"http://galaxyssi:{self.token}@127.0.0.1:{port}"
        gradle_options = " ".join(
            (
                "-Dhttp.proxyHost=127.0.0.1",
                f"-Dhttp.proxyPort={port}",
                "-Dhttps.proxyHost=127.0.0.1",
                f"-Dhttps.proxyPort={port}",
                "-Dhttp.proxyUser=galaxyssi",
                f"-Dhttp.proxyPassword={self.token}",
                "-Dhttps.proxyUser=galaxyssi",
                f"-Dhttps.proxyPassword={self.token}",
                "-Djdk.http.auth.tunneling.disabledSchemes=",
            )
        )
        return ProxyEnvironment(
            {
                "HTTP_PROXY": proxy_url,
                "HTTPS_PROXY": proxy_url,
                "http_proxy": proxy_url,
                "https_proxy": proxy_url,
                "NO_PROXY": "127.0.0.1,localhost",
                "no_proxy": "127.0.0.1,localhost",
                "GRADLE_OPTS": gradle_options,
            }
        )

    def close(self) -> None:
        self._server.shutdown()
        self._server.server_close()
        self._thread.join(timeout=2)

    def authorize(self, supplied: str) -> bool:
        expected = base64.b64encode(f"galaxyssi:{self.token}".encode("utf-8")).decode("ascii")
        return hmac.compare_digest(supplied.strip(), f"Basic {expected}")

    def connect(self, host: str, port: int) -> socket.socket:
        if port not in ALLOWED_PORTS:
            raise ValueError("Network target port is not allowed")
        if not domain_allowed(host, self.allowed_domains):
            raise ValueError("Network target is outside the task allowlist")
        family, address = resolve_public_address(host, port)
        connection = socket.socket(family, socket.SOCK_STREAM)
        connection.settimeout(SOCKET_TIMEOUT_SECONDS)
        connection.connect(address)
        return connection

    def count_transfer(self, size: int) -> None:
        with self._transfer_lock:
            self._transferred += size
            if self._transferred > self.max_transfer_bytes:
                raise ValueError("Network transfer limit exceeded")


class _ProxyServer(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(self, address: tuple[str, int], handler, owner: AllowlistedHttpProxy):
        self.owner = owner
        super().__init__(address, handler)


class _ProxyHandler(socketserver.StreamRequestHandler):
    rbufsize = 0
    wbufsize = 0

    def handle(self) -> None:
        try:
            request_line, headers = self._read_headers()
            if not self.server.owner.authorize(headers.pop("proxy-authorization", "")):
                self._respond(407, "Proxy Authentication Required")
                return
            method, target, version = request_line.split(" ", 2)
            if method.upper() == "CONNECT":
                host, port = _split_authority(target, 443)
                upstream = self.server.owner.connect(host, port)
                try:
                    self.wfile.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                    self.wfile.flush()
                    _relay(self.connection, upstream, self.server.owner)
                finally:
                    upstream.close()
                return
            parsed = urlsplit(target)
            if (
                parsed.scheme.lower() != "http"
                or not parsed.hostname
                or parsed.username is not None
                or parsed.password is not None
            ):
                self._respond(400, "Bad Request")
                return
            port = parsed.port or 80
            upstream = self.server.owner.connect(parsed.hostname, port)
            try:
                path = parsed.path or "/"
                if parsed.query:
                    path += f"?{parsed.query}"
                headers.pop("proxy-connection", None)
                headers["host"] = parsed.netloc
                wire = [f"{method} {path} {version}"]
                wire.extend(f"{name}: {value}" for name, value in headers.items())
                payload = ("\r\n".join(wire) + "\r\n\r\n").encode("iso-8859-1")
                self.server.owner.count_transfer(len(payload))
                upstream.sendall(payload)
                _relay(self.connection, upstream, self.server.owner)
            finally:
                upstream.close()
        except (OSError, ValueError):
            try:
                self._respond(502, "Bad Gateway")
            except OSError:
                pass

    def _read_headers(self) -> tuple[str, dict[str, str]]:
        total = 0
        lines: list[str] = []
        while True:
            raw = self.rfile.readline(MAX_HEADER_BYTES + 1)
            total += len(raw)
            if not raw or total > MAX_HEADER_BYTES:
                raise ValueError("Proxy request headers are invalid")
            if raw in (b"\r\n", b"\n"):
                break
            lines.append(raw.decode("iso-8859-1").rstrip("\r\n"))
        if not lines:
            raise ValueError("Proxy request is empty")
        headers: dict[str, str] = {}
        for line in lines[1:]:
            name, separator, value = line.partition(":")
            if not separator:
                raise ValueError("Proxy request header is invalid")
            headers[name.strip().lower()] = value.strip()
        return lines[0], headers

    def _respond(self, code: int, reason: str) -> None:
        self.wfile.write(
            f"HTTP/1.1 {code} {reason}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".encode("ascii")
        )
        self.wfile.flush()


def _split_authority(value: str, default_port: int) -> tuple[str, int]:
    if value.startswith("["):
        raise ValueError("IPv6 proxy targets are not supported")
    host, separator, raw_port = value.rpartition(":")
    if not separator:
        return normalize_domain(value), default_port
    return normalize_domain(host), int(raw_port)


def _relay(client: socket.socket, upstream: socket.socket, owner: AllowlistedHttpProxy) -> None:
    sockets = [client, upstream]
    while sockets:
        readable, _, _ = select.select(sockets, [], [], SOCKET_TIMEOUT_SECONDS)
        if not readable:
            return
        for source in readable:
            data = source.recv(64 * 1024)
            if not data:
                return
            owner.count_transfer(len(data))
            destination = upstream if source is client else client
            destination.sendall(data)
