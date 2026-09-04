"""Bounded public-article compatibility helpers for Desktop web intelligence."""
from __future__ import annotations

import re
import urllib.parse
from html.parser import HTMLParser
from typing import Any, Mapping


_WECHAT_HOSTS = {"mp.weixin.qq.com"}
_BLOCK_TAGS = {
    "article", "blockquote", "br", "div", "h1", "h2", "h3", "h4", "h5",
    "h6", "li", "ol", "p", "pre", "section", "table", "td", "th", "tr", "ul",
}
_VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
_IGNORED_TAGS = {"script", "style", "svg", "noscript", "template"}


def dynamic_article_headers(url: str) -> dict[str, str]:
    host = (urllib.parse.urlsplit(str(url or "")).hostname or "").lower()
    if host not in _WECHAT_HOSTS:
        return {}
    return {
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.7",
        "Referer": "https://mp.weixin.qq.com/",
        "User-Agent": (
            "Mozilla/5.0 (Linux; Android 16; Mobile; wv) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Version/4.0 Chrome/140.0.7339.52 Mobile "
            "Safari/537.36 MicroMessenger/8.0.60 WeChat/arm64 Weixin "
            "NetType/WIFI Language/zh_CN ABI/arm64"
        ),
    }


def parse_public_article(url: str, source: str) -> dict[str, Any] | None:
    host = (urllib.parse.urlsplit(str(url or "")).hostname or "").lower()
    if host not in _WECHAT_HOSTS:
        return None
    parser = _WechatArticleParser(url)
    parser.feed(source)
    return parser.value()


class _WechatArticleParser(HTMLParser):
    def __init__(self, base_url: str) -> None:
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.content_depth = 0
        self.ignored_depth = 0
        self.capture_kind = ""
        self.capture_depth = 0
        self.parts: list[str] = []
        self.captures: dict[str, list[str]] = {"title": [], "author": [], "published_at": []}
        self.meta: dict[str, str] = {}
        self.links: list[str] = []
        self.images: list[dict[str, Any]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        values = {str(key).lower(): str(value or "") for key, value in attrs}
        classes = set(values.get("class", "").split())
        element_id = values.get("id", "")
        if tag == "meta":
            key = (values.get("property") or values.get("name") or "").lower()
            if key and values.get("content"):
                self.meta[key] = values["content"].strip()
        if not self.content_depth and (element_id == "js_content" or "rich_media_content" in classes):
            self.content_depth = 1
            self.parts.append("\n")
            return
        if self.content_depth:
            if tag not in _VOID_TAGS:
                self.content_depth += 1
            if tag in _IGNORED_TAGS:
                self.ignored_depth += 1
                return
            if self.ignored_depth:
                return
            if tag in _BLOCK_TAGS:
                self.parts.append("\n")
            if tag == "a":
                target = _public_https_url(values.get("href", ""), self.base_url)
                if target and target not in self.links and len(self.links) < 4_096:
                    self.links.append(target)
            if tag == "img":
                raw = values.get("data-src") or values.get("data-original") or values.get("src") or ""
                target = _public_https_url(raw, self.base_url)
                if target and all(item["url"] != target for item in self.images) and len(self.images) < 100:
                    image: dict[str, Any] = {"index": len(self.images), "url": target}
                    if values.get("alt", "").strip():
                        image["alt"] = values["alt"].strip()[:500]
                    for name, attributes in (("width", ("data-w", "width")), ("height", ("data-h", "height"))):
                        raw_dimension = next((values.get(key, "") for key in attributes if values.get(key, "")), "")
                        if raw_dimension.isdigit() and int(raw_dimension) > 0:
                            image[name] = int(raw_dimension)
                    self.images.append(image)
            return
        capture = ""
        if element_id == "activity-name" or "rich_media_title" in classes:
            capture = "title"
        elif element_id == "js_name" or "rich_media_meta_nickname" in classes or "profile_nickname" in classes:
            capture = "author"
        elif element_id == "publish_time":
            capture = "published_at"
        if capture:
            self.capture_kind = capture
            self.capture_depth = 1
        elif self.capture_depth and tag not in _VOID_TAGS:
            self.capture_depth += 1

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if self.content_depth:
            if tag in _IGNORED_TAGS and self.ignored_depth:
                self.ignored_depth -= 1
            if not self.ignored_depth and tag in _BLOCK_TAGS:
                self.parts.append("\n")
            if tag not in _VOID_TAGS:
                self.content_depth = max(0, self.content_depth - 1)
            return
        if self.capture_depth and tag not in _VOID_TAGS:
            self.capture_depth -= 1
            if self.capture_depth == 0:
                self.capture_kind = ""

    def handle_data(self, data: str) -> None:
        if self.content_depth and not self.ignored_depth:
            self.parts.append(data)
        elif self.capture_kind:
            self.captures[self.capture_kind].append(data)

    def value(self) -> dict[str, Any] | None:
        content = _clean_multiline("".join(self.parts), 512 * 1024)
        if not content:
            return None
        title = _clean_inline(" ".join(self.captures["title"]), 2_048) or _clean_inline(
            self.meta.get("og:title", ""), 2_048
        )
        return {
            "title": title,
            "author": _clean_inline(" ".join(self.captures["author"]), 1_024),
            "published_at": _clean_inline(" ".join(self.captures["published_at"]), 256),
            "content": content,
            "links": list(self.links),
            "images": list(self.images),
            "source_type": "wechat_public_account",
        }


def _public_https_url(value: str, base_url: str) -> str:
    raw = str(value or "").strip()
    if not raw or raw.lower().startswith("data:"):
        return ""
    parsed = urllib.parse.urlsplit(urllib.parse.urljoin(base_url, raw))
    if parsed.scheme.lower() == "http" and (parsed.hostname or "").lower().endswith("qpic.cn"):
        parsed = parsed._replace(scheme="https")
    if parsed.scheme.lower() != "https" or not parsed.hostname:
        return ""
    return urllib.parse.urlunsplit(parsed._replace(fragment=""))[:4_096]


def _clean_inline(value: str, limit: int) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:limit]


def _clean_multiline(value: str, limit: int) -> str:
    lines = [_clean_inline(line, limit) for line in str(value or "").splitlines()]
    return "\n\n".join(line for index, line in enumerate(lines) if line and (index == 0 or line != lines[index - 1]))[:limit]
