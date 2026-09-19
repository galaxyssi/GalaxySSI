"""Bounded, public search receipts for the mobile disclosure row, not model reasoning."""
from urllib.parse import urlsplit, urlunsplit
import json


def bound_receipt(receipt: dict, limit: int = 12_000) -> dict:
    while len(json.dumps(receipt, ensure_ascii=False, separators=(",", ":")).encode("utf-8")) > limit:
        receipt["truncated"] = True
        if receipt["sources"]:
            receipt["sources"].pop()
        elif receipt["queries"]:
            receipt["queries"].pop()
        else:
            break
    return receipt


def replay_receipts(events: list) -> dict:
    queries, sources = {}, {}
    truncated = len(events) >= 100  # Task snapshots may retain only the most recent 100 events.
    for event in events:
        metadata = event.get("metadata") if isinstance(event, dict) else None
        receipt = metadata.get("research_trace") if isinstance(metadata, dict) else None
        if not isinstance(receipt, dict):
            continue
        truncated |= bool(receipt.get("truncated"))
        for query in receipt.get("queries", []):
            if isinstance(query, str) and query.strip():
                queries.setdefault(query.casefold(), query)
        for source in receipt.get("sources", []):
            if isinstance(source, dict) and source.get("url"):
                sources.setdefault(source["url"], source)
    if not queries and not sources:
        return {}
    return bound_receipt({"queries": list(queries.values())[:128], "sources": list(sources.values())[:512],
                          "remote": True, "truncated": truncated or len(queries) > 128 or len(sources) > 512}, 48_000)


def search_receipt(item: dict, *, completed: bool) -> dict:
    if item.get("type") != "webSearch":
        return {}
    action = item.get("action") if isinstance(item.get("action"), dict) else {}
    queries = []
    values = [item.get("query"), action.get("query")]
    if isinstance(action.get("queries"), list):
        values.extend(action["queries"][:128])
    for value in values:
        if not isinstance(value, str):
            continue
        query = " ".join(value.split())[:1024]
        if query and query.casefold() not in {q.casefold() for q in queries}:
            queries.append(query)
    sources = {}

    def add(value):
        if not isinstance(value, dict) or not isinstance(value.get("url"), str):
            return
        raw = value["url"].strip()
        try:
            url = urlsplit(raw)
            if len(raw) > 4096 or url.scheme not in {"https", "http"} or not url.hostname or url.username:
                return
            canonical = urlunsplit((url.scheme, url.netloc, url.path, url.query, ""))
        except ValueError:
            return
        title = value.get("title")
        title = " ".join(title.split())[:512] if isinstance(title, str) else ""
        if canonical not in sources or not sources[canonical]["title"]:
            sources[canonical] = {"url": canonical, "title": title}

    if completed:
        for key in ("sources", "results"):
            values = item.get(key)
            if isinstance(values, list):
                for value in values[:512]:
                    add(value)
        if action.get("type") in {"openPage", "open_page"}:
            add(action)
    return bound_receipt({"queries": queries[:128], "sources": list(sources.values())[:512], "remote": True,
                         "truncated": len(queries) > 128 or len(sources) > 512})
