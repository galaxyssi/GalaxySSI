"""Bounded public HTTPS image downloads with DNS pinning and normal TLS checks."""
from __future__ import annotations

import http.client
import ipaddress
import socket
import ssl
import time
from urllib.parse import quote, urljoin, urlsplit

MAX_IMAGE_BYTES = 12 * 1024 * 1024


class ImageDownloadError(ValueError):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def public_destination(url: str, resolver=socket.getaddrinfo):
    try:
        parsed = urlsplit(url)
        if (len(url) > 4096 or parsed.scheme != "https" or not parsed.hostname
                or parsed.username or parsed.password or parsed.port not in (None, 443)
                or any(ord(char) < 32 for char in url)):
            raise ImageDownloadError("unsafe_image_url")
        addresses = list(dict.fromkeys(item[4][0] for item in resolver(
            parsed.hostname, 443, type=socket.SOCK_STREAM)))
        if not addresses or any(not ipaddress.ip_address(value).is_global
                                or ipaddress.ip_address(value).is_multicast for value in addresses):
            raise ImageDownloadError("non_public_image_destination")
        return parsed, addresses
    except (ValueError, OSError) as error:
        if isinstance(error, ImageDownloadError):
            raise
        raise ImageDownloadError("image_dns_failed") from error


def remaining(deadline: float) -> float:
    value = deadline - time.monotonic()
    if value <= 0:
        raise ImageDownloadError("image_download_timeout")
    return value


class PublicImageTransport:
    """Uses the Desktop OS network route, without forwarding cookies or credentials."""
    def fetch(self, url: str, *, deadline: float, max_bytes=MAX_IMAGE_BYTES) -> bytes:
        context = ssl.create_default_context()
        for _ in range(6):
            parsed, addresses = public_destination(url)
            connection = None
            last_error = None
            for address in sorted(addresses, key=lambda item: ":" in item):
                raw = None
                try:
                    raw = socket.create_connection((address, 443), min(5.0, remaining(deadline)))
                    connection = http.client.HTTPSConnection(parsed.hostname, timeout=remaining(deadline),
                                                             context=context)
                    # Connect only to the checked IP; SNI and certificate identity remain the hostname.
                    connection.auto_open = 0
                    connection.sock = context.wrap_socket(raw, server_hostname=parsed.hostname)
                    break
                except (OSError, ssl.SSLError) as error:
                    last_error = error
                    if raw is not None:
                        raw.close()
                    if connection is not None:
                        connection.close()
                    connection = None
            if connection is None:
                raise ImageDownloadError("image_connection_failed") from last_error
            response = None
            try:
                stream_socket = connection.sock
                stream_socket.settimeout(remaining(deadline))
                path = quote(parsed.path or "/", safe="/%:@!$&'()*+,;=-._~")
                if parsed.query:
                    path += "?" + quote(parsed.query, safe="%:@!$&'()*+,;=/?-._~")
                connection.request("GET", path, headers={
                    "Host": (f"[{parsed.hostname}]" if ":" in parsed.hostname
                             else parsed.hostname.encode("idna").decode("ascii")),
                    "User-Agent": "GalaxySSI/Desktop (+https://github.com/galaxyssi/GalaxySSI)",
                    "Accept": "image/avif,image/webp,image/png,image/jpeg,image/gif,*/*;q=0.1",
                    "Accept-Encoding": "identity",
                })
                response = connection.getresponse()
                if response.status in (301, 302, 303, 307, 308):
                    location = response.getheader("Location")
                    if not location:
                        raise ImageDownloadError("invalid_image_redirect")
                    url = urljoin(url, location)
                    continue
                if response.status != 200:
                    raise ImageDownloadError(f"image_http_{response.status}")
                media_type = response.getheader("Content-Type", "").split(";", 1)[0].strip().lower()
                if media_type.startswith("text/") or media_type in ("image/svg+xml", "application/xhtml+xml"):
                    raise ImageDownloadError("image_response_not_image")
                length = response.getheader("Content-Length")
                if length and (not length.isdecimal() or int(length) > max_bytes):
                    raise ImageDownloadError("image_too_large")
                result = bytearray()
                while True:
                    stream_socket.settimeout(remaining(deadline))
                    chunk = response.read1(min(64 * 1024, max_bytes + 1 - len(result)))
                    if not chunk:
                        return bytes(result)
                    result.extend(chunk)
                    if len(result) > max_bytes:
                        raise ImageDownloadError("image_too_large")
            except ImageDownloadError:
                raise
            except (OSError, http.client.HTTPException) as error:
                raise ImageDownloadError("image_transport_failed") from error
            finally:
                if response is not None:
                    response.close()
                connection.close()
        raise ImageDownloadError("too_many_image_redirects")
