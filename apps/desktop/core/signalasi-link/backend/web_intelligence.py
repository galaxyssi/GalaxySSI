"""SignalASI-owned local web intelligence engine.

The module intentionally uses only the Python standard library. It exposes a
stable ten-operation contract while keeping search adapters, ranking, storage,
and answer synthesis replaceable. Network failures are returned as per-source
receipts instead of being hidden behind an empty result set.
"""
from __future__ import annotations

import base64
import concurrent.futures
import contextlib
import dataclasses
import datetime as dt
import difflib
import hashlib
import html
import ipaddress
import json
import math
import os
import re
import socket
import sqlite3
import struct
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET
import zlib
from collections import Counter, deque
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping, Protocol, Sequence


PROTOCOL = "signalasi.web-intelligence.v1"
MODEL_NAME = "signalasi-web-ranker"
MODEL_VERSION = 1

SEARCH = "signalasi.web.intelligence.search"
FETCH = "signalasi.web.intelligence.fetch"
CRAWL = "signalasi.web.intelligence.crawl"
EXTRACT = "signalasi.web.intelligence.extract"
CACHE = "signalasi.web.intelligence.cache"
FIND_SIMILAR = "signalasi.web.intelligence.find_similar"
RESEARCH = "signalasi.web.intelligence.research"
AGENT = "signalasi.web.intelligence.agent"
DIFF = "signalasi.web.intelligence.diff"
WATCH = "signalasi.web.intelligence.watch"

TOOL_OPERATIONS = {
    SEARCH: "search",
    FETCH: "fetch",
    CRAWL: "crawl",
    EXTRACT: "extract",
    CACHE: "cache",
    FIND_SIMILAR: "find_similar",
    RESEARCH: "research",
    AGENT: "agent",
    DIFF: "diff",
    WATCH: "watch",
}

MAX_QUERY_CHARS = 4_096
MAX_URL_CHARS = 4_096
MAX_FETCH_BYTES = 2 * 1024 * 1024
MAX_CONTENT_CHARS = 512 * 1024
MAX_RESULTS = 100
MAX_CRAWL_PAGES = 100
MAX_CRAWL_DEPTH = 5
MAX_LINKS = 4_096
MAX_ENGINE_FANOUT = 32
DEFAULT_ENGINE_FANOUT = 18
DEFAULT_TIMEOUT_SECONDS = 15.0
DEFAULT_CACHE_TTL_SECONDS = 24 * 60 * 60
DEFAULT_VECTOR_DIMENSIONS = 192
SOURCE_HEALTH_FAILURE_THRESHOLD = 3
SOURCE_HEALTH_BASE_COOLDOWN_MILLIS = 60_000
SOURCE_HEALTH_MAX_COOLDOWN_MILLIS = 30 * 60_000
SOURCE_HEALTH_EWMA_ALPHA = 0.25
SEARCH_PROFILES: Mapping[str, tuple[int, float]] = {
    "fast": (6, 6.0),
    "balanced": (DEFAULT_ENGINE_FANOUT, DEFAULT_TIMEOUT_SECONDS),
    "deep": (MAX_ENGINE_FANOUT, 35.0),
}


class WebIntelligenceError(RuntimeError):
    def __init__(
        self,
        code: str,
        message: str,
        *,
        retryable: bool = False,
        details: Mapping[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = str(code or "web_intelligence_failed")
        self.retryable = bool(retryable)
        self.details = dict(details or {})


@dataclass(frozen=True)
class HttpResponse:
    url: str
    status: int
    headers: Mapping[str, str]
    body: bytes
    duration_ms: int


class WebTransport(Protocol):
    def fetch(
        self,
        url: str,
        *,
        timeout_seconds: float,
        max_bytes: int,
        headers: Mapping[str, str] | None = None,
    ) -> HttpResponse:
        ...


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        return None


class PublicWebTransport:
    """Bounded transport with redirect-by-redirect SSRF checks."""

    USER_AGENT = (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/126.0 Safari/537.36 SignalASI/0.2"
    )

    def __init__(self, resolver: Callable[[str], Sequence[str]] | None = None) -> None:
        self._resolver = resolver or self._resolve
        self._opener = urllib.request.build_opener(_NoRedirect())

    def fetch(
        self,
        url: str,
        *,
        timeout_seconds: float,
        max_bytes: int,
        headers: Mapping[str, str] | None = None,
    ) -> HttpResponse:
        if max_bytes < 1 or max_bytes > MAX_FETCH_BYTES:
            raise WebIntelligenceError("invalid_limit", "Fetch byte limit is outside the allowed range")
        current = self._validate_public_url(url)
        started = time.monotonic()
        request_headers = {
            "User-Agent": self.USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/json,application/atom+xml,application/xml,text/plain;q=0.9,*/*;q=0.3",
            "Accept-Language": "en-US,en;q=0.8,zh-CN;q=0.7,zh;q=0.6",
            "Cache-Control": "no-cache",
            **dict(headers or {}),
        }
        for _ in range(5):
            parsed = urllib.parse.urlsplit(current)
            self._require_public_host(parsed.hostname or "")
            request = urllib.request.Request(current, headers=request_headers, method="GET")
            try:
                response = self._opener.open(request, timeout=max(0.2, timeout_seconds))
            except urllib.error.HTTPError as exc:
                if exc.code in {301, 302, 303, 307, 308}:
                    location = exc.headers.get("Location")
                    if not location:
                        raise WebIntelligenceError("redirect_missing", "Redirect did not include a destination")
                    current = self._validate_public_url(urllib.parse.urljoin(current, location))
                    continue
                body = exc.read(4_096).decode("utf-8", errors="replace")
                raise WebIntelligenceError(
                    "http_status",
                    f"HTTP {exc.code}: {body[:500]}",
                    retryable=exc.code in {408, 425, 429} or exc.code >= 500,
                    details={"status": exc.code, "url": current},
                ) from exc
            except (urllib.error.URLError, TimeoutError, socket.timeout, OSError) as exc:
                raise WebIntelligenceError(
                    "transport_failed",
                    str(exc.reason if isinstance(exc, urllib.error.URLError) else exc),
                    retryable=True,
                    details={"url": current},
                ) from exc
            with contextlib.closing(response):
                status = int(getattr(response, "status", 200))
                content_length = response.headers.get("Content-Length")
                if content_length and int(content_length) > max_bytes:
                    raise WebIntelligenceError("response_too_large", "Response exceeds the configured byte limit")
                body = response.read(max_bytes + 1)
                if len(body) > max_bytes:
                    raise WebIntelligenceError("response_too_large", "Response exceeds the configured byte limit")
                return HttpResponse(
                    url=current,
                    status=status,
                    headers={key.lower(): value for key, value in response.headers.items()},
                    body=body,
                    duration_ms=max(0, int((time.monotonic() - started) * 1_000)),
                )
        raise WebIntelligenceError("too_many_redirects", "Response exceeded the redirect limit")

    @staticmethod
    def _resolve(host: str) -> Sequence[str]:
        return sorted({
            item[4][0]
            for item in socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
            if item and item[4]
        })

    def _require_public_host(self, host: str) -> None:
        if not host:
            raise WebIntelligenceError("invalid_url", "URL does not contain a host")
        try:
            addresses = self._resolver(host)
        except OSError as exc:
            raise WebIntelligenceError("dns_failed", f"Could not resolve {host}", retryable=True) from exc
        if not addresses:
            raise WebIntelligenceError("dns_failed", f"Could not resolve {host}", retryable=True)
        for raw in addresses[:32]:
            address = ipaddress.ip_address(raw)
            if (
                address.is_private
                or address.is_loopback
                or address.is_link_local
                or address.is_multicast
                or address.is_reserved
                or address.is_unspecified
            ):
                raise WebIntelligenceError(
                    "private_network_blocked",
                    "Public web tools cannot access local or private network targets",
                    details={"host": host},
                )

    @staticmethod
    def _validate_public_url(value: str) -> str:
        if not isinstance(value, str) or len(value.strip()) not in range(1, MAX_URL_CHARS + 1):
            raise WebIntelligenceError("invalid_url", "URL is blank or too long")
        parsed = urllib.parse.urlsplit(value.strip())
        if parsed.scheme not in {"http", "https"} or not parsed.hostname:
            raise WebIntelligenceError("invalid_url", "Only explicit HTTP and HTTPS URLs are supported")
        if parsed.username or parsed.password:
            raise WebIntelligenceError("invalid_url", "Credentials are not allowed in URLs")
        return urllib.parse.urlunsplit(parsed)


@dataclass(frozen=True)
class EngineSpec:
    engine_id: str
    title: str
    vertical: str
    endpoint: str
    parser: str = "html"
    languages: tuple[str, ...] = ("*",)
    weight: float = 1.0
    authority: float = 0.5
    default_enabled: bool = True
    requires_key: str = ""


@dataclass(frozen=True)
class RawSearchResult:
    engine_id: str
    rank: int
    title: str
    url: str
    excerpt: str = ""
    published_at: str = ""
    vertical: str = "general"


@dataclass(frozen=True)
class EngineReceipt:
    source_id: str
    status: str
    duration_millis: int
    result_count: int
    error_code: str = ""
    error_message: str = ""
    retryable: bool = False

    def public(self) -> dict[str, Any]:
        return {
            "source_id": self.source_id,
            "status": self.status,
            "duration_millis": max(0, self.duration_millis),
            "result_count": max(0, self.result_count),
            "error_code": self.error_code,
            "error_message": self.error_message[:2_048],
            "retryable": self.retryable,
        }


@dataclass(frozen=True)
class SourceHealth:
    source_id: str
    attempts: int = 0
    successes: int = 0
    empty_responses: int = 0
    failures: int = 0
    consecutive_failures: int = 0
    ewma_latency_millis: float = 0.0
    ewma_result_count: float = 0.0
    last_status: str = ""
    last_attempt_at_millis: int = 0
    last_success_at_millis: int = 0
    circuit_open_until_millis: int = 0

    def circuit_state(self, now_millis: int) -> str:
        if self.circuit_open_until_millis > now_millis:
            return "open"
        if self.consecutive_failures >= SOURCE_HEALTH_FAILURE_THRESHOLD:
            return "half_open"
        return "closed"

    def routing_score(self) -> float:
        reliable = (self.successes + self.empty_responses + 2.0) / (self.attempts + 4.0)
        speed = 0.6 if self.ewma_latency_millis <= 0 else 1.0 / (
            1.0 + self.ewma_latency_millis / 3_000.0
        )
        useful = min(1.0, self.ewma_result_count / 8.0)
        exploration = 1.0 / math.sqrt(self.attempts + 1.0)
        return reliable * 1.1 + speed * 0.5 + useful * 0.35 + exploration * 0.25

    def public(self, now_millis: int) -> dict[str, Any]:
        return {
            "source_id": self.source_id,
            "attempts": self.attempts,
            "successes": self.successes,
            "empty_responses": self.empty_responses,
            "failures": self.failures,
            "consecutive_failures": self.consecutive_failures,
            "ewma_latency_millis": round(self.ewma_latency_millis, 3),
            "ewma_result_count": round(self.ewma_result_count, 3),
            "last_status": self.last_status,
            "last_attempt_at_millis": self.last_attempt_at_millis,
            "last_success_at_millis": self.last_success_at_millis,
            "circuit_state": self.circuit_state(now_millis),
            "circuit_open_until_millis": self.circuit_open_until_millis,
            "routing_score": round(self.routing_score(), 6),
        }


@dataclass(frozen=True)
class SourceSelection:
    selected: tuple[str, ...]
    skipped: tuple[SourceHealth, ...]
    explicit: bool = False


def evolve_source_health(
    previous: SourceHealth,
    receipt: EngineReceipt,
    now_millis: int,
) -> SourceHealth:
    if receipt.status == "cancelled":
        return dataclasses.replace(
            previous,
            last_status=receipt.status,
            last_attempt_at_millis=now_millis,
        )
    alpha = SOURCE_HEALTH_EWMA_ALPHA
    latency = float(max(0, receipt.duration_millis))
    result_count = float(max(0, receipt.result_count))
    ewma_latency = latency if previous.attempts == 0 else (
        previous.ewma_latency_millis * (1.0 - alpha) + latency * alpha
    )
    ewma_results = result_count if previous.attempts == 0 else (
        previous.ewma_result_count * (1.0 - alpha) + result_count * alpha
    )
    successful = receipt.status in {"completed", "empty"}
    consecutive_failures = 0 if successful else previous.consecutive_failures + 1
    circuit_open_until = 0
    if not successful and consecutive_failures >= SOURCE_HEALTH_FAILURE_THRESHOLD:
        exponent = min(10, consecutive_failures - SOURCE_HEALTH_FAILURE_THRESHOLD)
        cooldown = min(
            SOURCE_HEALTH_MAX_COOLDOWN_MILLIS,
            SOURCE_HEALTH_BASE_COOLDOWN_MILLIS * (2 ** exponent),
        )
        circuit_open_until = now_millis + cooldown
    return SourceHealth(
        source_id=previous.source_id,
        attempts=previous.attempts + 1,
        successes=previous.successes + int(receipt.status == "completed"),
        empty_responses=previous.empty_responses + int(receipt.status == "empty"),
        failures=previous.failures + int(not successful),
        consecutive_failures=consecutive_failures,
        ewma_latency_millis=ewma_latency,
        ewma_result_count=ewma_results,
        last_status=receipt.status,
        last_attempt_at_millis=now_millis,
        last_success_at_millis=(
            now_millis if successful else previous.last_success_at_millis
        ),
        circuit_open_until_millis=circuit_open_until,
    )


@dataclass
class FusedSearchResult:
    title: str
    url: str
    excerpt: str
    vertical: str
    published_at: str
    engine_ranks: dict[str, int] = field(default_factory=dict)
    engine_weights: dict[str, float] = field(default_factory=dict)
    authority: float = 0.0
    score: dict[str, float] = field(default_factory=dict)

    def public(self, rank: int) -> dict[str, Any]:
        return {
            "citation_id": citation_id(self.url, self.excerpt),
            "title": self.title[:2_048],
            "url": self.url[:MAX_URL_CHARS],
            "excerpt": self.excerpt[:16_384],
            "published_at": self.published_at[:64],
            "language": detect_language(f"{self.title} {self.excerpt}"),
            "vertical": self.vertical,
            "engines": sorted(self.engine_ranks),
            "rank": rank,
            "score": {name: round(float(value), 6) for name, value in self.score.items()},
        }


ENGINE_SPECS: tuple[EngineSpec, ...] = (
    EngineSpec("bing", "Bing", "general", "https://www.bing.com/search?q={query}&count={limit}", weight=1.05),
    EngineSpec("duckduckgo", "DuckDuckGo", "general", "https://html.duckduckgo.com/html/?q={query}", weight=1.05),
    EngineSpec("baidu", "Baidu", "general", "https://www.baidu.com/s?wd={query}&rn={limit}", languages=("zh",), weight=1.05),
    EngineSpec("brave", "Brave Search", "general", "https://search.brave.com/search?q={query}&source=web"),
    EngineSpec("mojeek", "Mojeek", "general", "https://www.mojeek.com/search?q={query}"),
    EngineSpec("qwant", "Qwant", "general", "https://www.qwant.com/?q={query}&t=web"),
    EngineSpec("yahoo", "Yahoo", "general", "https://search.yahoo.com/search?p={query}"),
    EngineSpec("yandex", "Yandex", "general", "https://yandex.com/search/?text={query}"),
    EngineSpec("ecosia", "Ecosia", "general", "https://www.ecosia.org/search?q={query}"),
    EngineSpec("startpage", "Startpage", "general", "https://www.startpage.com/sp/search?query={query}"),
    EngineSpec("sogou", "Sogou", "general", "https://www.sogou.com/web?query={query}", languages=("zh",)),
    EngineSpec("so360", "360 Search", "general", "https://www.so.com/s?q={query}", languages=("zh",)),
    EngineSpec("naver", "Naver", "general", "https://search.naver.com/search.naver?query={query}", languages=("ko",)),
    EngineSpec("google", "Google", "general", "https://www.google.com/search?q={query}&num={limit}", default_enabled=False),
    EngineSpec("bing_news", "Bing News", "news", "https://www.bing.com/news/search?q={query}&count={limit}", weight=1.1),
    EngineSpec("brave_news", "Brave News", "news", "https://search.brave.com/news?q={query}"),
    EngineSpec("wikipedia", "Wikipedia", "knowledge", "https://en.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit={limit}&srsearch={query}", parser="wikipedia", authority=0.9),
    EngineSpec("wikipedia_zh", "Wikipedia Chinese", "knowledge", "https://zh.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit={limit}&srsearch={query}", parser="wikipedia_zh", languages=("zh",), authority=0.9),
    EngineSpec("github", "GitHub", "code", "https://api.github.com/search/repositories?q={query}&per_page={limit}", parser="github", authority=0.85),
    EngineSpec("gitlab", "GitLab", "code", "https://gitlab.com/api/v4/projects?search={query}&per_page={limit}", parser="gitlab", authority=0.8),
    EngineSpec("stackoverflow", "Stack Overflow", "community", "https://api.stackexchange.com/2.3/search/advanced?site=stackoverflow&pagesize={limit}&q={query}", parser="stackoverflow", authority=0.85),
    EngineSpec("hacker_news", "Hacker News", "community", "https://hn.algolia.com/api/v1/search?hitsPerPage={limit}&query={query}", parser="hacker_news", authority=0.7),
    EngineSpec("lobsters", "Lobsters", "community", "https://lobste.rs/search.json?q={query}", parser="lobsters", authority=0.7),
    EngineSpec("reddit", "Reddit", "community", "https://www.reddit.com/search.json?q={query}&limit={limit}&raw_json=1", parser="reddit", authority=0.65),
    EngineSpec("crossref", "Crossref", "academic", "https://api.crossref.org/works?rows={limit}&query={query}", parser="crossref", authority=0.9),
    EngineSpec("semantic_scholar", "Semantic Scholar", "academic", "https://api.semanticscholar.org/graph/v1/paper/search?limit={limit}&fields=title,url,abstract,year,authors&query={query}", parser="semantic_scholar", authority=0.9),
    EngineSpec("arxiv", "arXiv", "academic", "https://export.arxiv.org/api/query?max_results={limit}&search_query=all:{query}", parser="atom", authority=0.9),
    EngineSpec("pubmed", "PubMed", "academic", "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json&retmax={limit}&term={query}", parser="pubmed", authority=0.95),
    EngineSpec("crates_io", "crates.io", "code", "https://crates.io/api/v1/crates?q={query}&per_page={limit}", parser="crates_io", authority=0.8),
    EngineSpec("npm", "npm", "code", "https://registry.npmjs.org/-/v1/search?size={limit}&text={query}", parser="npm", authority=0.8),
    EngineSpec("mdn", "MDN", "docs", "https://developer.mozilla.org/api/v1/search?q={query}&page_size={limit}", parser="mdn", authority=0.95),
    EngineSpec("pypi", "PyPI", "code", "https://pypi.org/search/?q={query}", authority=0.8),
)


def engine_catalog() -> list[dict[str, Any]]:
    return [
        {
            "id": spec.engine_id,
            "title": spec.title,
            "vertical": spec.vertical,
            "languages": list(spec.languages),
            "default_enabled": spec.default_enabled,
            "requires_key": spec.requires_key,
        }
        for spec in ENGINE_SPECS
    ]


def _safe_text(value: Any, limit: int) -> str:
    if value is None:
        return ""
    return re.sub(r"\s+", " ", html.unescape(str(value))).strip()[:limit]


def citation_id(url: str, excerpt: str = "") -> str:
    return hashlib.sha256(f"{canonical_url(url)}\n{excerpt}".encode("utf-8")).hexdigest()[:24]


def canonical_url(value: str) -> str:
    try:
        parsed = urllib.parse.urlsplit(value.strip())
    except ValueError:
        return value.strip()
    host = (parsed.hostname or "").lower().removeprefix("www.")
    scheme = parsed.scheme.lower() or "https"
    port = parsed.port
    netloc = host
    if port and not ((scheme == "https" and port == 443) or (scheme == "http" and port == 80)):
        netloc = f"{host}:{port}"
    query = urllib.parse.parse_qsl(parsed.query, keep_blank_values=False)
    filtered = [
        (key, item)
        for key, item in query
        if not key.lower().startswith("utm_")
        and key.lower() not in {"gclid", "fbclid", "ref", "source", "campaign"}
    ]
    path = re.sub(r"/+", "/", parsed.path or "/")
    if path != "/":
        path = path.rstrip("/")
    return urllib.parse.urlunsplit((scheme, netloc, path, urllib.parse.urlencode(sorted(filtered)), ""))


def _unwrap_search_url(value: str) -> str:
    decoded = html.unescape(value or "").strip()
    if decoded.startswith("//"):
        decoded = "https:" + decoded
    parsed = urllib.parse.urlsplit(decoded)
    params = urllib.parse.parse_qs(parsed.query)
    for key in ("uddg", "url", "u", "target", "r"):
        candidate = params.get(key, [""])[0]
        if candidate.startswith(("http://", "https://")):
            return urllib.parse.unquote(candidate)
    return decoded


def _tokens(value: str) -> list[str]:
    normalized = unicodedata.normalize("NFKC", value).lower()
    latin = re.findall(r"[a-z0-9][a-z0-9_+.-]{1,}", normalized)
    cjk_groups = re.findall(r"[\u3400-\u9fff]+", normalized)
    cjk: list[str] = []
    for group in cjk_groups:
        if len(group) == 1:
            cjk.append(group)
        else:
            cjk.extend(group[index:index + 2] for index in range(len(group) - 1))
    return latin + cjk


def detect_language(value: str) -> str:
    if re.search(r"[\u3400-\u9fff]", value):
        return "zh"
    if re.search(r"[\u3040-\u30ff]", value):
        return "ja"
    if re.search(r"[\uac00-\ud7af]", value):
        return "ko"
    return "en"


class SearchAnchorParser(HTMLParser):
    def __init__(self, base_url: str) -> None:
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.results: list[tuple[str, str]] = []
        self._href = ""
        self._text: list[str] = []
        self._depth = 0
        self._ignore = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in {"script", "style", "svg", "noscript"}:
            self._ignore += 1
            return
        if self._ignore:
            return
        if tag == "a" and not self._href:
            href = dict(attrs).get("href") or ""
            if href:
                self._href = href
                self._text = []
                self._depth = 1
        elif self._href:
            self._depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style", "svg", "noscript"} and self._ignore:
            self._ignore -= 1
            return
        if not self._href:
            return
        self._depth -= 1
        if tag == "a" or self._depth <= 0:
            title = _safe_text(" ".join(self._text), 2_048)
            target = urllib.parse.urljoin(self.base_url, _unwrap_search_url(self._href))
            if title and target.startswith(("http://", "https://")):
                self.results.append((title, target))
            self._href = ""
            self._text = []
            self._depth = 0

    def handle_data(self, data: str) -> None:
        if self._href and not self._ignore:
            self._text.append(data)


class ReadableHtmlParser(HTMLParser):
    BLOCKS = {
        "p", "div", "article", "section", "main", "li", "h1", "h2", "h3",
        "h4", "h5", "h6", "pre", "blockquote", "tr", "br",
    }

    def __init__(self, base_url: str) -> None:
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.title = ""
        self._in_title = False
        self._ignore = 0
        self._parts: list[str] = []
        self.links: list[str] = []
        self.metadata: dict[str, str] = {}
        self.json_ld: list[Any] = []
        self._json_ld_depth = 0
        self._json_ld_parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {str(key).lower(): value or "" for key, value in attrs}
        if tag in {"script", "style", "svg", "noscript", "template"}:
            if tag == "script" and values.get("type", "").lower() == "application/ld+json":
                self._json_ld_depth = 1
                self._json_ld_parts = []
            else:
                self._ignore += 1
            return
        if self._ignore:
            return
        if tag == "title":
            self._in_title = True
        if tag == "a":
            href = urllib.parse.urljoin(self.base_url, values.get("href", ""))
            if href.startswith(("http://", "https://")) and len(self.links) < MAX_LINKS:
                self.links.append(canonical_url(href))
        if tag == "meta":
            key = values.get("property") or values.get("name")
            content = values.get("content")
            if key and content and len(self.metadata) < 128:
                self.metadata[key.lower()[:128]] = _safe_text(content, 4_096)
        if tag in self.BLOCKS:
            self._parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if self._json_ld_depth and tag == "script":
            self._json_ld_depth = 0
            raw = "".join(self._json_ld_parts).strip()
            if raw:
                with contextlib.suppress(json.JSONDecodeError):
                    self.json_ld.append(json.loads(raw))
            return
        if tag in {"script", "style", "svg", "noscript", "template"} and self._ignore:
            self._ignore -= 1
            return
        if tag == "title":
            self._in_title = False
        if tag in self.BLOCKS:
            self._parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self._json_ld_depth:
            self._json_ld_parts.append(data)
            return
        if self._ignore:
            return
        clean = _safe_text(data, 16_384)
        if not clean:
            return
        if self._in_title:
            self.title = _safe_text(f"{self.title} {clean}", 2_048)
        self._parts.append(clean)

    @property
    def text(self) -> str:
        lines = []
        for line in "".join(
            ("\n" if part == "\n" else f" {part} ")
            for part in self._parts
        ).splitlines():
            clean = _safe_text(line, MAX_CONTENT_CHARS)
            if clean and (not lines or clean != lines[-1]):
                lines.append(clean)
        return "\n\n".join(lines)[:MAX_CONTENT_CHARS]


class SearchEngineAdapter:
    def __init__(self, spec: EngineSpec, transport: WebTransport) -> None:
        self.spec = spec
        self.transport = transport

    def search(self, query: str, limit: int, timeout_seconds: float) -> list[RawSearchResult]:
        encoded = urllib.parse.quote_plus(query)
        url = self.spec.endpoint.format(query=encoded, limit=limit)
        response = self.transport.fetch(
            url,
            timeout_seconds=timeout_seconds,
            max_bytes=MAX_FETCH_BYTES,
            headers={"Accept": self._accept_header()},
        )
        return self._parse(response, limit)

    def _accept_header(self) -> str:
        if self.spec.parser in {"html"}:
            return "text/html,application/xhtml+xml"
        if self.spec.parser == "atom":
            return "application/atom+xml,application/xml,text/xml"
        return "application/json,text/json"

    def _parse(self, response: HttpResponse, limit: int) -> list[RawSearchResult]:
        charset = _response_charset(response.headers.get("content-type", ""))
        text = response.body.decode(charset, errors="replace")
        parser = self.spec.parser
        if parser == "html":
            return self._parse_html(text, response.url, limit)
        if parser == "atom":
            return self._parse_atom(text, limit)
        try:
            value = json.loads(text)
        except json.JSONDecodeError as exc:
            raise WebIntelligenceError(
                "invalid_engine_response",
                f"{self.spec.title} did not return valid JSON",
                retryable=True,
            ) from exc
        handler = getattr(self, f"_parse_{parser}", None)
        if handler is None:
            raise WebIntelligenceError("unsupported_engine_parser", f"Unsupported parser: {parser}")
        return handler(value, limit)

    def _result(
        self,
        rank: int,
        title: Any,
        url: Any,
        excerpt: Any = "",
        published_at: Any = "",
    ) -> RawSearchResult | None:
        clean_title = _safe_text(title, 2_048)
        clean_url = _unwrap_search_url(_safe_text(url, MAX_URL_CHARS))
        if not clean_title or not clean_url.startswith(("http://", "https://")):
            return None
        return RawSearchResult(
            engine_id=self.spec.engine_id,
            rank=rank,
            title=clean_title,
            url=clean_url,
            excerpt=_safe_text(excerpt, 16_384),
            published_at=_safe_text(published_at, 64),
            vertical=self.spec.vertical,
        )

    def _parse_html(self, text: str, base_url: str, limit: int) -> list[RawSearchResult]:
        parser = SearchAnchorParser(base_url)
        parser.feed(text)
        ignored_hosts = {
            urllib.parse.urlsplit(base_url).hostname or "",
            "accounts.google.com",
            "support.google.com",
        }
        results: list[RawSearchResult] = []
        seen: set[str] = set()
        for title, url in parser.results:
            parsed = urllib.parse.urlsplit(url)
            if not parsed.hostname or parsed.hostname in ignored_hosts:
                continue
            normalized = canonical_url(url)
            if normalized in seen:
                continue
            seen.add(normalized)
            result = self._result(len(results) + 1, title, url)
            if result is not None:
                results.append(result)
            if len(results) >= limit:
                break
        return results

    def _parse_wikipedia(self, value: Any, limit: int) -> list[RawSearchResult]:
        return self._parse_wikipedia_common(value, limit, "en")

    def _parse_wikipedia_zh(self, value: Any, limit: int) -> list[RawSearchResult]:
        return self._parse_wikipedia_common(value, limit, "zh")

    def _parse_wikipedia_common(self, value: Any, limit: int, language: str) -> list[RawSearchResult]:
        rows = _list_at(value, "query", "search")
        output = []
        for row in rows[:limit]:
            page_id = row.get("pageid")
            title = row.get("title")
            url = f"https://{language}.wikipedia.org/?curid={page_id}" if page_id else ""
            result = self._result(len(output) + 1, title, url, _strip_html(row.get("snippet", "")))
            if result:
                output.append(result)
        return output

    def _parse_github(self, value: Any, limit: int) -> list[RawSearchResult]:
        rows = value.get("items", []) if isinstance(value, dict) else []
        return self._rows(rows, limit, "full_name", "html_url", "description", "updated_at")

    def _parse_gitlab(self, value: Any, limit: int) -> list[RawSearchResult]:
        rows = value if isinstance(value, list) else []
        return self._rows(rows, limit, "path_with_namespace", "web_url", "description", "last_activity_at")

    def _parse_stackoverflow(self, value: Any, limit: int) -> list[RawSearchResult]:
        rows = value.get("items", []) if isinstance(value, dict) else []
        return self._rows(rows, limit, "title", "link", "excerpt", "last_activity_date")

    def _parse_hacker_news(self, value: Any, limit: int) -> list[RawSearchResult]:
        rows = value.get("hits", []) if isinstance(value, dict) else []
        output = []
        for row in rows[:limit]:
            result = self._result(
                len(output) + 1,
                row.get("title") or row.get("story_title"),
                row.get("url") or row.get("story_url") or f"https://news.ycombinator.com/item?id={row.get('objectID', '')}",
                row.get("story_text") or row.get("comment_text"),
                row.get("created_at"),
            )
            if result:
                output.append(result)
        return output

    def _parse_lobsters(self, value: Any, limit: int) -> list[RawSearchResult]:
        rows = value if isinstance(value, list) else []
        return self._rows(rows, limit, "title", "url", "description", "created_at")

    def _parse_reddit(self, value: Any, limit: int) -> list[RawSearchResult]:
        rows = _list_at(value, "data", "children")
        output = []
        for wrapper in rows[:limit]:
            row = wrapper.get("data", {}) if isinstance(wrapper, dict) else {}
            permalink = row.get("permalink")
            url = row.get("url_overridden_by_dest") or (
                f"https://www.reddit.com{permalink}" if permalink else ""
            )
            result = self._result(
                len(output) + 1,
                row.get("title"),
                url,
                row.get("selftext"),
                row.get("created_utc"),
            )
            if result:
                output.append(result)
        return output

    def _parse_crossref(self, value: Any, limit: int) -> list[RawSearchResult]:
        rows = _list_at(value, "message", "items")
        output = []
        for row in rows[:limit]:
            title_value = row.get("title")
            title = title_value[0] if isinstance(title_value, list) and title_value else title_value
            result = self._result(
                len(output) + 1,
                title,
                row.get("URL"),
                _strip_html(row.get("abstract", "")),
                _crossref_date(row),
            )
            if result:
                output.append(result)
        return output

    def _parse_semantic_scholar(self, value: Any, limit: int) -> list[RawSearchResult]:
        rows = value.get("data", []) if isinstance(value, dict) else []
        return self._rows(rows, limit, "title", "url", "abstract", "year")

    def _parse_pubmed(self, value: Any, limit: int) -> list[RawSearchResult]:
        ids = _list_at(value, "esearchresult", "idlist")
        output = []
        for raw in ids[:limit]:
            identifier = _safe_text(raw, 32)
            result = self._result(
                len(output) + 1,
                f"PubMed record {identifier}",
                f"https://pubmed.ncbi.nlm.nih.gov/{identifier}/",
            )
            if result:
                output.append(result)
        return output

    def _parse_crates_io(self, value: Any, limit: int) -> list[RawSearchResult]:
        rows = value.get("crates", []) if isinstance(value, dict) else []
        output = []
        for row in rows[:limit]:
            name = row.get("name") or row.get("id")
            result = self._result(
                len(output) + 1,
                name,
                row.get("repository") or f"https://crates.io/crates/{urllib.parse.quote(str(name or ''))}",
                row.get("description"),
                row.get("updated_at"),
            )
            if result:
                output.append(result)
        return output

    def _parse_npm(self, value: Any, limit: int) -> list[RawSearchResult]:
        rows = value.get("objects", []) if isinstance(value, dict) else []
        output = []
        for wrapper in rows[:limit]:
            row = wrapper.get("package", {}) if isinstance(wrapper, dict) else {}
            links = row.get("links", {}) if isinstance(row.get("links"), dict) else {}
            result = self._result(
                len(output) + 1,
                row.get("name"),
                links.get("npm") or links.get("repository"),
                row.get("description"),
                row.get("date"),
            )
            if result:
                output.append(result)
        return output

    def _parse_mdn(self, value: Any, limit: int) -> list[RawSearchResult]:
        rows = value.get("documents", []) if isinstance(value, dict) else []
        output = []
        for row in rows[:limit]:
            location = row.get("mdn_url") or row.get("url")
            if isinstance(location, str) and location.startswith("/"):
                location = "https://developer.mozilla.org" + location
            result = self._result(
                len(output) + 1,
                row.get("title"),
                location,
                row.get("summary"),
            )
            if result:
                output.append(result)
        return output

    def _parse_atom(self, text: str, limit: int) -> list[RawSearchResult]:
        try:
            root = ET.fromstring(text)
        except ET.ParseError as exc:
            raise WebIntelligenceError("invalid_engine_response", "Atom feed is invalid", retryable=True) from exc
        ns = {"atom": "http://www.w3.org/2005/Atom"}
        output = []
        for entry in root.findall("atom:entry", ns)[:limit]:
            title = entry.findtext("atom:title", default="", namespaces=ns)
            summary = entry.findtext("atom:summary", default="", namespaces=ns)
            published = entry.findtext("atom:published", default="", namespaces=ns)
            link = ""
            for node in entry.findall("atom:link", ns):
                href = node.attrib.get("href", "")
                if href and node.attrib.get("rel", "alternate") == "alternate":
                    link = href
                    break
            result = self._result(len(output) + 1, title, link, summary, published)
            if result:
                output.append(result)
        return output

    def _rows(
        self,
        rows: Any,
        limit: int,
        title_key: str,
        url_key: str,
        excerpt_key: str,
        date_key: str,
    ) -> list[RawSearchResult]:
        output = []
        for row in (rows if isinstance(rows, list) else [])[:limit]:
            if not isinstance(row, dict):
                continue
            result = self._result(
                len(output) + 1,
                row.get(title_key),
                row.get(url_key),
                row.get(excerpt_key),
                row.get(date_key),
            )
            if result:
                output.append(result)
        return output


def _response_charset(content_type: str) -> str:
    match = re.search(r"charset=([A-Za-z0-9._-]+)", content_type or "", re.I)
    return match.group(1) if match else "utf-8"


def _strip_html(value: Any) -> str:
    return _safe_text(re.sub(r"<[^>]+>", " ", str(value or "")), 16_384)


def _list_at(value: Any, *keys: str) -> list[Any]:
    current = value
    for key in keys:
        if not isinstance(current, dict):
            return []
        current = current.get(key)
    return current if isinstance(current, list) else []


def _crossref_date(row: Mapping[str, Any]) -> str:
    for key in ("published-print", "published-online", "created", "issued"):
        node = row.get(key)
        if not isinstance(node, dict):
            continue
        parts = node.get("date-parts")
        if isinstance(parts, list) and parts and isinstance(parts[0], list):
            values = [str(item) for item in parts[0][:3]]
            return "-".join(values)
    return ""


class TinyLocalRanker:
    """Inspectable feature model used before an optional neural reranker."""

    DEFAULT_WEIGHTS = (
        -1.15, 2.35, 1.8, 1.25, 0.9, 0.55, 0.75, 1.1, 0.45, -1.4,
    )

    def __init__(self, model_path: Path | None = None) -> None:
        self.model_name = MODEL_NAME
        self.model_version = MODEL_VERSION
        self.weights = self.DEFAULT_WEIGHTS
        path = model_path or Path(__file__).resolve().parents[5] / "core" / "models" / "web-ranker-v1.json"
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            weights = tuple(float(item) for item in value.get("weights", []))
            if len(weights) == len(self.DEFAULT_WEIGHTS) and all(math.isfinite(item) for item in weights):
                self.model_name = str(value.get("model") or MODEL_NAME)
                self.model_version = int(value.get("version") or MODEL_VERSION)
                self.weights = weights
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            pass

    def score(self, features: Sequence[float]) -> float:
        values = (1.0, *features)
        if len(values) != len(self.weights):
            raise ValueError("Local ranker feature count does not match its model")
        linear = sum(weight * value for weight, value in zip(self.weights, values))
        return 1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, linear))))


class FeatureHashEmbedder:
    """Tiny multilingual local embedding fallback with no downloaded model."""

    def __init__(self, dimensions: int = DEFAULT_VECTOR_DIMENSIONS) -> None:
        if dimensions < 32 or dimensions > 2_048:
            raise ValueError("Embedding dimensions are outside the supported range")
        self.dimensions = dimensions
        self.model_id = f"signalasi-feature-hash-{dimensions}-v1"

    def embed(self, value: str) -> tuple[float, ...]:
        normalized = unicodedata.normalize("NFKC", value).lower()
        features = _tokens(normalized)
        compact = re.sub(r"\s+", " ", normalized)
        features.extend(
            compact[index:index + 3]
            for index in range(max(0, len(compact) - 2))
            if " " not in compact[index:index + 3]
        )
        vector = [0.0] * self.dimensions
        for feature, count in Counter(features).items():
            digest = hashlib.blake2b(feature.encode("utf-8"), digest_size=8).digest()
            raw = int.from_bytes(digest, "big")
            index = raw % self.dimensions
            sign = -1.0 if raw & (1 << 63) else 1.0
            vector[index] += sign * (1.0 + math.log1p(count))
        norm = math.sqrt(sum(item * item for item in vector)) or 1.0
        return tuple(item / norm for item in vector)

    @staticmethod
    def cosine(left: Sequence[float], right: Sequence[float]) -> float:
        if len(left) != len(right):
            return 0.0
        return max(-1.0, min(1.0, sum(a * b for a, b in zip(left, right))))

    def encode(self, vector: Sequence[float]) -> bytes:
        packed = struct.pack(f"<{len(vector)}f", *vector)
        return zlib.compress(packed, level=6)

    def decode(self, raw: bytes) -> tuple[float, ...]:
        unpacked = zlib.decompress(raw)
        if len(unpacked) != self.dimensions * 4:
            raise ValueError("Stored embedding has an invalid size")
        return tuple(struct.unpack(f"<{self.dimensions}f", unpacked))


def _lexical_alignment(query: str, title: str, excerpt: str) -> tuple[float, float, float]:
    query_tokens = set(_tokens(query))
    title_tokens = set(_tokens(title))
    body_tokens = set(_tokens(excerpt))
    if not query_tokens:
        return 0.0, 0.0, 0.0
    title_overlap = len(query_tokens & title_tokens) / len(query_tokens)
    body_overlap = len(query_tokens & body_tokens) / len(query_tokens)
    exactness = 1.0 if unicodedata.normalize("NFKC", query).casefold() in (
        unicodedata.normalize("NFKC", title).casefold()
    ) else title_overlap
    return min(1.0, 0.7 * title_overlap + 0.3 * body_overlap), exactness, max(title_overlap, body_overlap)


def _freshness_score(value: str, now: dt.datetime | None = None) -> float:
    if not value:
        return 0.35
    now = now or dt.datetime.now(dt.timezone.utc)
    raw = str(value).strip()
    if raw.isdigit():
        number = int(raw)
        if number > 10_000_000_000:
            number //= 1_000
        with contextlib.suppress(ValueError, OSError, OverflowError):
            parsed = dt.datetime.fromtimestamp(number, tz=dt.timezone.utc)
            return _freshness_decay(now, parsed)
    with contextlib.suppress(ValueError):
        parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return _freshness_decay(now, parsed)
    year = re.search(r"\b(19|20)\d{2}\b", raw)
    if year:
        age = max(0, now.year - int(year.group(0)))
        return max(0.1, math.exp(-age / 4.0))
    return 0.35


def _freshness_decay(now: dt.datetime, value: dt.datetime) -> float:
    days = max(0.0, (now - value).total_seconds() / 86_400.0)
    return max(0.05, math.exp(-days / 365.0))


def _url_quality(url: str) -> float:
    try:
        parsed = urllib.parse.urlsplit(url)
    except ValueError:
        return 0.0
    value = 0.5
    if parsed.scheme == "https":
        value += 0.15
    if not parsed.query:
        value += 0.1
    depth = len([part for part in parsed.path.split("/") if part])
    value += max(0.0, 0.2 - depth * 0.025)
    if len(url) > 250:
        value -= 0.2
    return max(0.0, min(1.0, value))


class SearchFusion:
    def __init__(self, ranker: TinyLocalRanker | None = None, rrf_k: int = 60) -> None:
        self.ranker = ranker or TinyLocalRanker()
        self.rrf_k = max(1, int(rrf_k))
        self._specs = {spec.engine_id: spec for spec in ENGINE_SPECS}

    def fuse(
        self,
        query: str,
        groups: Sequence[Sequence[RawSearchResult]],
        *,
        limit: int,
    ) -> list[FusedSearchResult]:
        merged: dict[str, FusedSearchResult] = {}
        for group in groups:
            for raw in group:
                normalized = canonical_url(raw.url)
                if not normalized or not urllib.parse.urlsplit(normalized).hostname:
                    continue
                current = merged.get(normalized)
                spec = self._specs.get(raw.engine_id)
                weight = spec.weight if spec else 1.0
                authority = spec.authority if spec else 0.5
                if current is None:
                    current = FusedSearchResult(
                        title=raw.title,
                        url=normalized,
                        excerpt=raw.excerpt,
                        vertical=raw.vertical,
                        published_at=raw.published_at,
                        authority=authority,
                    )
                    merged[normalized] = current
                else:
                    if len(raw.title) > len(current.title) and len(raw.title) < 2_048:
                        current.title = raw.title
                    if len(raw.excerpt) > len(current.excerpt):
                        current.excerpt = raw.excerpt
                    if not current.published_at and raw.published_at:
                        current.published_at = raw.published_at
                    if current.vertical == "general" and raw.vertical != "general":
                        current.vertical = raw.vertical
                    current.authority = max(current.authority, authority)
                previous = current.engine_ranks.get(raw.engine_id)
                current.engine_ranks[raw.engine_id] = min(previous, raw.rank) if previous else raw.rank
                current.engine_weights[raw.engine_id] = weight

        maximum_engines = max(1, len({engine for item in merged.values() for engine in item.engine_ranks}))
        maximum_rrf = 1.0 / (self.rrf_k + 1)
        for item in merged.values():
            raw_rrf = sum(
                item.engine_weights.get(engine_id, 1.0) / (self.rrf_k + rank)
                for engine_id, rank in item.engine_ranks.items()
            )
            reciprocal_rank = min(1.0, raw_rrf / maximum_rrf)
            lexical, exactness, coverage = _lexical_alignment(query, item.title, item.excerpt)
            consensus = min(1.0, len(item.engine_ranks) / min(5, maximum_engines))
            freshness = _freshness_score(item.published_at)
            url_quality = _url_quality(item.url)
            duplicate_penalty = max(0.0, (len(item.engine_ranks) - 8) / 16.0)
            local_model = self.ranker.score((
                reciprocal_rank,
                lexical,
                consensus,
                item.authority,
                freshness,
                exactness,
                coverage,
                url_quality,
                duplicate_penalty,
            ))
            final = (
                0.28 * reciprocal_rank
                + 0.21 * lexical
                + 0.14 * consensus
                + 0.10 * item.authority
                + 0.07 * freshness
                + 0.20 * local_model
            )
            item.score = {
                "final": max(0.0, min(1.0, final)),
                "reciprocal_rank": reciprocal_rank,
                "lexical": lexical,
                "consensus": consensus,
                "authority": item.authority,
                "freshness": freshness,
                "local_model": local_model,
            }
        return sorted(
            merged.values(),
            key=lambda item: (
                item.score.get("final", 0.0),
                len(item.engine_ranks),
                item.authority,
            ),
            reverse=True,
        )[:limit]


@dataclass(frozen=True)
class CachedDocument:
    url: str
    title: str
    content: str
    content_type: str
    content_sha256: str
    retrieved_at_millis: int
    expires_at_millis: int
    links: tuple[str, ...]
    metadata: Mapping[str, Any]
    vector: tuple[float, ...]


class WebIntelligenceStore:
    def __init__(
        self,
        path: Path,
        *,
        embedder: FeatureHashEmbedder | None = None,
        now: Callable[[], float] = time.time,
    ) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.embedder = embedder or FeatureHashEmbedder()
        self.now = now
        self._lock = threading.RLock()
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(str(self.path), timeout=10)
        connection.row_factory = sqlite3.Row
        return connection

    @contextlib.contextmanager
    def _connection(self):
        connection = self._connect()
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _initialize(self) -> None:
        with self._lock, self._connection() as connection:
            connection.executescript(
                """
                PRAGMA journal_mode=WAL;
                PRAGMA synchronous=NORMAL;
                CREATE TABLE IF NOT EXISTS documents (
                    url TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    content TEXT NOT NULL,
                    content_type TEXT NOT NULL,
                    content_sha256 TEXT NOT NULL,
                    retrieved_at_millis INTEGER NOT NULL,
                    expires_at_millis INTEGER NOT NULL,
                    links_json TEXT NOT NULL,
                    metadata_json TEXT NOT NULL,
                    embedding_model TEXT NOT NULL,
                    embedding BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS documents_retrieved_idx
                    ON documents(retrieved_at_millis DESC);
                CREATE TABLE IF NOT EXISTS searches (
                    cache_key TEXT PRIMARY KEY,
                    query TEXT NOT NULL,
                    response_json TEXT NOT NULL,
                    created_at_millis INTEGER NOT NULL,
                    expires_at_millis INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS searches_expires_idx ON searches(expires_at_millis);
                CREATE TABLE IF NOT EXISTS watches (
                    watch_id TEXT PRIMARY KEY,
                    url TEXT NOT NULL,
                    interval_minutes INTEGER NOT NULL,
                    enabled INTEGER NOT NULL,
                    last_checked_at_millis INTEGER NOT NULL,
                    last_changed_at_millis INTEGER NOT NULL,
                    last_sha256 TEXT NOT NULL,
                    created_at_millis INTEGER NOT NULL,
                    updated_at_millis INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS source_health (
                    source_id TEXT PRIMARY KEY,
                    attempts INTEGER NOT NULL,
                    successes INTEGER NOT NULL,
                    empty_responses INTEGER NOT NULL,
                    failures INTEGER NOT NULL,
                    consecutive_failures INTEGER NOT NULL,
                    ewma_latency_millis REAL NOT NULL,
                    ewma_result_count REAL NOT NULL,
                    last_status TEXT NOT NULL,
                    last_attempt_at_millis INTEGER NOT NULL,
                    last_success_at_millis INTEGER NOT NULL,
                    circuit_open_until_millis INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS source_health_circuit_idx
                    ON source_health(circuit_open_until_millis);
                """
            )

    def put_document(
        self,
        *,
        url: str,
        title: str,
        content: str,
        content_type: str,
        links: Sequence[str],
        metadata: Mapping[str, Any],
        ttl_seconds: int = DEFAULT_CACHE_TTL_SECONDS,
    ) -> CachedDocument:
        now_millis = int(self.now() * 1_000)
        clean_content = content[:MAX_CONTENT_CHARS]
        digest = hashlib.sha256(clean_content.encode("utf-8")).hexdigest()
        vector = self.embedder.embed(f"{title}\n{clean_content[:64_000]}")
        document = CachedDocument(
            url=canonical_url(url),
            title=title[:2_048],
            content=clean_content,
            content_type=content_type[:256],
            content_sha256=digest,
            retrieved_at_millis=now_millis,
            expires_at_millis=now_millis + max(60, ttl_seconds) * 1_000,
            links=tuple(dict.fromkeys(links))[:MAX_LINKS],
            metadata=dict(metadata),
            vector=vector,
        )
        with self._lock, self._connection() as connection:
            connection.execute(
                """
                INSERT INTO documents (
                    url, title, content, content_type, content_sha256,
                    retrieved_at_millis, expires_at_millis, links_json,
                    metadata_json, embedding_model, embedding
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(url) DO UPDATE SET
                    title=excluded.title,
                    content=excluded.content,
                    content_type=excluded.content_type,
                    content_sha256=excluded.content_sha256,
                    retrieved_at_millis=excluded.retrieved_at_millis,
                    expires_at_millis=excluded.expires_at_millis,
                    links_json=excluded.links_json,
                    metadata_json=excluded.metadata_json,
                    embedding_model=excluded.embedding_model,
                    embedding=excluded.embedding
                """,
                (
                    document.url,
                    document.title,
                    document.content,
                    document.content_type,
                    document.content_sha256,
                    document.retrieved_at_millis,
                    document.expires_at_millis,
                    json.dumps(document.links, ensure_ascii=False),
                    json.dumps(document.metadata, ensure_ascii=False),
                    self.embedder.model_id,
                    self.embedder.encode(vector),
                ),
            )
        return document

    def get_document(self, url: str, *, allow_stale: bool = False) -> CachedDocument | None:
        with self._lock, self._connection() as connection:
            row = connection.execute(
                "SELECT * FROM documents WHERE url = ?",
                (canonical_url(url),),
            ).fetchone()
        document = self._decode_document(row)
        if document is None:
            return None
        if not allow_stale and document.expires_at_millis < int(self.now() * 1_000):
            return None
        return document

    def similar(self, query: str, limit: int = 10) -> list[tuple[CachedDocument, float]]:
        target = self.embedder.embed(query)
        with self._lock, self._connection() as connection:
            rows = connection.execute(
                "SELECT * FROM documents ORDER BY retrieved_at_millis DESC LIMIT 2000"
            ).fetchall()
        values = []
        for row in rows:
            document = self._decode_document(row)
            if document is None:
                continue
            score = (self.embedder.cosine(target, document.vector) + 1.0) / 2.0
            values.append((document, score))
        return sorted(values, key=lambda item: item[1], reverse=True)[: max(1, min(100, limit))]

    def put_search(self, key: str, query: str, response: Mapping[str, Any], ttl_seconds: int) -> None:
        now_millis = int(self.now() * 1_000)
        with self._lock, self._connection() as connection:
            connection.execute(
                """
                INSERT INTO searches(cache_key, query, response_json, created_at_millis, expires_at_millis)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(cache_key) DO UPDATE SET
                    query=excluded.query,
                    response_json=excluded.response_json,
                    created_at_millis=excluded.created_at_millis,
                    expires_at_millis=excluded.expires_at_millis
                """,
                (
                    key,
                    query[:MAX_QUERY_CHARS],
                    json.dumps(response, ensure_ascii=False, separators=(",", ":")),
                    now_millis,
                    now_millis + max(60, ttl_seconds) * 1_000,
                ),
            )

    def get_search(self, key: str) -> dict[str, Any] | None:
        with self._lock, self._connection() as connection:
            row = connection.execute(
                "SELECT response_json, expires_at_millis FROM searches WHERE cache_key = ?",
                (key,),
            ).fetchone()
        if not row or int(row["expires_at_millis"]) < int(self.now() * 1_000):
            return None
        with contextlib.suppress(json.JSONDecodeError, TypeError):
            value = json.loads(row["response_json"])
            return value if isinstance(value, dict) else None
        return None

    def stats(self) -> dict[str, Any]:
        now_millis = int(self.now() * 1_000)
        with self._lock, self._connection() as connection:
            documents = connection.execute(
                "SELECT COUNT(*) AS count, COALESCE(SUM(LENGTH(content)), 0) AS bytes FROM documents"
            ).fetchone()
            searches = connection.execute("SELECT COUNT(*) AS count FROM searches").fetchone()
            watches = connection.execute("SELECT COUNT(*) AS count FROM watches").fetchone()
            source_health = connection.execute(
                """
                SELECT COUNT(*) AS count,
                       COALESCE(SUM(CASE WHEN circuit_open_until_millis > ? THEN 1 ELSE 0 END), 0)
                           AS circuits_open
                FROM source_health
                """,
                (now_millis,),
            ).fetchone()
        return {
            "entry_count": int(documents["count"]),
            "bytes": int(documents["bytes"]),
            "search_count": int(searches["count"]),
            "watch_count": int(watches["count"]),
            "source_health_count": int(source_health["count"]),
            "source_circuits_open": int(source_health["circuits_open"]),
            "embedding_model": self.embedder.model_id,
        }

    def clear(self, *, expired_only: bool = False) -> dict[str, int]:
        with self._lock, self._connection() as connection:
            if expired_only:
                now_millis = int(self.now() * 1_000)
                documents = connection.execute(
                    "DELETE FROM documents WHERE expires_at_millis < ?", (now_millis,)
                ).rowcount
                searches = connection.execute(
                    "DELETE FROM searches WHERE expires_at_millis < ?", (now_millis,)
                ).rowcount
            else:
                documents = connection.execute("DELETE FROM documents").rowcount
                searches = connection.execute("DELETE FROM searches").rowcount
        return {"documents_removed": max(0, documents), "searches_removed": max(0, searches)}

    def source_health(self, source_ids: Sequence[str] = ()) -> dict[str, SourceHealth]:
        clean_ids = tuple(dict.fromkeys(str(item) for item in source_ids if str(item)))
        with self._lock, self._connection() as connection:
            if clean_ids:
                placeholders = ",".join("?" for _ in clean_ids)
                rows = connection.execute(
                    f"SELECT * FROM source_health WHERE source_id IN ({placeholders})",
                    clean_ids,
                ).fetchall()
            else:
                rows = connection.execute(
                    "SELECT * FROM source_health ORDER BY source_id"
                ).fetchall()
        return {
            health.source_id: health
            for row in rows
            if (health := self._decode_source_health(row)) is not None
        }

    def record_source_receipt(self, receipt: EngineReceipt) -> SourceHealth:
        now_millis = int(self.now() * 1_000)
        with self._lock, self._connection() as connection:
            row = connection.execute(
                "SELECT * FROM source_health WHERE source_id = ?",
                (receipt.source_id,),
            ).fetchone()
            previous = self._decode_source_health(row) or SourceHealth(receipt.source_id)
            current = evolve_source_health(previous, receipt, now_millis)
            connection.execute(
                """
                INSERT INTO source_health (
                    source_id, attempts, successes, empty_responses, failures,
                    consecutive_failures, ewma_latency_millis, ewma_result_count,
                    last_status, last_attempt_at_millis, last_success_at_millis,
                    circuit_open_until_millis
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(source_id) DO UPDATE SET
                    attempts=excluded.attempts,
                    successes=excluded.successes,
                    empty_responses=excluded.empty_responses,
                    failures=excluded.failures,
                    consecutive_failures=excluded.consecutive_failures,
                    ewma_latency_millis=excluded.ewma_latency_millis,
                    ewma_result_count=excluded.ewma_result_count,
                    last_status=excluded.last_status,
                    last_attempt_at_millis=excluded.last_attempt_at_millis,
                    last_success_at_millis=excluded.last_success_at_millis,
                    circuit_open_until_millis=excluded.circuit_open_until_millis
                """,
                (
                    current.source_id,
                    current.attempts,
                    current.successes,
                    current.empty_responses,
                    current.failures,
                    current.consecutive_failures,
                    current.ewma_latency_millis,
                    current.ewma_result_count,
                    current.last_status,
                    current.last_attempt_at_millis,
                    current.last_success_at_millis,
                    current.circuit_open_until_millis,
                ),
            )
        return current

    def reset_source_health(self) -> int:
        with self._lock, self._connection() as connection:
            removed = connection.execute("DELETE FROM source_health").rowcount
        return max(0, removed)

    @staticmethod
    def _decode_source_health(row: sqlite3.Row | None) -> SourceHealth | None:
        if row is None:
            return None
        return SourceHealth(
            source_id=str(row["source_id"]),
            attempts=int(row["attempts"]),
            successes=int(row["successes"]),
            empty_responses=int(row["empty_responses"]),
            failures=int(row["failures"]),
            consecutive_failures=int(row["consecutive_failures"]),
            ewma_latency_millis=float(row["ewma_latency_millis"]),
            ewma_result_count=float(row["ewma_result_count"]),
            last_status=str(row["last_status"]),
            last_attempt_at_millis=int(row["last_attempt_at_millis"]),
            last_success_at_millis=int(row["last_success_at_millis"]),
            circuit_open_until_millis=int(row["circuit_open_until_millis"]),
        )

    def upsert_watch(
        self,
        watch_id: str,
        url: str,
        interval_minutes: int,
        *,
        enabled: bool = True,
    ) -> dict[str, Any]:
        now_millis = int(self.now() * 1_000)
        clean_id = _identifier(watch_id or f"watch-{uuid.uuid4().hex[:20]}")
        clean_url = canonical_url(url)
        interval = max(15, min(10_080, int(interval_minutes)))
        with self._lock, self._connection() as connection:
            connection.execute(
                """
                INSERT INTO watches (
                    watch_id, url, interval_minutes, enabled, last_checked_at_millis,
                    last_changed_at_millis, last_sha256, created_at_millis, updated_at_millis
                ) VALUES (?, ?, ?, ?, 0, 0, '', ?, ?)
                ON CONFLICT(watch_id) DO UPDATE SET
                    url=excluded.url,
                    interval_minutes=excluded.interval_minutes,
                    enabled=excluded.enabled,
                    updated_at_millis=excluded.updated_at_millis
                """,
                (clean_id, clean_url, interval, int(enabled), now_millis, now_millis),
            )
        return self.get_watch(clean_id) or {}

    def get_watch(self, watch_id: str) -> dict[str, Any] | None:
        with self._lock, self._connection() as connection:
            row = connection.execute(
                "SELECT * FROM watches WHERE watch_id = ?", (_identifier(watch_id),)
            ).fetchone()
        return self._watch_value(row)

    def list_watches(self) -> list[dict[str, Any]]:
        with self._lock, self._connection() as connection:
            rows = connection.execute("SELECT * FROM watches ORDER BY updated_at_millis DESC").fetchall()
        return [value for row in rows if (value := self._watch_value(row)) is not None]

    def remove_watch(self, watch_id: str) -> bool:
        with self._lock, self._connection() as connection:
            return connection.execute(
                "DELETE FROM watches WHERE watch_id = ?", (_identifier(watch_id),)
            ).rowcount > 0

    def update_watch_result(self, watch_id: str, content_sha256: str, *, changed: bool) -> dict[str, Any]:
        now_millis = int(self.now() * 1_000)
        with self._lock, self._connection() as connection:
            connection.execute(
                """
                UPDATE watches SET
                    last_checked_at_millis=?,
                    last_changed_at_millis=CASE WHEN ? THEN ? ELSE last_changed_at_millis END,
                    last_sha256=?,
                    updated_at_millis=?
                WHERE watch_id=?
                """,
                (now_millis, int(changed), now_millis, content_sha256, now_millis, _identifier(watch_id)),
            )
        return self.get_watch(watch_id) or {}

    def _decode_document(self, row: sqlite3.Row | None) -> CachedDocument | None:
        if row is None:
            return None
        try:
            vector = self.embedder.decode(row["embedding"])
            links = tuple(json.loads(row["links_json"]))
            metadata = json.loads(row["metadata_json"])
            if not isinstance(metadata, dict):
                metadata = {}
            return CachedDocument(
                url=row["url"],
                title=row["title"],
                content=row["content"],
                content_type=row["content_type"],
                content_sha256=row["content_sha256"],
                retrieved_at_millis=int(row["retrieved_at_millis"]),
                expires_at_millis=int(row["expires_at_millis"]),
                links=links,
                metadata=metadata,
                vector=vector,
            )
        except (ValueError, TypeError, json.JSONDecodeError, zlib.error, struct.error):
            return None

    @staticmethod
    def _watch_value(row: sqlite3.Row | None) -> dict[str, Any] | None:
        if row is None:
            return None
        return {
            "watch_id": row["watch_id"],
            "url": row["url"],
            "interval_minutes": int(row["interval_minutes"]),
            "enabled": bool(row["enabled"]),
            "last_checked_at_millis": int(row["last_checked_at_millis"]),
            "last_changed_at_millis": int(row["last_changed_at_millis"]),
            "last_sha256": row["last_sha256"],
        }


def _identifier(value: str) -> str:
    clean = str(value or "").strip()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,95}", clean):
        raise WebIntelligenceError("invalid_id", "Identifier is invalid")
    return clean


class WebIntelligenceService:
    def __init__(
        self,
        state_root: Path,
        *,
        transport: WebTransport | None = None,
        browser_fetcher: Callable[[str, float], str | Mapping[str, Any]] | None = None,
        now: Callable[[], float] = time.time,
        max_workers: int = 8,
    ) -> None:
        self.state_root = Path(state_root)
        self.state_root.mkdir(parents=True, exist_ok=True)
        self.transport = transport or PublicWebTransport()
        self.browser_fetcher = browser_fetcher
        self.now = now
        self.max_workers = max(1, min(16, int(max_workers)))
        self.store = WebIntelligenceStore(self.state_root / "web-intelligence.sqlite3", now=now)
        self.fusion = SearchFusion()
        self.specs = {spec.engine_id: spec for spec in ENGINE_SPECS}
        self.engines = {
            spec.engine_id: SearchEngineAdapter(spec, self.transport)
            for spec in ENGINE_SPECS
        }

    def invoke(self, operation: str, arguments: Mapping[str, Any]) -> dict[str, Any]:
        handler = getattr(self, str(operation or ""), None)
        if operation not in set(TOOL_OPERATIONS.values()) or not callable(handler):
            raise WebIntelligenceError("unknown_operation", f"Unknown web intelligence operation: {operation}")
        return handler(dict(arguments))

    def search(self, arguments: Mapping[str, Any]) -> dict[str, Any]:
        query = self._query(arguments)
        limit = _bounded_int(arguments.get("limit"), 10, 1, MAX_RESULTS)
        profile = str(arguments.get("profile") or "balanced").strip().lower()
        if profile not in SEARCH_PROFILES:
            raise WebIntelligenceError(
                "invalid_search_profile",
                f"Unsupported search profile: {profile}",
            )
        profile_fanout, profile_timeout = SEARCH_PROFILES[profile]
        fanout = _bounded_int(
            arguments.get("engine_fanout"),
            profile_fanout,
            1,
            MAX_ENGINE_FANOUT,
        )
        timeout_seconds = _bounded_float(
            arguments.get("timeout_seconds"),
            profile_timeout,
            1.0,
            60.0,
        )
        requested_engines = _string_list(arguments.get("engines"), limit=MAX_ENGINE_FANOUT, max_length=64)
        verticals = _string_list(arguments.get("verticals"), limit=10, max_length=32)
        freshness = str(arguments.get("freshness") or "any")
        use_cache = bool(arguments.get("use_cache", True))
        selection = self._select_engines(query, fanout, requested_engines, verticals)
        engine_ids = list(selection.selected)
        cache_key = hashlib.sha256(json.dumps(
            {
                "query": query,
                "limit": limit,
                "engines": engine_ids,
                "freshness": freshness,
                "profile": profile,
                "version": MODEL_VERSION,
            },
            sort_keys=True,
            ensure_ascii=False,
        ).encode("utf-8")).hexdigest()
        if use_cache:
            cached = self.store.get_search(cache_key)
            if cached:
                cached = json.loads(json.dumps(cached))
                cached["request_id"] = self._request_id(arguments)
                cached["started_at_millis"] = self._millis()
                cached["completed_at_millis"] = self._millis()
                cached.setdefault("cache", {})["hit"] = True
                cached.setdefault("metadata", {})["cache_hit"] = True
                cached["metadata"]["profile"] = profile
                cached["metadata"]["source_health"] = self._source_health_values(engine_ids)
                cached["metadata"]["circuits_skipped"] = [
                    item.public(self._millis()) for item in selection.skipped
                ]
                return cached

        started_at = self._millis()
        started_monotonic = time.monotonic()
        raw_groups: list[list[RawSearchResult]] = []
        receipts: list[EngineReceipt] = []
        futures: dict[concurrent.futures.Future[list[RawSearchResult]], tuple[str, float]] = {}
        per_engine_timeout = max(1.0, min(8.0, timeout_seconds * 0.8))
        if engine_ids:
            with concurrent.futures.ThreadPoolExecutor(
                max_workers=min(self.max_workers, len(engine_ids)),
                thread_name_prefix="signalasi-web",
            ) as executor:
                for engine_id in engine_ids:
                    adapter = self.engines[engine_id]
                    submitted = time.monotonic()
                    future = executor.submit(adapter.search, query, min(20, max(limit, 8)), per_engine_timeout)
                    futures[future] = (engine_id, submitted)
                deadline = started_monotonic + timeout_seconds
                pending = set(futures)
                while pending and time.monotonic() < deadline:
                    wait = max(0.01, deadline - time.monotonic())
                    done, pending = concurrent.futures.wait(
                        pending,
                        timeout=wait,
                        return_when=concurrent.futures.FIRST_COMPLETED,
                    )
                    if not done:
                        break
                    for future in done:
                        engine_id, submitted = futures[future]
                        duration = int((time.monotonic() - submitted) * 1_000)
                        try:
                            rows = future.result()
                            raw_groups.append(rows)
                            receipts.append(EngineReceipt(
                                engine_id,
                                "completed" if rows else "empty",
                                duration,
                                len(rows),
                            ))
                        except WebIntelligenceError as exc:
                            receipts.append(EngineReceipt(
                                engine_id,
                                _receipt_status(exc),
                                duration,
                                0,
                                exc.code,
                                str(exc),
                                exc.retryable,
                            ))
                        except Exception as exc:  # Defensive isolation between engines.
                            receipts.append(EngineReceipt(
                                engine_id,
                                "failed",
                                duration,
                                0,
                                "engine_failed",
                                str(exc),
                                True,
                            ))
                for future in pending:
                    engine_id, submitted = futures[future]
                    future.cancel()
                    receipts.append(EngineReceipt(
                        engine_id,
                        "timeout",
                        int((time.monotonic() - submitted) * 1_000),
                        0,
                        "engine_timeout",
                        "Search source exceeded the shared request deadline",
                        True,
                    ))

        for receipt in receipts:
            self.store.record_source_receipt(receipt)

        fused = self.fusion.fuse(query, raw_groups, limit=limit)
        status = "completed" if fused and all(item.status in {"completed", "empty"} for item in receipts) else (
            "partial" if fused else "failed"
        )
        result = self._base("search", arguments, started_at, status)
        result.update({
            "query": query,
            "results": [item.public(index + 1) for index, item in enumerate(fused)],
            "receipts": [receipt.public() for receipt in sorted(receipts, key=lambda item: item.source_id)],
            "cache": {
                "hit": False,
                **self.store.stats(),
                "expires_at_millis": self._millis() + DEFAULT_CACHE_TTL_SECONDS * 1_000,
            },
            "metadata": {
                "engine_catalog_size": len(ENGINE_SPECS),
                "engines_requested": engine_ids,
                "engines_completed": sum(receipt.status == "completed" for receipt in receipts),
                "engine_failures": sum(receipt.status not in {"completed", "empty"} for receipt in receipts),
                "profile": profile,
                "engine_fanout": fanout,
                "timeout_seconds": timeout_seconds,
                "source_selection": (
                    "explicit_sources" if selection.explicit else "adaptive_health_weighted"
                ),
                "source_health": self._source_health_values(engine_ids),
                "circuits_skipped": [
                    item.public(self._millis()) for item in selection.skipped
                ],
                "fusion": "weighted_rrf_plus_local_ranker",
                "ranker_model": self.fusion.ranker.model_name,
                "ranker_version": self.fusion.ranker.model_version,
                "freshness": freshness,
                "elapsed_millis": max(0, int((time.monotonic() - started_monotonic) * 1_000)),
            },
        })
        if fused:
            self.store.put_search(cache_key, query, result, DEFAULT_CACHE_TTL_SECONDS)
        return result

    def fetch(self, arguments: Mapping[str, Any]) -> dict[str, Any]:
        started_at = self._millis()
        document, cache_hit, receipt = self._fetch_document(
            self._url(arguments),
            timeout_seconds=_bounded_float(arguments.get("timeout_seconds"), DEFAULT_TIMEOUT_SECONDS, 1.0, 120.0),
            force=bool(arguments.get("force", False)),
            max_bytes=_bounded_int(arguments.get("max_bytes"), MAX_FETCH_BYTES, 1_024, MAX_FETCH_BYTES),
            ttl_seconds=_bounded_int(arguments.get("cache_ttl_seconds"), DEFAULT_CACHE_TTL_SECONDS, 60, 30 * 24 * 60 * 60),
        )
        result = self._base("fetch", arguments, started_at, "completed")
        result.update({
            "url": document.url,
            "documents": [self._document_value(document)],
            "receipts": [receipt.public()],
            "cache": {
                "hit": cache_hit,
                **self.store.stats(),
                "expires_at_millis": document.expires_at_millis,
            },
            "metadata": {
                "fetch_tier": document.metadata.get("fetch_tier", "http"),
                "challenge_detected": bool(document.metadata.get("challenge_detected")),
            },
        })
        return result

    def crawl(self, arguments: Mapping[str, Any]) -> dict[str, Any]:
        started_at = self._millis()
        root_url = canonical_url(self._url(arguments))
        max_pages = _bounded_int(arguments.get("max_pages"), 20, 1, MAX_CRAWL_PAGES)
        max_depth = _bounded_int(arguments.get("max_depth"), 2, 0, MAX_CRAWL_DEPTH)
        timeout_seconds = _bounded_float(arguments.get("timeout_seconds"), 60.0, 1.0, 600.0)
        same_origin = bool(arguments.get("same_origin", True))
        include_pattern = _optional_regex(arguments.get("include_pattern"))
        exclude_pattern = _optional_regex(arguments.get("exclude_pattern"))
        deadline = time.monotonic() + timeout_seconds
        queue: deque[tuple[str, int]] = deque([(root_url, 0)])
        queued = {root_url}
        documents: list[CachedDocument] = []
        receipts: list[EngineReceipt] = []
        root_origin = _origin(root_url)
        while queue and len(documents) < max_pages and time.monotonic() < deadline:
            url, depth = queue.popleft()
            if include_pattern and not include_pattern.search(url):
                continue
            if exclude_pattern and exclude_pattern.search(url):
                continue
            item_started = time.monotonic()
            try:
                document, _, receipt = self._fetch_document(
                    url,
                    timeout_seconds=max(1.0, min(15.0, deadline - time.monotonic())),
                    force=False,
                    max_bytes=MAX_FETCH_BYTES,
                    ttl_seconds=DEFAULT_CACHE_TTL_SECONDS,
                )
                documents.append(document)
                receipts.append(receipt)
                if depth < max_depth:
                    for link in document.links:
                        normalized = canonical_url(link)
                        if normalized in queued:
                            continue
                        if same_origin and _origin(normalized) != root_origin:
                            continue
                        queued.add(normalized)
                        queue.append((normalized, depth + 1))
            except WebIntelligenceError as exc:
                receipts.append(EngineReceipt(
                    f"crawl:{url[:48]}",
                    _receipt_status(exc),
                    int((time.monotonic() - item_started) * 1_000),
                    0,
                    exc.code,
                    str(exc),
                    exc.retryable,
                ))
        status = "completed" if documents and not queue else ("partial" if documents else "failed")
        result = self._base("crawl", arguments, started_at, status)
        result.update({
            "url": root_url,
            "documents": [self._document_value(item) for item in documents],
            "receipts": [item.public() for item in receipts],
            "cache": {"hit": False, **self.store.stats()},
            "metadata": {
                "pages_fetched": len(documents),
                "urls_discovered": len(queued),
                "remaining_queue": len(queue),
                "max_pages": max_pages,
                "max_depth": max_depth,
                "deadline_reached": time.monotonic() >= deadline,
            },
        })
        return result

    def extract(self, arguments: Mapping[str, Any]) -> dict[str, Any]:
        started_at = self._millis()
        if arguments.get("url"):
            document, cache_hit, receipt = self._fetch_document(
                self._url(arguments),
                timeout_seconds=_bounded_float(arguments.get("timeout_seconds"), DEFAULT_TIMEOUT_SECONDS, 1.0, 120.0),
                force=bool(arguments.get("force", False)),
                max_bytes=MAX_FETCH_BYTES,
                ttl_seconds=DEFAULT_CACHE_TTL_SECONDS,
            )
        else:
            content = _required_string(arguments.get("content"), "content", MAX_CONTENT_CHARS)
            title = _safe_text(arguments.get("title"), 2_048)
            url = _safe_text(arguments.get("source_url"), MAX_URL_CHARS) or "https://local.signalasi.invalid/content"
            document = self._document_from_content(url, title, content, "text/plain", [], {}, "local")
            cache_hit = False
            receipt = EngineReceipt("local_content", "completed", 0, 1)
        fields = _string_list(arguments.get("fields"), limit=100, max_length=128)
        structured = self._structured_extract(document, fields)
        result = self._base("extract", arguments, started_at, "completed")
        result.update({
            "url": document.url,
            "documents": [self._document_value(document)],
            "receipts": [receipt.public()],
            "cache": {"hit": cache_hit, **self.store.stats()},
            "metadata": {
                "structured": structured,
                "requested_fields": fields,
                "extraction_mode": "local_readability_and_metadata",
            },
        })
        return result

    def cache(self, arguments: Mapping[str, Any]) -> dict[str, Any]:
        started_at = self._millis()
        action = str(arguments.get("action") or "status")
        metadata: dict[str, Any]
        results: list[dict[str, Any]] = []
        documents: list[dict[str, Any]] = []
        if action == "status":
            metadata = self.store.stats()
        elif action == "query":
            query = self._query(arguments)
            matches = self.store.similar(query, _bounded_int(arguments.get("limit"), 10, 1, 100))
            results = [
                {
                    "citation_id": citation_id(document.url, document.content[:500]),
                    "title": document.title,
                    "url": document.url,
                    "excerpt": document.content[:1_000],
                    "published_at": "",
                    "language": detect_language(document.content),
                    "vertical": "local",
                    "engines": ["local_cache"],
                    "rank": index + 1,
                    "score": {
                        "final": score,
                        "reciprocal_rank": 0.0,
                        "lexical": 0.0,
                        "consensus": 0.0,
                        "authority": 1.0,
                        "freshness": 1.0,
                        "local_model": score,
                    },
                }
                for index, (document, score) in enumerate(matches)
            ]
            metadata = self.store.stats()
        elif action == "get":
            document = self.store.get_document(self._url(arguments), allow_stale=True)
            if document is None:
                raise WebIntelligenceError("cache_miss", "The requested URL is not in the local cache")
            documents = [self._document_value(document)]
            metadata = self.store.stats()
        elif action in {"clear", "clear_expired"}:
            metadata = {
                **self.store.stats(),
                **self.store.clear(expired_only=action == "clear_expired"),
            }
        elif action == "source_health":
            source_ids = _string_list(
                arguments.get("engines"),
                limit=MAX_ENGINE_FANOUT,
                max_length=64,
            )
            unknown = [item for item in source_ids if item not in self.engines]
            if unknown:
                raise WebIntelligenceError(
                    "unknown_engine",
                    f"Unknown search sources: {', '.join(unknown)}",
                )
            metadata = {
                **self.store.stats(),
                "source_health": self._source_health_values(source_ids),
            }
        elif action == "reset_source_health":
            removed = self.store.reset_source_health()
            metadata = {
                **self.store.stats(),
                "source_health_removed": removed,
            }
        else:
            raise WebIntelligenceError("invalid_cache_action", f"Unsupported cache action: {action}")
        result = self._base("cache", arguments, started_at, "completed")
        result.update({
            "query": _safe_text(arguments.get("query"), MAX_QUERY_CHARS),
            "results": results,
            "documents": documents,
            "receipts": [],
            "cache": {"hit": bool(results or documents), **self.store.stats()},
            "metadata": {"action": action, **metadata},
        })
        return result

    def find_similar(self, arguments: Mapping[str, Any]) -> dict[str, Any]:
        started_at = self._millis()
        if arguments.get("url"):
            document = self.store.get_document(self._url(arguments), allow_stale=True)
            if document is None:
                document, _, _ = self._fetch_document(
                    self._url(arguments),
                    timeout_seconds=DEFAULT_TIMEOUT_SECONDS,
                    force=False,
                    max_bytes=MAX_FETCH_BYTES,
                    ttl_seconds=DEFAULT_CACHE_TTL_SECONDS,
                )
            query = f"{document.title}\n{document.content[:32_000]}"
        else:
            query = self._query(arguments)
        limit = _bounded_int(arguments.get("limit"), 10, 1, 100)
        local_matches = self.store.similar(query, limit * 2)
        local_results = []
        excluded = canonical_url(_safe_text(arguments.get("url"), MAX_URL_CHARS)) if arguments.get("url") else ""
        for document, score in local_matches:
            if excluded and document.url == excluded:
                continue
            local_results.append(_similar_result(document, score, len(local_results) + 1))
            if len(local_results) >= limit:
                break
        if len(local_results) < max(3, limit // 2) and bool(arguments.get("search_web", True)):
            searched = self.search({
                "query": query[:MAX_QUERY_CHARS],
                "limit": limit,
                "engine_fanout": min(12, DEFAULT_ENGINE_FANOUT),
                "timeout_seconds": arguments.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS),
            })
            seen = {item["url"] for item in local_results}
            for item in searched.get("results", []):
                if item.get("url") not in seen and item.get("url") != excluded:
                    local_results.append(item)
                    seen.add(item.get("url"))
                if len(local_results) >= limit:
                    break
            receipts = searched.get("receipts", [])
        else:
            receipts = []
        result = self._base("find_similar", arguments, started_at, "completed" if local_results else "partial")
        result.update({
            "query": query[:MAX_QUERY_CHARS],
            "results": local_results[:limit],
            "receipts": receipts,
            "cache": {"hit": bool(local_matches), **self.store.stats()},
            "metadata": {"embedding_model": self.store.embedder.model_id},
        })
        return result

    def research(self, arguments: Mapping[str, Any]) -> dict[str, Any]:
        return self._run_research(arguments, autonomous=False)

    def agent(self, arguments: Mapping[str, Any]) -> dict[str, Any]:
        return self._run_research(arguments, autonomous=True)

    def diff(self, arguments: Mapping[str, Any]) -> dict[str, Any]:
        started_at = self._millis()
        url = self._url(arguments)
        previous = self.store.get_document(url, allow_stale=True)
        current, _, receipt = self._fetch_document(
            url,
            timeout_seconds=_bounded_float(arguments.get("timeout_seconds"), DEFAULT_TIMEOUT_SECONDS, 1.0, 120.0),
            force=True,
            max_bytes=MAX_FETCH_BYTES,
            ttl_seconds=DEFAULT_CACHE_TTL_SECONDS,
        )
        previous_text = previous.content if previous else ""
        changed = previous is None or previous.content_sha256 != current.content_sha256
        summary = ""
        if changed:
            summary = "\n".join(difflib.unified_diff(
                previous_text.splitlines(),
                current.content.splitlines(),
                fromfile="previous",
                tofile="current",
                lineterm="",
                n=2,
            ))[:32_768]
        result = self._base("diff", arguments, started_at, "completed")
        result.update({
            "url": current.url,
            "documents": [self._document_value(current)],
            "receipts": [receipt.public()],
            "cache": {"hit": previous is not None, **self.store.stats()},
            "diff": {
                "changed": changed,
                "previous_sha256": previous.content_sha256 if previous else "",
                "current_sha256": current.content_sha256,
                "summary": summary,
            },
            "metadata": {"previous_available": previous is not None},
        })
        return result

    def watch(self, arguments: Mapping[str, Any]) -> dict[str, Any]:
        started_at = self._millis()
        action = str(arguments.get("action") or "list")
        watch_value: dict[str, Any] = {}
        metadata: dict[str, Any] = {"action": action}
        receipts: list[dict[str, Any]] = []
        diff_value: dict[str, Any] | None = None
        if action == "create":
            watch_value = self.store.upsert_watch(
                str(arguments.get("watch_id") or f"watch-{uuid.uuid4().hex[:20]}"),
                self._url(arguments),
                _bounded_int(arguments.get("interval_minutes"), 60, 15, 10_080),
                enabled=bool(arguments.get("enabled", True)),
            )
        elif action == "list":
            metadata["watches"] = self.store.list_watches()
        elif action == "remove":
            removed = self.store.remove_watch(_required_string(arguments.get("watch_id"), "watch_id", 96))
            metadata["removed"] = removed
        elif action in {"check", "check_due"}:
            if action == "check":
                selected = [self.store.get_watch(_required_string(arguments.get("watch_id"), "watch_id", 96))]
            else:
                now_millis = self._millis()
                selected = [
                    item for item in self.store.list_watches()
                    if item["enabled"] and (
                        not item["last_checked_at_millis"]
                        or now_millis - item["last_checked_at_millis"] >= item["interval_minutes"] * 60_000
                    )
                ][:_bounded_int(arguments.get("limit"), 20, 1, 100)]
            checked = []
            for item in selected:
                if not item:
                    continue
                previous_hash = item.get("last_sha256", "")
                result = self.diff({"url": item["url"], "timeout_seconds": arguments.get("timeout_seconds", 30)})
                current_hash = result["diff"]["current_sha256"]
                changed = bool(previous_hash and previous_hash != current_hash)
                updated = self.store.update_watch_result(item["watch_id"], current_hash, changed=changed)
                checked.append({**updated, "changed": changed})
                receipts.extend(result.get("receipts", []))
                diff_value = result.get("diff")
                watch_value = updated
            metadata["checked"] = checked
        else:
            raise WebIntelligenceError("invalid_watch_action", f"Unsupported watch action: {action}")
        result = self._base("watch", arguments, started_at, "completed")
        result.update({
            "receipts": receipts,
            "watch": watch_value,
            "cache": {"hit": False, **self.store.stats()},
            "metadata": metadata,
        })
        if diff_value is not None:
            result["diff"] = diff_value
        return result

    def _run_research(self, arguments: Mapping[str, Any], *, autonomous: bool) -> dict[str, Any]:
        started_at = self._millis()
        query = self._query(arguments)
        max_rounds = _bounded_int(arguments.get("max_rounds"), 3 if autonomous else 2, 1, 8)
        source_budget = _bounded_int(arguments.get("source_budget"), 12 if autonomous else 8, 2, 40)
        timeout_seconds = _bounded_float(arguments.get("timeout_seconds"), 120.0, 5.0, 900.0)
        deadline = time.monotonic() + timeout_seconds
        subqueries = self._decompose_query(query, max_rounds)
        all_results: dict[str, dict[str, Any]] = {}
        all_receipts: list[dict[str, Any]] = []
        round_events: list[dict[str, Any]] = []
        queries_used: list[str] = []

        for round_index in range(max_rounds):
            if time.monotonic() >= deadline or len(all_results) >= source_budget * 3:
                break
            current_queries = subqueries[round_index:round_index + 1] if not autonomous else (
                subqueries[round_index * 2:round_index * 2 + 2] or [query]
            )
            for subquery in current_queries:
                if time.monotonic() >= deadline:
                    break
                queries_used.append(subquery)
                searched = self.search({
                    "query": subquery,
                    "limit": min(20, source_budget),
                    "engine_fanout": min(DEFAULT_ENGINE_FANOUT, 12 + round_index * 3),
                    "timeout_seconds": max(2.0, min(30.0, deadline - time.monotonic())),
                    "use_cache": True,
                })
                new_count = 0
                for item in searched.get("results", []):
                    url = canonical_url(item.get("url", ""))
                    if not url or url in all_results:
                        continue
                    all_results[url] = item
                    new_count += 1
                all_receipts.extend(searched.get("receipts", []))
                round_events.append({
                    "round": round_index + 1,
                    "query": subquery,
                    "new_results": new_count,
                    "total_results": len(all_results),
                })

        ranked = sorted(
            all_results.values(),
            key=lambda item: float((item.get("score") or {}).get("final") or 0),
            reverse=True,
        )
        documents: list[CachedDocument] = []
        fetch_receipts: list[dict[str, Any]] = []
        domains: set[str] = set()
        for item in ranked:
            if len(documents) >= source_budget or time.monotonic() >= deadline:
                break
            host = urllib.parse.urlsplit(item["url"]).hostname or ""
            if host in domains and len(domains) < min(5, source_budget):
                continue
            try:
                document, _, receipt = self._fetch_document(
                    item["url"],
                    timeout_seconds=max(1.0, min(20.0, deadline - time.monotonic())),
                    force=False,
                    max_bytes=MAX_FETCH_BYTES,
                    ttl_seconds=DEFAULT_CACHE_TTL_SECONDS,
                )
                if len(document.content) < 80:
                    continue
                documents.append(document)
                domains.add(host)
                fetch_receipts.append(receipt.public())
            except WebIntelligenceError as exc:
                fetch_receipts.append(EngineReceipt(
                    f"fetch:{host[:48]}",
                    _receipt_status(exc),
                    0,
                    0,
                    exc.code,
                    str(exc),
                    exc.retryable,
                ).public())

        brief, citations = self._evidence_brief(query, documents, ranked)
        enough_evidence = len(documents) >= min(3, source_budget) and len(domains) >= min(2, source_budget)
        status = "completed" if enough_evidence else ("partial" if documents or ranked else "failed")
        result = self._base("agent" if autonomous else "research", arguments, started_at, status)
        result.update({
            "query": query,
            "results": ranked[:source_budget * 2],
            "documents": [self._document_value(document) for document in documents],
            "brief": brief,
            "citations": citations,
            "receipts": all_receipts + fetch_receipts,
            "cache": {"hit": False, **self.store.stats()},
            "metadata": {
                "mode": "autonomous" if autonomous else "research",
                "rounds_completed": len({item["round"] for item in round_events}),
                "queries": queries_used,
                "events": round_events,
                "source_count": len(documents),
                "domain_count": len(domains),
                "evidence_sufficient": enough_evidence,
                "deadline_reached": time.monotonic() >= deadline,
                "synthesis": "deterministic_extract_then_selected_agent",
            },
        })
        return result

    def _fetch_document(
        self,
        url: str,
        *,
        timeout_seconds: float,
        force: bool,
        max_bytes: int,
        ttl_seconds: int,
    ) -> tuple[CachedDocument, bool, EngineReceipt]:
        normalized = canonical_url(url)
        if not force:
            cached = self.store.get_document(normalized)
            if cached is not None:
                return cached, True, EngineReceipt("local_cache", "completed", 0, 1)
        started = time.monotonic()
        response = self.transport.fetch(
            normalized,
            timeout_seconds=timeout_seconds,
            max_bytes=max_bytes,
        )
        content_type = response.headers.get("content-type", "").split(";", 1)[0].strip().lower()
        charset = _response_charset(response.headers.get("content-type", ""))
        raw_text = response.body.decode(charset, errors="replace")
        title = ""
        links: list[str] = []
        metadata: dict[str, Any] = {
            "fetch_tier": "http",
            "http_status": response.status,
            "http_duration_millis": response.duration_ms,
            "response_bytes": len(response.body),
        }
        if "html" in content_type or raw_text.lstrip().lower().startswith(("<!doctype html", "<html")):
            parser = ReadableHtmlParser(response.url)
            parser.feed(raw_text)
            title = parser.title or parser.metadata.get("og:title", "")
            text = parser.text
            links = parser.links
            metadata.update({
                "meta": parser.metadata,
                "json_ld": parser.json_ld[:20],
            })
        elif "json" in content_type:
            with contextlib.suppress(json.JSONDecodeError):
                raw_text = json.dumps(json.loads(raw_text), ensure_ascii=False, indent=2)
            text = raw_text[:MAX_CONTENT_CHARS]
        else:
            text = raw_text[:MAX_CONTENT_CHARS]

        challenge = self._challenge_reason(raw_text, text)
        if challenge and self.browser_fetcher is not None:
            try:
                rendered = self.browser_fetcher(normalized, timeout_seconds)
                if isinstance(rendered, Mapping):
                    text = _safe_text(rendered.get("text"), MAX_CONTENT_CHARS)
                    title = _safe_text(rendered.get("title"), 2_048) or title
                    links = _string_list(rendered.get("links"), limit=MAX_LINKS, max_length=MAX_URL_CHARS)
                else:
                    parser = ReadableHtmlParser(normalized)
                    parser.feed(str(rendered))
                    text = parser.text
                    title = parser.title or title
                    links = parser.links
                metadata["fetch_tier"] = "browser"
                metadata["challenge_detected"] = challenge
            except Exception as exc:
                metadata["browser_fallback_error"] = str(exc)[:500]
        elif challenge:
            metadata["challenge_detected"] = challenge

        if not text.strip():
            raise WebIntelligenceError(
                "empty_content",
                "The page returned no readable content",
                retryable=True,
                details={"url": normalized, "challenge": challenge},
            )
        document = self.store.put_document(
            url=response.url,
            title=title or urllib.parse.urlsplit(response.url).hostname or response.url,
            content=text,
            content_type=content_type or "text/plain",
            links=links,
            metadata=metadata,
            ttl_seconds=ttl_seconds,
        )
        return document, False, EngineReceipt(
            "browser" if metadata.get("fetch_tier") == "browser" else "bounded_http",
            "completed",
            int((time.monotonic() - started) * 1_000),
            1,
        )

    def _document_from_content(
        self,
        url: str,
        title: str,
        content: str,
        content_type: str,
        links: Sequence[str],
        metadata: Mapping[str, Any],
        fetch_tier: str,
    ) -> CachedDocument:
        clean = content[:MAX_CONTENT_CHARS]
        now_millis = self._millis()
        return CachedDocument(
            url=url,
            title=title,
            content=clean,
            content_type=content_type,
            content_sha256=hashlib.sha256(clean.encode("utf-8")).hexdigest(),
            retrieved_at_millis=now_millis,
            expires_at_millis=now_millis + DEFAULT_CACHE_TTL_SECONDS * 1_000,
            links=tuple(links),
            metadata={**metadata, "fetch_tier": fetch_tier},
            vector=self.store.embedder.embed(f"{title}\n{clean}"),
        )

    def _document_value(self, document: CachedDocument) -> dict[str, Any]:
        return {
            "citation_id": citation_id(document.url, document.content[:1_000]),
            "url": document.url,
            "title": document.title,
            "content": document.content,
            "content_sha256": document.content_sha256,
            "content_type": document.content_type,
            "language": detect_language(document.content),
            "links": list(document.links),
            "retrieved_at_millis": document.retrieved_at_millis,
            "fetch_tier": str(document.metadata.get("fetch_tier") or "cache"),
        }

    def _structured_extract(self, document: CachedDocument, fields: Sequence[str]) -> dict[str, Any]:
        metadata = document.metadata.get("meta")
        meta = metadata if isinstance(metadata, dict) else {}
        json_ld = document.metadata.get("json_ld")
        available = {
            "title": document.title,
            "description": meta.get("description") or meta.get("og:description") or document.content[:500],
            "canonical_url": meta.get("og:url") or document.url,
            "site_name": meta.get("og:site_name") or urllib.parse.urlsplit(document.url).hostname,
            "author": meta.get("author") or "",
            "published_at": meta.get("article:published_time") or "",
            "language": detect_language(document.content),
            "content_sha256": document.content_sha256,
            "links": list(document.links),
            "json_ld": json_ld if isinstance(json_ld, list) else [],
        }
        if not fields:
            return available
        return {field: available.get(field) for field in fields}

    def _select_engines(
        self,
        query: str,
        fanout: int,
        requested: Sequence[str],
        verticals: Sequence[str],
    ) -> SourceSelection:
        if requested:
            unknown = [item for item in requested if item not in self.engines]
            if unknown:
                raise WebIntelligenceError(
                    "unknown_engine",
                    f"Unknown search sources: {', '.join(unknown)}",
                )
            return SourceSelection(
                tuple(list(dict.fromkeys(requested))[:fanout]),
                (),
                explicit=True,
            )
        language = detect_language(query)
        desired = set(verticals or self._infer_verticals(query))
        now_millis = self._millis()
        health_by_source = self.store.source_health()
        scored: list[tuple[float, int, str]] = []
        skipped: list[SourceHealth] = []
        for index, spec in enumerate(ENGINE_SPECS):
            if not spec.default_enabled:
                continue
            health = health_by_source.get(spec.engine_id, SourceHealth(spec.engine_id))
            if health.circuit_state(now_millis) == "open":
                skipped.append(health)
                continue
            score = spec.weight
            if spec.vertical in desired:
                score += 2.5
            if spec.vertical == "general":
                score += 1.0
            if "*" in spec.languages or language in spec.languages:
                score += 0.8
            elif spec.languages != ("*",):
                score -= 1.5
            score += spec.authority * 0.5
            score += health.routing_score()
            scored.append((score, -index, spec.engine_id))
        ranked = sorted(scored, reverse=True)
        selected: list[str] = []
        for vertical in sorted(desired):
            match = next(
                (
                    item[2]
                    for item in ranked
                    if self.specs[item[2]].vertical == vertical and item[2] not in selected
                ),
                None,
            )
            if match:
                selected.append(match)
            if len(selected) >= fanout:
                break
        for _, _, source_id in ranked:
            if source_id not in selected:
                selected.append(source_id)
            if len(selected) >= fanout:
                break
        return SourceSelection(
            tuple(selected),
            tuple(sorted(skipped, key=lambda item: item.circuit_open_until_millis)),
        )

    def _source_health_values(self, source_ids: Sequence[str] = ()) -> list[dict[str, Any]]:
        now_millis = self._millis()
        health_by_source = self.store.source_health(source_ids)
        if source_ids:
            values = [
                health_by_source.get(source_id, SourceHealth(source_id))
                for source_id in dict.fromkeys(source_ids)
            ]
        else:
            values = list(health_by_source.values())
        return [item.public(now_millis) for item in values]

    @staticmethod
    def _infer_verticals(query: str) -> list[str]:
        lower = query.lower()
        values = {"general", "knowledge"}
        if re.search(
            r"\b(today|latest|breaking|news|current)\b|"
            r"\u4eca\u5929|\u6700\u65b0|\u65b0\u95fb|\u5b9e\u65f6",
            lower,
        ):
            values.add("news")
        if re.search(
            r"\b(code|api|sdk|library|package|bug|github|python|javascript|rust|java)\b|"
            r"\u4ee3\u7801|\u7f16\u7a0b|\u63a5\u53e3|\u5f00\u53d1",
            lower,
        ):
            values.update({"code", "docs", "community"})
        if re.search(
            r"\b(paper|study|research|doi|journal|citation)\b|"
            r"\u8bba\u6587|\u7814\u7a76|\u6587\u732e|\u5b66\u672f",
            lower,
        ):
            values.add("academic")
        if re.search(
            r"\b(opinion|discussion|experience|recommend)\b|"
            r"\u8bc4\u4ef7|\u8ba8\u8bba|\u7ecf\u9a8c|\u63a8\u8350",
            lower,
        ):
            values.add("community")
        return sorted(values)

    @staticmethod
    def _decompose_query(query: str, rounds: int) -> list[str]:
        if detect_language(query) == "zh":
            suffixes = (
                " \u5b98\u65b9\u8d44\u6599",
                " \u6700\u65b0\u8fdb\u5c55",
                " \u5c40\u9650 \u98ce\u9669",
                " \u5b9e\u9645\u6848\u4f8b",
                " \u6280\u672f\u539f\u7406",
                " \u5bf9\u6bd4",
            )
        else:
            suffixes = (
                " official documentation",
                " latest developments",
                " limitations risks",
                " real world examples",
                " technical architecture",
                " comparison",
            )
        values = [query]
        values.extend(f"{query}{suffix}"[:MAX_QUERY_CHARS] for suffix in suffixes)
        return values[: max(1, rounds * 2)]

    @staticmethod
    def _evidence_brief(
        query: str,
        documents: Sequence[CachedDocument],
        search_results: Sequence[Mapping[str, Any]],
    ) -> tuple[str, list[dict[str, Any]]]:
        citations = []
        paragraphs = []
        for index, document in enumerate(documents, start=1):
            sentence = _best_evidence_sentence(query, document.content)
            identifier = citation_id(document.url, sentence)
            citations.append({
                "citation_id": identifier,
                "url": document.url,
                "title": document.title,
                "quoted_text": sentence[:16_384],
            })
            if sentence:
                paragraphs.append(f"[{index}] {sentence}")
        if not paragraphs:
            for index, item in enumerate(search_results[:8], start=1):
                excerpt = _safe_text(item.get("excerpt"), 1_000)
                if not excerpt:
                    continue
                identifier = str(item.get("citation_id") or citation_id(item.get("url", ""), excerpt))
                citations.append({
                    "citation_id": identifier,
                    "url": item.get("url", ""),
                    "title": item.get("title", ""),
                    "quoted_text": excerpt,
                })
                paragraphs.append(f"[{index}] {excerpt}")
        return "\n\n".join(paragraphs)[:MAX_CONTENT_CHARS], citations

    @staticmethod
    def _challenge_reason(raw_html: str, extracted_text: str) -> str:
        lower = raw_html[:200_000].lower()
        markers = {
            "captcha": ("captcha", "verify you are human", "\u4eba\u673a\u9a8c\u8bc1"),
            "managed_challenge": ("cf-chl-", "challenge-platform", "checking your browser"),
            "javascript_required": (
                "enable javascript",
                "javascript is required",
                "\u8bf7\u542f\u7528javascript",
            ),
            "access_denied": (
                "access denied",
                "request blocked",
                "\u8bbf\u95ee\u88ab\u62d2\u7edd",
            ),
        }
        for reason, values in markers.items():
            if any(marker in lower for marker in values):
                return reason
        if len(extracted_text.strip()) < 120 and ("<script" in lower or "<div id=\"root\"" in lower):
            return "thin_javascript_shell"
        return ""

    def _base(
        self,
        operation: str,
        arguments: Mapping[str, Any],
        started_at_millis: int,
        status: str,
    ) -> dict[str, Any]:
        return {
            "protocol": PROTOCOL,
            "operation": operation,
            "request_id": self._request_id(arguments),
            "status": status,
            "started_at_millis": started_at_millis,
            "completed_at_millis": self._millis(),
            "receipts": [],
        }

    @staticmethod
    def _request_id(arguments: Mapping[str, Any]) -> str:
        value = str(arguments.get("request_id") or f"web-{uuid.uuid4().hex[:20]}")
        return _identifier(value)

    @staticmethod
    def _query(arguments: Mapping[str, Any]) -> str:
        return _required_string(arguments.get("query"), "query", MAX_QUERY_CHARS)

    @staticmethod
    def _url(arguments: Mapping[str, Any]) -> str:
        value = _required_string(arguments.get("url"), "url", MAX_URL_CHARS)
        return PublicWebTransport._validate_public_url(value)

    def _millis(self) -> int:
        return int(self.now() * 1_000)


def _receipt_status(error: WebIntelligenceError) -> str:
    if error.code in {"transport_failed", "dns_failed"}:
        return "unavailable"
    if error.code in {"private_network_blocked", "access_denied", "challenge"}:
        return "blocked"
    if "timeout" in error.code:
        return "timeout"
    return "failed"


def _bounded_int(value: Any, default: int, minimum: int, maximum: int) -> int:
    if value in (None, ""):
        return default
    if isinstance(value, bool):
        raise WebIntelligenceError("invalid_input", "Boolean value is not an integer")
    try:
        converted = int(value)
    except (TypeError, ValueError) as exc:
        raise WebIntelligenceError("invalid_input", "Expected an integer") from exc
    if converted < minimum or converted > maximum:
        raise WebIntelligenceError("invalid_input", f"Integer must be between {minimum} and {maximum}")
    return converted


def _bounded_float(value: Any, default: float, minimum: float, maximum: float) -> float:
    if value in (None, ""):
        return default
    if isinstance(value, bool):
        raise WebIntelligenceError("invalid_input", "Boolean value is not a number")
    try:
        converted = float(value)
    except (TypeError, ValueError) as exc:
        raise WebIntelligenceError("invalid_input", "Expected a number") from exc
    if not math.isfinite(converted) or converted < minimum or converted > maximum:
        raise WebIntelligenceError("invalid_input", f"Number must be between {minimum} and {maximum}")
    return converted


def _required_string(value: Any, name: str, maximum: int) -> str:
    if not isinstance(value, str) or not value.strip():
        raise WebIntelligenceError("invalid_input", f"{name} is required")
    clean = value.strip()
    if len(clean) > maximum:
        raise WebIntelligenceError("invalid_input", f"{name} is too long")
    return clean


def _string_list(value: Any, *, limit: int, max_length: int) -> list[str]:
    if value in (None, ""):
        return []
    if not isinstance(value, (list, tuple)):
        raise WebIntelligenceError("invalid_input", "Expected an array of strings")
    if len(value) > limit:
        raise WebIntelligenceError("invalid_input", "String array has too many items")
    output = []
    for item in value:
        if not isinstance(item, str) or len(item.strip()) > max_length:
            raise WebIntelligenceError("invalid_input", "String array contains an invalid item")
        if item.strip():
            output.append(item.strip())
    return list(dict.fromkeys(output))


def _optional_regex(value: Any) -> re.Pattern[str] | None:
    if value in (None, ""):
        return None
    text = _required_string(value, "pattern", 512)
    try:
        return re.compile(text)
    except re.error as exc:
        raise WebIntelligenceError("invalid_pattern", str(exc)) from exc


def _origin(url: str) -> tuple[str, str, int | None]:
    parsed = urllib.parse.urlsplit(url)
    return parsed.scheme.lower(), (parsed.hostname or "").lower(), parsed.port


def _similar_result(document: CachedDocument, score: float, rank: int) -> dict[str, Any]:
    return {
        "citation_id": citation_id(document.url, document.content[:1_000]),
        "title": document.title,
        "url": document.url,
        "excerpt": document.content[:1_000],
        "published_at": "",
        "language": detect_language(document.content),
        "vertical": "local",
        "engines": ["local_cache"],
        "rank": rank,
        "score": {
            "final": score,
            "reciprocal_rank": 0.0,
            "lexical": 0.0,
            "consensus": 0.0,
            "authority": 1.0,
            "freshness": 1.0,
            "local_model": score,
        },
    }


def _best_evidence_sentence(query: str, content: str) -> str:
    query_tokens = set(_tokens(query))
    candidates = [
        _safe_text(item, 2_000)
        for item in re.split(r"(?<=[.!?\u3002\uFF01\uFF1F])\s+|\n+", content)
        if 40 <= len(item.strip()) <= 2_000
    ][:2_000]
    if not candidates:
        return _safe_text(content, 1_500)
    return max(
        candidates,
        key=lambda sentence: (
            len(query_tokens & set(_tokens(sentence))) / max(1, len(query_tokens)),
            min(len(sentence), 500) / 500,
        ),
    )[:1_500]
