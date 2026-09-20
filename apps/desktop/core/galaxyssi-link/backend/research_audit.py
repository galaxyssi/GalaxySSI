"""Task-local provenance checks. Model judgments remain judgments, not verified facts."""
from __future__ import annotations

import hashlib
import json
import threading
from copy import deepcopy
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit


TOOL = "research_audit"


def tool_spec():
    spec = json.loads((Path(__file__).with_name("research_contract") / "research-audit-tool.json").read_text(encoding="utf-8"))
    return {"type": "function", "name": TOOL, "description": spec["description"], "inputSchema": spec["parameters"]}


def canonical(raw):
    if not isinstance(raw, str) or len(raw) > 4096:
        return None
    try:
        url = urlsplit(raw.strip())
        if url.scheme not in {"https", "http"} or not url.hostname or url.username or url.password:
            return None
        return urlunsplit((url.scheme, url.netloc, url.path, url.query, ""))
    except ValueError:
        return None


def record_key(url):
    parsed = urlsplit(url)
    path = parsed.path.strip("/")
    if parsed.hostname in {"doi.org", "dx.doi.org"}:
        return "doi:" + path.lower()
    if parsed.hostname == "pubmed.ncbi.nlm.nih.gov" and path.isascii() and path.isdigit():
        return "pmid:" + path
    return url


def rows(value):
    return value if isinstance(value, list) else []


def text(row, key, length):
    value = row.get(key)
    return value[:length] if isinstance(value, str) else ""


class ResearchEvidenceAudit:
    def __init__(self):
        self.queries = set()
        self.sources = {}
        self.bodies = set()
        self.chars = 0
        self.truncated = False
        self.snapshot = None
        self.lock = threading.RLock()

    def observe(self, root):
        with self.lock:
            trace = root.get("research_trace") or {}
            for query in rows(trace.get("queries")):
                if isinstance(query, str):
                    if len(self.queries) < 4096:
                        self.queries.add(query)
                    else:
                        self.truncated = True
            self.truncated |= bool(trace.get("truncated"))
            for source in rows(trace.get("sources")):
                if isinstance(source, dict):
                    self._add(source.get("url"), "", False)
            for item in rows((root.get("evidence_pack") or {}).get("items")):
                if isinstance(item, dict):
                    self._add(item.get("url"), text(item, "excerpt", 8_000_000), item.get("evidence_level") == "retrieved_body")

    def _add(self, raw, passage, body):
        url = canonical(raw)
        if not url:
            return
        if url not in self.sources and len(self.sources) >= 20000:
            self.truncated = True
            return
        passages = self.sources.setdefault(url, {})
        if passage and passage not in passages:
            if self.chars + len(passage) <= 8_000_000:
                passages[passage] = body
                self.chars += len(passage)
            else:
                self.truncated = True
        if body and passage:
            self.bodies.add(url)
            if passage in passages:
                passages[passage] = True

    def _refs(self, values):
        result = []
        for row in rows(values):
            url = canonical(row.get("url"))
            quote = text(row, "quote", 1200).strip()
            passage = next((value for value in self.sources.get(url, {}) if len(quote) >= 8 and quote in value), None)
            relation = text(row, "relation", 40)
            result.append({"url": url or "", "quote": quote,
                           "relation": relation if relation in {"supports", "contradicts", "context"} else "context",
                           "source_observed": url in self.sources, "passage_observed": passage is not None,
                           "passage_sha256": hashlib.sha256(passage.encode()).hexdigest() if passage else "",
                           "quote_offset": passage.index(quote) if passage else -1,
                           "evidence_scope": "retrieved_excerpt" if self.sources.get(url, {}).get(passage) else "search_snippet_or_unavailable"})
        return result

    def submit(self, data):
        with self.lock:
            return self._submit(data)

    def _submit(self, data):
        def invalid(message):
            return {"status": "invalid", "tool": TOOL, "error": message}
        if not isinstance(data, dict) or len(json.dumps(data, ensure_ascii=False)) > 160_000 or not text(data, "scope", 2000).strip():
            return invalid("Provide scope and a bounded snapshot; preserve counterevidence.")
        for key, limit in (("entities", 40), ("claims", 80), ("coverage", 40)):
            if not isinstance(data.get(key), list) or len(data[key]) > limit:
                return invalid("Provide bounded entities, claims and coverage arrays")
            for row in data[key]:
                if not isinstance(row, dict) or ("evidence" in row and (not isinstance(row["evidence"], list) or len(row["evidence"]) > 8 or
                        any(not isinstance(ref, dict) for ref in row["evidence"]))) or len(rows(row.get("entity_ids"))) > 8:
                    return invalid("Invalid ledger rows")
                fields = {"entities": ("id", "name", "decision", "basis", "reason"),
                          "claims": ("id", "statement", "assessment"), "coverage": ("facet", "status", "query", "gap")}[key]
                if any(not isinstance(row.get(field), str) for field in fields):
                    return invalid("Missing or invalid row fields")
                if key != "coverage" and (not isinstance(row.get("evidence"), list) or any(
                        not isinstance(ref.get("url"), str) or not isinstance(ref.get("quote"), str) or
                        len(ref["url"]) > 4096 or len(ref["quote"]) > 1200 for ref in row["evidence"])):
                    return invalid("Invalid evidence references")
                if key == "claims" and (not isinstance(row.get("entity_ids"), list) or any(not isinstance(value, str) for value in row["entity_ids"])):
                    return invalid("Invalid entity references")
        issues, entities, states = set(), [], {}
        for row in data["entities"]:
            identity = text(row, "id", 80)
            if not identity or identity in states:
                return invalid("Entity IDs must be unique and nonblank")
            refs = self._refs(row.get("evidence"))
            decision, basis = text(row, "decision", 40), text(row, "basis", 40)
            if decision not in {"include", "pending", "exclude"} or not any(ref["passage_observed"] for ref in refs) or (
                    decision == "include" and basis != "positive_match") or (decision == "exclude" and basis != "positive_mismatch"):
                decision = "pending"
            if decision == "pending":
                issues.add("identity_unresolved")
            states[identity] = decision
            entities.append({"id": identity, "name": text(row, "name", 200), "decision": decision,
                             "basis": text(row, "basis", 40), "reason": text(row, "reason", 1000), "evidence": refs,
                             "decision_authority": "model_assessment_not_independent_verification"})
        claims, ids = [], set()
        for row in data["claims"]:
            identity = text(row, "id", 80)
            if not identity or identity in ids:
                return invalid("Claim IDs must be unique and nonblank")
            ids.add(identity)
            refs = self._refs(row.get("evidence"))
            entity_ids = [str(value)[:80] for value in rows(row.get("entity_ids"))]
            assessment = text(row, "assessment", 40)
            if assessment not in {"supported", "inference", "disputed", "unknown"}:
                assessment = "unknown"
            if any(states.get(entity) != "include" for entity in entity_ids) or (
                    assessment == "supported" and not any(ref["passage_observed"] and ref["relation"] == "supports" for ref in refs)):
                assessment = "unknown"
            if any(ref["relation"] == "contradicts" for ref in refs):
                assessment = "disputed"
            if assessment != "supported":
                issues.add("claim_requires_qualification")
            claims.append({"id": identity, "statement": text(row, "statement", 1500), "entity_ids": entity_ids,
                           "assessment": assessment, "evidence": refs})
        coverage = []
        for row in data["coverage"]:
            query = text(row, "query", 1024)
            executed = query in self.queries
            status = text(row, "status", 40) if text(row, "status", 40) in {"searched", "unavailable", "not_searched"} else "not_searched"
            gap = text(row, "gap", 1000)
            if not executed or status != "searched" or gap:
                issues.add("coverage_incomplete")
            coverage.append({"facet": text(row, "facet", 300), "status": status, "query": query,
                             "query_observed": executed, "gap": gap})
        if not claims:
            issues.add("claims_missing")
        if not coverage:
            issues.add("coverage_incomplete")
        if self.truncated:
            issues.add("observation_truncated")
        self.snapshot = {"status": "recorded", "tool": TOOL, "scope": text(data, "scope", 2000),
                         "entities": entities, "claims": claims, "coverage": coverage, "issues": sorted(issues),
                         "completeness": "not_established", "semantic_verification": "not_independently_verified"}
        return self.report()

    def report(self):
        with self.lock:
            return {**deepcopy(self.snapshot or {"status": "not_submitted", "tool": TOOL}), "observed": {
                "unique_queries": len(self.queries), "source_urls": len(self.sources), "body_urls": len(self.bodies),
                "canonical_records": len({record_key(url) for url in self.sources}),
                "record_grouping": "explicit_identifier_url_aliases_only_not_independent_evidence",
                "scope": "host_observed_only_not_full_agent_activity", "truncated": self.truncated}}
