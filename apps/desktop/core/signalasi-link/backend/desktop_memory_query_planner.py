"""Deterministic multi-intent query planning for Desktop long-term memory."""
from __future__ import annotations

import re
from dataclasses import dataclass


QUERY_TYPES = {
    "project_state",
    "device_capability",
    "historical_decision",
    "personal_identity",
    "personal_preference",
    "security_state",
    "long_term_goal",
    "tool_evidence",
    "relationship",
    "general",
}
TEMPORAL_SCOPES = {"current", "history", "current_and_history"}


@dataclass(frozen=True)
class DesktopMemoryQueryPlan:
    types: tuple[str, ...]
    temporal_scope: str
    namespaces: tuple[str, ...]
    preferred_kinds: tuple[str, ...]
    preferred_relations: tuple[str, ...]
    graph_hops: int
    maximum_memories: int
    maximum_graph_nodes: int
    maximum_characters: int

    @property
    def include_historical(self) -> bool:
        return self.temporal_scope != "current"

    def as_dict(self) -> dict[str, object]:
        return {
            "types": list(self.types),
            "temporal_scope": self.temporal_scope,
            "namespaces": list(self.namespaces),
            "preferred_kinds": list(self.preferred_kinds),
            "preferred_relations": list(self.preferred_relations),
            "graph_hops": self.graph_hops,
            "maximum_memories": self.maximum_memories,
            "maximum_graph_nodes": self.maximum_graph_nodes,
            "maximum_characters": self.maximum_characters,
        }


def plan_memory_query(query: str) -> DesktopMemoryQueryPlan:
    value = _normalize(query)
    types: list[str] = []
    _append_if(types, "historical_decision", _contains_any(value, HISTORICAL_TERMS))
    _append_if(types, "relationship", _contains_any(value, RELATIONSHIP_TERMS))
    _append_if(types, "device_capability", _contains_any(value, DEVICE_TERMS))
    _append_if(types, "personal_identity", _contains_any(value, IDENTITY_TERMS))
    _append_if(types, "personal_preference", _contains_any(value, PREFERENCE_TERMS))
    _append_if(types, "security_state", _contains_any(value, SECURITY_TERMS))
    _append_if(types, "long_term_goal", _contains_any(value, GOAL_TERMS))
    _append_if(types, "tool_evidence", _contains_any(value, TOOL_TERMS))
    _append_if(types, "project_state", _contains_any(value, PROJECT_TERMS))
    if not types:
        types.append("general")

    temporal_scope = "current"
    if "historical_decision" in types:
        temporal_scope = (
            "current_and_history"
            if _contains_any(value, CURRENT_OR_COMPARISON_TERMS)
            else "history"
        )
    profiles = [TYPE_PROFILES[query_type] for query_type in types]
    namespaces = _ordered_union(profile["namespaces"] for profile in profiles)
    kinds = _ordered_union(profile["kinds"] for profile in profiles)
    relations = _preferred_relations(value)
    return DesktopMemoryQueryPlan(
        types=tuple(types),
        temporal_scope=temporal_scope,
        namespaces=tuple(namespaces),
        preferred_kinds=tuple(kinds),
        preferred_relations=tuple(relations),
        graph_hops=max(int(profile["graph_hops"]) for profile in profiles),
        maximum_memories=max(int(profile["maximum_memories"]) for profile in profiles),
        maximum_graph_nodes=max(int(profile["maximum_graph_nodes"]) for profile in profiles),
        maximum_characters=max(int(profile["maximum_characters"]) for profile in profiles),
    )


def _append_if(values: list[str], value: str, condition: bool) -> None:
    if condition:
        values.append(value)


def _normalize(value: str) -> str:
    return re.sub(r"\s+", " ", str(value or "").casefold()).strip()


def _contains_any(value: str, terms: tuple[str, ...]) -> bool:
    for term in terms:
        if any(ord(character) > 127 for character in term):
            if term in value:
                return True
        elif re.search(rf"(?<![a-z0-9_]){re.escape(term)}(?![a-z0-9_])", value):
            return True
    return False


def _ordered_union(groups) -> list[str]:
    values: list[str] = []
    for group in groups:
        for value in group:
            if value not in values:
                values.append(value)
    return values


def _preferred_relations(value: str) -> list[str]:
    relations: list[str] = []
    for relation, terms in RELATION_TERM_MAP:
        if _contains_any(value, terms):
            relations.append(relation)
    return relations


TYPE_PROFILES = {
    "project_state": {
        "namespaces": ("project",),
        "kinds": ("project_state", "decision", "goal", "episode", "fact"),
        "graph_hops": 2,
        "maximum_memories": 18,
        "maximum_graph_nodes": 20,
        "maximum_characters": 5_500,
    },
    "device_capability": {
        "namespaces": ("device",),
        "kinds": ("device_state", "fact", "decision"),
        "graph_hops": 3,
        "maximum_memories": 16,
        "maximum_graph_nodes": 28,
        "maximum_characters": 5_500,
    },
    "historical_decision": {
        "namespaces": (),
        "kinds": ("decision", "project_state", "device_state", "fact"),
        "graph_hops": 2,
        "maximum_memories": 24,
        "maximum_graph_nodes": 24,
        "maximum_characters": 7_000,
    },
    "personal_identity": {
        "namespaces": ("user",),
        "kinds": ("identity", "explicit", "fact", "preference"),
        "graph_hops": 2,
        "maximum_memories": 12,
        "maximum_graph_nodes": 16,
        "maximum_characters": 4_000,
    },
    "personal_preference": {
        "namespaces": ("user",),
        "kinds": ("preference", "decision", "explicit"),
        "graph_hops": 1,
        "maximum_memories": 12,
        "maximum_graph_nodes": 12,
        "maximum_characters": 4_000,
    },
    "security_state": {
        "namespaces": ("security",),
        "kinds": ("security", "decision", "fact"),
        "graph_hops": 2,
        "maximum_memories": 14,
        "maximum_graph_nodes": 18,
        "maximum_characters": 4_500,
    },
    "long_term_goal": {
        "namespaces": ("project",),
        "kinds": ("goal", "project_state", "episode"),
        "graph_hops": 2,
        "maximum_memories": 18,
        "maximum_graph_nodes": 20,
        "maximum_characters": 5_500,
    },
    "tool_evidence": {
        "namespaces": ("project", "device", "general"),
        "kinds": ("episode", "device_state", "project_state", "fact"),
        "graph_hops": 1,
        "maximum_memories": 14,
        "maximum_graph_nodes": 14,
        "maximum_characters": 5_000,
    },
    "relationship": {
        "namespaces": (),
        "kinds": ("fact", "device_state", "project_state", "preference"),
        "graph_hops": 3,
        "maximum_memories": 18,
        "maximum_graph_nodes": 32,
        "maximum_characters": 6_000,
    },
    "general": {
        "namespaces": (),
        "kinds": (),
        "graph_hops": 2,
        "maximum_memories": 16,
        "maximum_graph_nodes": 18,
        "maximum_characters": 5_000,
    },
}


HISTORICAL_TERMS = (
    "previous",
    "previously",
    "earlier",
    "prior",
    "what happened before",
    "what was before",
    "historical",
    "history",
    "used to",
    "decision",
    "\u4e4b\u524d",
    "\u4ee5\u524d",
    "\u66fe\u7ecf",
    "\u5386\u53f2",
    "\u51b3\u5b9a",
    "\u6539\u53e3",
)
CURRENT_OR_COMPARISON_TERMS = (
    "now",
    "current",
    "currently",
    "today",
    "changed",
    "compare",
    "then and now",
    "\u73b0\u5728",
    "\u5f53\u524d",
    "\u4eca\u5929",
    "\u6539\u4e86",
    "\u53d8\u5316",
    "\u5bf9\u6bd4",
    "\u5f53\u65f6\u548c\u73b0\u5728",
)
DEVICE_TERMS = (
    "device",
    "phone",
    "android",
    "battery",
    "chip",
    "ram",
    "gpu",
    "npu",
    "model",
    "runtime",
    "\u8bbe\u5907",
    "\u624b\u673a",
    "\u7535\u6c60",
    "\u82af\u7247",
    "\u5185\u5b58",
    "\u578b\u53f7",
    "\u672c\u673a",
)
PREFERENCE_TERMS = (
    "prefer",
    "preference",
    "favorite",
    "default style",
    "my style",
    "\u504f\u597d",
    "\u559c\u6b22",
    "\u9ed8\u8ba4",
    "\u6211\u7684\u98ce\u683c",
)
IDENTITY_TERMS = (
    "who am i",
    "my identity",
    "my name",
    "my profile",
    "about me",
    "account owner",
    "\u6211\u662f\u8c01",
    "\u6211\u7684\u8eab\u4efd",
    "\u6211\u7684\u540d\u5b57",
    "\u6211\u7684\u8d44\u6599",
    "\u5173\u4e8e\u6211",
)
SECURITY_TERMS = (
    "security",
    "privacy",
    "permission",
    "authorization",
    "trust",
    "trusted device",
    "safety policy",
    "\u5b89\u5168",
    "\u9690\u79c1",
    "\u6743\u9650",
    "\u6388\u6743",
    "\u4fe1\u4efb",
    "\u53ef\u4fe1\u8bbe\u5907",
    "\u5b89\u5168\u7b56\u7565",
)
GOAL_TERMS = (
    "goal",
    "objective",
    "roadmap",
    "long term",
    "long-term",
    "next milestone",
    "\u76ee\u6807",
    "\u8def\u7ebf\u56fe",
    "\u957f\u671f",
    "\u91cc\u7a0b\u7891",
    "\u4e0b\u4e00\u6b65",
)
TOOL_TERMS = (
    "tool",
    "command",
    "result",
    "output",
    "run",
    "terminal",
    "log",
    "\u5de5\u5177",
    "\u547d\u4ee4",
    "\u7ed3\u679c",
    "\u8f93\u51fa",
    "\u65e5\u5fd7",
    "\u8fd0\u884c",
)
PROJECT_TERMS = (
    "project",
    "task",
    "feature",
    "bug",
    "build",
    "release",
    "\u9879\u76ee",
    "\u4efb\u52a1",
    "\u529f\u80fd",
    "\u7f3a\u9677",
    "\u6784\u5efa",
    "\u53d1\u5e03",
)
RELATIONSHIP_TERMS = (
    "relationship",
    "related",
    "connected",
    "depend on",
    "depends on",
    "uses",
    "support",
    "supports",
    "belongs to",
    "paired",
    "owns",
    "contains",
    "component",
    "renamed",
    "state is",
    "status is",
    "\u5173\u7cfb",
    "\u76f8\u5173",
    "\u8fde\u63a5",
    "\u4f9d\u8d56",
    "\u4f7f\u7528",
    "\u652f\u6301",
    "\u5c5e\u4e8e",
    "\u914d\u5bf9",
    "\u62e5\u6709",
    "\u5305\u542b",
    "\u7ec4\u6210",
    "\u66f4\u540d",
    "\u72b6\u6001\u4e3a",
)

RELATION_TERM_MAP = (
    ("owns", ("owns", "owned by", "\u62e5\u6709", "\u5c5e\u4e8e")),
    ("uses", ("uses", "using", "used by", "use of", "\u4f7f\u7528")),
    ("supports", ("supports", "support", "\u652f\u6301")),
    ("has_component", ("contains", "component", "composed of", "\u5305\u542b", "\u7ec4\u6210")),
    ("has_state", ("state is", "status is", "current state", "\u72b6\u6001\u4e3a", "\u5f53\u524d\u72b6\u6001")),
    ("named_as", ("renamed", "named as", "called", "\u66f4\u540d", "\u547d\u540d", "\u53eb\u4ec0\u4e48")),
    ("depends_on", ("depend on", "depends on", "requires", "\u4f9d\u8d56", "\u9700\u8981")),
    ("connected_to", ("connected", "paired", "\u8fde\u63a5", "\u914d\u5bf9")),
    ("prefers", ("prefers", "preference", "\u504f\u597d", "\u559c\u6b22")),
    ("removed", ("removed", "deleted", "deprecated", "\u79fb\u9664", "\u5220\u9664", "\u5e9f\u5f03")),
)
