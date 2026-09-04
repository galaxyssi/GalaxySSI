"""Evidence-backed typed relationship graph for Desktop long-term memory."""
from __future__ import annotations

import hashlib
import json
import re
import sqlite3
from typing import Any, Iterable


NODE_KINDS = {
    "user",
    "device",
    "application",
    "feature",
    "setting",
    "agent",
    "model",
    "tool",
    "project",
    "concept",
    "state",
}
RELATION_KINDS = {
    "owns",
    "uses",
    "supports",
    "has_component",
    "has_state",
    "named_as",
    "depends_on",
    "connected_to",
    "prefers",
    "removed",
    "related_to",
}
ACTIVE_STATES = {"current", "planned", "pending", "conflicted"}
HISTORICAL_STATES = {"historical", "deprecated"}
WORD_PATTERN = re.compile(r"[a-z0-9_.-]{2,}|[\u4e00-\u9fff]")


def initialize_graph_schema(connection: sqlite3.Connection) -> None:
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS memory_graph_nodes (
            id TEXT PRIMARY KEY,
            stable_key TEXT NOT NULL UNIQUE,
            namespace TEXT NOT NULL DEFAULT 'general',
            kind TEXT NOT NULL,
            label TEXT NOT NULL,
            aliases_json TEXT NOT NULL DEFAULT '[]',
            temporal_state TEXT NOT NULL DEFAULT 'current',
            confidence REAL NOT NULL DEFAULT 0.5,
            evidence_memory_ids_json TEXT NOT NULL DEFAULT '[]',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        )
        """
    )
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS memory_graph_relations (
            id TEXT PRIMARY KEY,
            namespace TEXT NOT NULL DEFAULT 'general',
            from_node_id TEXT NOT NULL,
            to_node_id TEXT NOT NULL,
            relation_kind TEXT NOT NULL,
            temporal_state TEXT NOT NULL DEFAULT 'current',
            confidence REAL NOT NULL DEFAULT 0.5,
            evidence_memory_ids_json TEXT NOT NULL DEFAULT '[]',
            valid_from_at INTEGER NOT NULL DEFAULT 0,
            valid_until_at INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        )
        """
    )
    connection.execute(
        "CREATE INDEX IF NOT EXISTS idx_memory_graph_node_kind "
        "ON memory_graph_nodes(kind, temporal_state, updated_at DESC)"
    )
    connection.execute(
        "CREATE INDEX IF NOT EXISTS idx_memory_graph_node_namespace "
        "ON memory_graph_nodes(namespace, temporal_state, updated_at DESC)"
    )
    connection.execute(
        "CREATE INDEX IF NOT EXISTS idx_memory_graph_relation_nodes "
        "ON memory_graph_relations(from_node_id, to_node_id, temporal_state)"
    )
    connection.execute(
        "CREATE INDEX IF NOT EXISTS idx_memory_graph_relation_kind "
        "ON memory_graph_relations(relation_kind, temporal_state, updated_at DESC)"
    )


def project_memory_graph(connection: sqlite3.Connection, memory: sqlite3.Row) -> None:
    content = _clean(memory["content"], 2_400)
    if not content:
        return
    namespace = _normalize_namespace(memory["namespace"])
    memory_id = str(memory["id"])
    kind = str(memory["kind"] or "fact").casefold()
    temporal_state = _normalize_state(memory["temporal_state"])
    confidence = max(0.0, min(1.0, float(memory["confidence"])))
    now_ms = int(memory["updated_at"])
    triples = _extract_triples(content)
    if not triples:
        fallback = _fallback_triple(namespace, kind, content)
        if fallback:
            triples = [fallback]
    for source_label, relation_kind, target_label in triples[:24]:
        source_kind = _classify_node(source_label, namespace)
        target_kind = _target_kind(relation_kind, target_label, namespace)
        source_namespace = _node_namespace(namespace, source_kind, source_label)
        target_namespace = _node_namespace(namespace, target_kind, target_label)
        source = _upsert_node(
            connection,
            source_namespace,
            source_kind,
            source_label,
            temporal_state,
            confidence,
            memory_id,
            now_ms,
        )
        target = _upsert_node(
            connection,
            target_namespace,
            target_kind,
            target_label,
            "deprecated" if relation_kind == "removed" else temporal_state,
            confidence,
            memory_id,
            now_ms,
        )
        if relation_kind == "removed":
            _retire_entity(connection, source["id"], now_ms)
        if relation_kind in {"has_state", "named_as", "prefers"}:
            _close_exclusive_relations(
                connection,
                source["id"],
                relation_kind,
                target["id"],
                namespace,
                now_ms,
            )
        _upsert_relation(
            connection,
            namespace,
            source["id"],
            target["id"],
            relation_kind,
            "deprecated" if relation_kind == "removed" else temporal_state,
            confidence,
            memory_id,
            now_ms,
        )


def retract_memory_graph_evidence(
    connection: sqlite3.Connection,
    memory_id: str,
    now_ms: int,
) -> None:
    for table in ("memory_graph_nodes", "memory_graph_relations"):
        rows = connection.execute(
            f"SELECT id, evidence_memory_ids_json FROM {table}"
        ).fetchall()
        for row in rows:
            evidence = _json_strings(row["evidence_memory_ids_json"])
            if memory_id not in evidence:
                continue
            remaining = [item for item in evidence if item != memory_id]
            if remaining:
                connection.execute(
                    f"UPDATE {table} SET evidence_memory_ids_json = ?, updated_at = ? WHERE id = ?",
                    (json.dumps(remaining), now_ms, row["id"]),
                )
            elif table == "memory_graph_relations":
                connection.execute(
                    "UPDATE memory_graph_relations SET temporal_state = 'deprecated', "
                    "valid_until_at = ?, updated_at = ? WHERE id = ?",
                    (now_ms, now_ms, row["id"]),
                )
            else:
                connection.execute(
                    "UPDATE memory_graph_nodes SET temporal_state = 'deprecated', "
                    "updated_at = ? WHERE id = ?",
                    (now_ms, row["id"]),
                )


def clear_memory_graph(connection: sqlite3.Connection) -> None:
    connection.execute("DELETE FROM memory_graph_relations")
    connection.execute("DELETE FROM memory_graph_nodes")


def search_memory_graph(
    connection: sqlite3.Connection,
    query: str,
    *,
    namespaces: Iterable[str] | None = None,
    hops: int = 2,
    limit: int = 24,
    include_historical: bool = False,
    historical_only: bool = False,
    preferred_relations: Iterable[str] | None = None,
) -> dict[str, list[dict[str, Any]]]:
    query_tokens = _tokens(query)
    if not query_tokens:
        return {"nodes": [], "relations": []}
    requested = {_normalize_namespace(value) for value in (namespaces or []) if str(value).strip()}
    preferred = {
        str(value).casefold()
        for value in (preferred_relations or [])
        if str(value).casefold() in RELATION_KINDS
    }
    node_states = (
        ACTIVE_STATES | HISTORICAL_STATES
        if include_historical or historical_only
        else ACTIVE_STATES
    )
    relation_states = HISTORICAL_STATES if historical_only else node_states
    node_placeholders = ",".join("?" for _ in node_states)
    nodes = connection.execute(
        f"SELECT * FROM memory_graph_nodes WHERE temporal_state IN ({node_placeholders}) "
        "ORDER BY updated_at DESC LIMIT 2000",
        tuple(sorted(node_states)),
    ).fetchall()
    ranked: list[tuple[float, sqlite3.Row]] = []
    for node in nodes:
        if requested and not _namespace_matches(str(node["namespace"]), requested):
            continue
        label_tokens = _tokens(
            " ".join([str(node["label"]), *_json_strings(node["aliases_json"])])
        )
        overlap = len(query_tokens & label_tokens)
        if overlap <= 0:
            continue
        coverage = overlap / max(1, len(query_tokens))
        score = coverage * 0.82 + float(node["confidence"]) * 0.18
        ranked.append((score, node))
    seeds = [
        row for _score, row in sorted(ranked, key=lambda item: item[0], reverse=True)[:8]
    ]
    if not seeds:
        return {"nodes": [], "relations": []}
    selected_ids = {str(row["id"]) for row in seeds}
    selected_order = [str(row["id"]) for row in seeds]
    relation_placeholders = ",".join("?" for _ in relation_states)
    relation_rows = connection.execute(
        f"SELECT * FROM memory_graph_relations WHERE temporal_state IN ({relation_placeholders}) "
        "ORDER BY confidence DESC, updated_at DESC LIMIT 8000",
        tuple(sorted(relation_states)),
    ).fetchall()
    relation_rows = sorted(
        relation_rows,
        key=lambda row: (
            str(row["relation_kind"]) in preferred,
            float(row["confidence"]),
            int(row["updated_at"]),
        ),
        reverse=True,
    )
    for _ in range(max(0, min(int(hops), 3))):
        neighbors: list[str] = []
        for relation in relation_rows:
            source = str(relation["from_node_id"])
            target = str(relation["to_node_id"])
            if source in selected_ids or target in selected_ids:
                neighbors.extend((source, target))
        additions = [node_id for node_id in neighbors if node_id not in selected_ids][
            : max(1, min(limit, 60))
        ]
        if not additions:
            break
        selected_ids.update(additions)
        selected_order.extend(additions)
    node_by_id = {str(row["id"]): row for row in nodes}
    selected_nodes = [
        _node_public(node_by_id[node_id])
        for node_id in selected_order
        if node_id in node_by_id
    ][: max(1, min(limit, 60))]
    bounded_ids = {node["id"] for node in selected_nodes}
    selected_relations = [
        _relation_public(row)
        for row in relation_rows
        if str(row["from_node_id"]) in bounded_ids
        and str(row["to_node_id"]) in bounded_ids
    ][: max(2, min(limit * 2, 120))]
    return {"nodes": selected_nodes, "relations": selected_relations}


def memory_graph_snapshot(connection: sqlite3.Connection) -> dict[str, Any]:
    node_rows = connection.execute(
        "SELECT kind, temporal_state, COUNT(*) AS count FROM memory_graph_nodes "
        "GROUP BY kind, temporal_state"
    ).fetchall()
    relation_rows = connection.execute(
        "SELECT relation_kind, temporal_state, COUNT(*) AS count FROM memory_graph_relations "
        "GROUP BY relation_kind, temporal_state"
    ).fetchall()
    active_nodes: dict[str, int] = {}
    for row in node_rows:
        if str(row["temporal_state"]) in ACTIVE_STATES:
            kind = str(row["kind"])
            active_nodes[kind] = active_nodes.get(kind, 0) + int(row["count"])
    active_relations: dict[str, int] = {}
    for row in relation_rows:
        if str(row["temporal_state"]) in ACTIVE_STATES:
            kind = str(row["relation_kind"])
            active_relations[kind] = active_relations.get(kind, 0) + int(row["count"])
    return {
        "contract_version": 1,
        "node_count": sum(active_nodes.values()),
        "relation_count": sum(active_relations.values()),
        "historical_node_count": sum(
            int(row["count"]) for row in node_rows
            if str(row["temporal_state"]) in HISTORICAL_STATES
        ),
        "historical_relation_count": sum(
            int(row["count"]) for row in relation_rows
            if str(row["temporal_state"]) in HISTORICAL_STATES
        ),
        "node_kinds": {kind: active_nodes.get(kind, 0) for kind in sorted(NODE_KINDS)},
        "relation_kinds": {
            kind: active_relations.get(kind, 0) for kind in sorted(RELATION_KINDS)
        },
    }


def _upsert_node(
    connection: sqlite3.Connection,
    namespace: str,
    kind: str,
    label: str,
    temporal_state: str,
    confidence: float,
    memory_id: str,
    now_ms: int,
) -> sqlite3.Row:
    label = _clean_label(label)
    kind = kind if kind in NODE_KINDS else "concept"
    stable_key = _stable_key("node", namespace, kind, _normalize_label(label))
    existing = connection.execute(
        "SELECT * FROM memory_graph_nodes WHERE stable_key = ?",
        (stable_key,),
    ).fetchone()
    if existing:
        aliases = _append_unique(_json_strings(existing["aliases_json"]), label, 16)
        evidence = _append_unique(
            _json_strings(existing["evidence_memory_ids_json"]), memory_id, 100
        )
        state = temporal_state if now_ms >= int(existing["updated_at"]) else str(existing["temporal_state"])
        connection.execute(
            "UPDATE memory_graph_nodes SET label = ?, aliases_json = ?, temporal_state = ?, "
            "confidence = ?, evidence_memory_ids_json = ?, updated_at = ? WHERE id = ?",
            (
                label if len(label) < len(str(existing["label"])) else existing["label"],
                json.dumps(aliases, ensure_ascii=False),
                state,
                min(0.99, max(float(existing["confidence"]), confidence) + 0.02),
                json.dumps(evidence),
                max(now_ms, int(existing["updated_at"])),
                existing["id"],
            ),
        )
        return connection.execute(
            "SELECT * FROM memory_graph_nodes WHERE id = ?",
            (existing["id"],),
        ).fetchone()
    node_id = stable_key
    connection.execute(
        "INSERT INTO memory_graph_nodes (id, stable_key, namespace, kind, label, "
        "aliases_json, temporal_state, confidence, evidence_memory_ids_json, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            node_id,
            stable_key,
            namespace,
            kind,
            label,
            json.dumps([label], ensure_ascii=False),
            temporal_state,
            confidence,
            json.dumps([memory_id]),
            now_ms,
            now_ms,
        ),
    )
    return connection.execute(
        "SELECT * FROM memory_graph_nodes WHERE id = ?",
        (node_id,),
    ).fetchone()


def _upsert_relation(
    connection: sqlite3.Connection,
    namespace: str,
    source_id: str,
    target_id: str,
    relation_kind: str,
    temporal_state: str,
    confidence: float,
    memory_id: str,
    now_ms: int,
) -> None:
    if source_id == target_id:
        return
    relation_kind = relation_kind if relation_kind in RELATION_KINDS else "related_to"
    relation_id = _stable_key("relation", namespace, source_id, relation_kind, target_id)
    existing = connection.execute(
        "SELECT * FROM memory_graph_relations WHERE id = ?",
        (relation_id,),
    ).fetchone()
    if existing:
        evidence = _append_unique(
            _json_strings(existing["evidence_memory_ids_json"]), memory_id, 100
        )
        connection.execute(
            "UPDATE memory_graph_relations SET temporal_state = ?, confidence = ?, "
            "evidence_memory_ids_json = ?, valid_until_at = 0, updated_at = ? WHERE id = ?",
            (
                temporal_state,
                min(0.99, max(float(existing["confidence"]), confidence) + 0.02),
                json.dumps(evidence),
                max(now_ms, int(existing["updated_at"])),
                relation_id,
            ),
        )
        return
    connection.execute(
        "INSERT INTO memory_graph_relations (id, namespace, from_node_id, to_node_id, "
        "relation_kind, temporal_state, confidence, evidence_memory_ids_json, "
        "valid_from_at, valid_until_at, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)",
        (
            relation_id,
            namespace,
            source_id,
            target_id,
            relation_kind,
            temporal_state,
            confidence,
            json.dumps([memory_id]),
            now_ms,
            now_ms,
            now_ms,
        ),
    )


def _close_exclusive_relations(
    connection: sqlite3.Connection,
    source_id: str,
    relation_kind: str,
    target_id: str,
    namespace: str,
    now_ms: int,
) -> None:
    connection.execute(
        "UPDATE memory_graph_relations SET temporal_state = 'deprecated', "
        "valid_until_at = ?, updated_at = ? WHERE from_node_id = ? "
        "AND relation_kind = ? AND to_node_id != ? AND namespace = ? "
        "AND temporal_state IN ('current', 'planned', 'pending', 'conflicted')",
        (now_ms, now_ms, source_id, relation_kind, target_id, namespace),
    )


def _retire_entity(connection: sqlite3.Connection, node_id: str, now_ms: int) -> None:
    connection.execute(
        "UPDATE memory_graph_nodes SET temporal_state = 'deprecated', updated_at = ? WHERE id = ?",
        (now_ms, node_id),
    )
    connection.execute(
        "UPDATE memory_graph_relations SET temporal_state = 'deprecated', "
        "valid_until_at = ?, updated_at = ? WHERE (from_node_id = ? OR to_node_id = ?) "
        "AND temporal_state IN ('current', 'planned', 'pending', 'conflicted')",
        (now_ms, now_ms, node_id, node_id),
    )


def _fallback_triple(
    namespace: str,
    memory_kind: str,
    content: str,
) -> tuple[str, str, str] | None:
    family, _, scope = namespace.partition(":")
    if family == "user":
        relation = "prefers" if memory_kind == "preference" else "named_as"
        return ("User", relation, content)
    if family == "project":
        return (scope or "Project", "has_state", content)
    if family == "device":
        return (scope or "Device", "has_state", content)
    if family == "security":
        return ("Security policy", "has_state", content)
    return None


def _extract_triples(content: str) -> list[tuple[str, str, str]]:
    triples: list[tuple[str, str, str]] = []
    for pattern, relation_kind in RELATION_PATTERNS:
        for match in pattern.finditer(content):
            source = _clean_label(match.group(1))
            target = _clean_label(match.group(2) if match.lastindex and match.lastindex >= 2 else "Removed")
            if len(source) >= 2 and target:
                triples.append((source, relation_kind, target))
    unique: dict[str, tuple[str, str, str]] = {}
    for triple in triples:
        key = "|".join((_normalize_label(triple[0]), triple[1], _normalize_label(triple[2])))
        unique[key] = triple
    return list(unique.values())


def _classify_node(label: str, namespace: str) -> str:
    value = label.casefold()
    family = namespace.partition(":")[0]
    if value in {"i", "me", "my", "user", "owner", "\u6211", "\u7528\u6237"}:
        return "user"
    if _contains_any(value, DEVICE_TERMS):
        return "device"
    if _contains_any(value, MODEL_TERMS):
        return "model"
    if _contains_any(value, AGENT_TERMS):
        return "agent"
    if _contains_any(value, SETTING_TERMS):
        return "setting"
    if _contains_any(value, TOOL_TERMS):
        return "tool"
    if _contains_any(value, FEATURE_TERMS):
        return "feature"
    if family == "project" or _contains_any(value, PROJECT_TERMS):
        return "project"
    return "concept"


def _target_kind(relation_kind: str, label: str, namespace: str) -> str:
    if relation_kind in {"has_state", "named_as", "prefers", "removed"}:
        return "state"
    return _classify_node(label, namespace)


def _node_namespace(namespace: str, kind: str, label: str) -> str:
    if kind == "user":
        return "user"
    if kind == "device":
        return namespace if namespace.startswith("device:") else f"device:{_scope(label)}"
    if kind == "project":
        return namespace if namespace.startswith("project:") else f"project:{_scope(label)}"
    return namespace


def _node_public(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": str(row["id"]),
        "stable_key": str(row["stable_key"]),
        "namespace": str(row["namespace"]),
        "kind": str(row["kind"]),
        "label": str(row["label"]),
        "aliases": _json_strings(row["aliases_json"]),
        "temporal_state": str(row["temporal_state"]),
        "confidence": float(row["confidence"]),
        "evidence_memory_ids": _json_strings(row["evidence_memory_ids_json"]),
        "created_at": int(row["created_at"]),
        "updated_at": int(row["updated_at"]),
    }


def _relation_public(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": str(row["id"]),
        "namespace": str(row["namespace"]),
        "from_node_id": str(row["from_node_id"]),
        "to_node_id": str(row["to_node_id"]),
        "kind": str(row["relation_kind"]),
        "temporal_state": str(row["temporal_state"]),
        "confidence": float(row["confidence"]),
        "evidence_memory_ids": _json_strings(row["evidence_memory_ids_json"]),
        "valid_from_at": int(row["valid_from_at"]),
        "valid_until_at": int(row["valid_until_at"]),
        "created_at": int(row["created_at"]),
        "updated_at": int(row["updated_at"]),
    }


def _normalize_namespace(value: Any) -> str:
    raw = str(value or "general").strip().casefold()
    family, separator, scope = raw.partition(":")
    if family not in {"general", "user", "project", "device", "security"}:
        return "general"
    clean_scope = _scope(scope) if separator and family in {"project", "device"} else ""
    return f"{family}:{clean_scope}" if clean_scope else family


def _namespace_matches(value: str, requested: set[str]) -> bool:
    normalized = _normalize_namespace(value)
    family = normalized.partition(":")[0]
    return normalized in requested or family in requested


def _normalize_state(value: Any) -> str:
    state = str(value or "current").casefold()
    return state if state in ACTIVE_STATES | HISTORICAL_STATES else "current"


def _clean(value: Any, maximum: int = 160) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()[:maximum]


def _clean_label(value: Any) -> str:
    return _clean(value, 160).strip(" .,;:\u3002\uff0c\uff1b\uff1a")


def _normalize_label(value: str) -> str:
    return re.sub(r"[^a-z0-9\u4e00-\u9fff]+", "-", value.casefold()).strip("-")


def _scope(value: Any) -> str:
    return re.sub(
        r"[^a-z0-9_.\-\u4e00-\u9fff]+",
        "-",
        str(value or "").casefold(),
    ).strip("-")[:96] or "default"


def _tokens(value: Any) -> set[str]:
    text = _clean(value, 4_000).casefold()
    tokens = set(WORD_PATTERN.findall(text))
    cjk = "".join(character for character in text if "\u4e00" <= character <= "\u9fff")
    tokens.update(cjk[index:index + 2] for index in range(max(0, len(cjk) - 1)))
    return {token for token in tokens if token}


def _stable_key(*parts: str) -> str:
    raw = "|".join(parts).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()[:32]


def _json_strings(raw: Any) -> list[str]:
    try:
        values = json.loads(str(raw or "[]"))
    except (TypeError, ValueError, json.JSONDecodeError):
        return []
    return [str(value) for value in values if str(value).strip()] if isinstance(values, list) else []


def _append_unique(values: list[str], value: str, limit: int) -> list[str]:
    return list(dict.fromkeys([*values, value]))[-limit:]


def _contains_any(value: str, terms: tuple[str, ...]) -> bool:
    return any(term in value for term in terms)


AGENT_TERMS = (
    "galaxyssi", "codex", "hermes", "claude code", "openclaw", "agent",
    "\u667a\u80fd\u4f53",
)
MODEL_TERMS = (
    "model", "llm", "gpt", "gemma", "qwen", "deepseek", "claude opus",
    "claude sonnet", "\u6a21\u578b",
)
DEVICE_TERMS = (
    "phone", "android", "iphone", "desktop", "computer", "device", "tablet",
    "sensor", "camera", "\u624b\u673a", "\u7535\u8111", "\u8bbe\u5907", "\u4f20\u611f\u5668",
)
SETTING_TERMS = (
    "setting", "settings", "control center", "preference page", "menu",
    "\u8bbe\u7f6e", "\u63a7\u5236\u4e2d\u5fc3", "\u83dc\u5355",
)
TOOL_TERMS = (
    "tool", "mcp", "skill", "api", "runtime", "terminal", "command",
    "\u5de5\u5177", "\u6280\u80fd", "\u547d\u4ee4",
)
FEATURE_TERMS = (
    "feature", "tts", "asr", "ocr", "linux", "memory", "knowledge",
    "voice", "\u529f\u80fd", "\u8bb0\u5fc6", "\u77e5\u8bc6\u5e93", "\u8bed\u97f3",
)
PROJECT_TERMS = (
    "project", "repository", "roadmap", "release", "\u9879\u76ee", "\u8def\u7ebf\u56fe",
)


RELATION_PATTERNS = (
    (
        re.compile(
            r"(?i)([^.!?;\n]{2,80}?)\s+"
            r"(?:owns|has(?!\s+(?:component|been removed|removed|deleted)\b))\s+"
            r"([^.!?;\n]{1,120})"
        ),
        "owns",
    ),
    (re.compile(r"(?i)([^.!?;\n]{2,80}?)\s+(?:uses|use)\s+([^.!?;\n]{1,120})"), "uses"),
    (re.compile(r"(?i)([^.!?;\n]{2,80}?)\s+supports\s+([^.!?;\n]{1,120})"), "supports"),
    (
        re.compile(
            r"(?i)([^.!?;\n]{2,80}?)\s+(?:contains|includes|has component|is composed of)\s+"
            r"([^.!?;\n]{1,120})"
        ),
        "has_component",
    ),
    (
        re.compile(r"(?i)([^.!?;\n]{2,80}?)\s+(?:state is|status is|is currently)\s+([^.!?;\n]{1,120})"),
        "has_state",
    ),
    (re.compile(r"(?i)([^.!?;\n]{2,80}?)\s+(?:renamed to|changed to)\s+([^.!?;\n]{1,120})"), "named_as"),
    (re.compile(r"(?i)([^.!?;\n]{2,80}?)\s+(?:depends on|requires)\s+([^.!?;\n]{1,120})"), "depends_on"),
    (re.compile(r"(?i)([^.!?;\n]{2,80}?)\s+(?:connected to|paired with)\s+([^.!?;\n]{1,120})"), "connected_to"),
    (re.compile(r"(?i)([^.!?;\n]{2,80}?)\s+(?:prefers|preference is)\s+([^.!?;\n]{1,120})"), "prefers"),
    (
        re.compile(r"(?i)([^.!?;\n]{2,80}?)\s+(?:has been removed|was removed|is removed|removed)\b"),
        "removed",
    ),
    (re.compile(r"([^\u3002\uff01\uff1f\uff1b\n]{2,80}?)\s*\u62e5\u6709\s*([^\u3002\uff01\uff1f\uff1b\n]{1,120})"), "owns"),
    (re.compile(r"([^\u3002\uff01\uff1f\uff1b\n]{2,80}?)\s*\u4f7f\u7528\s*([^\u3002\uff01\uff1f\uff1b\n]{1,120})"), "uses"),
    (re.compile(r"([^\u3002\uff01\uff1f\uff1b\n]{2,80}?)\s*\u652f\u6301\s*([^\u3002\uff01\uff1f\uff1b\n]{1,120})"), "supports"),
    (
        re.compile(
            r"([^\u3002\uff01\uff1f\uff1b\n]{2,80}?)\s*(?:\u5305\u542b|\u7531)\s*"
            r"([^\u3002\uff01\uff1f\uff1b\n]{1,120})"
        ),
        "has_component",
    ),
    (
        re.compile(
            r"([^\u3002\uff01\uff1f\uff1b\n]{2,80}?)\s*(?:\u72b6\u6001\u4e3a|\u5f53\u524d\u4e3a)\s*"
            r"([^\u3002\uff01\uff1f\uff1b\n]{1,120})"
        ),
        "has_state",
    ),
    (
        re.compile(
            r"([^\u3002\uff01\uff1f\uff1b\n]{2,80}?)\s*(?:\u6539\u6210|\u66f4\u540d\u4e3a)\s*"
            r"([^\u3002\uff01\uff1f\uff1b\n]{1,120})"
        ),
        "named_as",
    ),
    (re.compile(r"([^\u3002\uff01\uff1f\uff1b\n]{2,80}?)\s*(?:\u4f9d\u8d56|\u9700\u8981)\s*([^\u3002\uff01\uff1f\uff1b\n]{1,120})"), "depends_on"),
    (re.compile(r"([^\u3002\uff01\uff1f\uff1b\n]{2,80}?)\s*(?:\u8fde\u63a5\u5230|\u914d\u5bf9)\s*([^\u3002\uff01\uff1f\uff1b\n]{1,120})"), "connected_to"),
    (re.compile(r"([^\u3002\uff01\uff1f\uff1b\n]{2,80}?)\s*(?:\u504f\u597d|\u559c\u6b22)\s*([^\u3002\uff01\uff1f\uff1b\n]{1,120})"), "prefers"),
    (re.compile(r"([^\u3002\uff01\uff1f\uff1b\n]{2,80}?)\s*(?:\u5df2\u79fb\u9664|\u5df2\u5220\u9664|\u53bb\u6389)"), "removed"),
)
