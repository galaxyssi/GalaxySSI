"""Atomic JSON storage layered beside the V1 task store."""
from __future__ import annotations

import json
import threading
from dataclasses import fields
from pathlib import Path
from typing import Any, Callable, TypeVar

from .common import atomic_write_json, read_json, safe_identifier, state_root
from .models import (
    CampaignNode,
    EvolutionCampaign,
    EvolutionProposal,
    IssueSignal,
    RadarItem,
    ResearchRun,
    RoadmapItem,
    RoadmapPlan,
    TaskMetadata,
)

T = TypeVar("T")


class EvolutionV2Store:
    def __init__(self, root: Path | None = None) -> None:
        self.root = (Path(root) if root else state_root() / "evolution" / "v2").resolve()
        self._lock = threading.RLock()
        self.paths = {
            "task_metadata": self.root / "task-metadata",
            "research": self.root / "research",
            "roadmaps": self.root / "roadmaps",
            "proposals": self.root / "proposals",
            "issues": self.root / "issues",
            "campaigns": self.root / "campaigns",
            "provenance": self.root / "provenance",
            "snapshots": self.root / "snapshots",
            "scheduler": self.root / "scheduler",
        }
        for path in self.paths.values():
            path.mkdir(parents=True, exist_ok=True)

    def _path(self, category: str, identifier: str) -> Path:
        return self.paths[category] / f"{safe_identifier(identifier)}.json"

    def save_task_metadata(self, value: TaskMetadata) -> None:
        self._save("task_metadata", value.task_id, value.public())

    def get_task_metadata(self, task_id: str) -> TaskMetadata | None:
        return self._load_dataclass("task_metadata", task_id, TaskMetadata)

    def save_research(self, value: ResearchRun) -> None:
        self._save("research", value.run_id, value.public())

    def get_research(self, run_id: str) -> ResearchRun | None:
        payload = self._read("research", run_id)
        if not isinstance(payload, dict):
            return None
        rows = [RadarItem(**_dataclass_values(RadarItem, item)) for item in payload.get("items") or []]
        return ResearchRun(**_dataclass_values(ResearchRun, {**payload, "items": rows}))

    def list_research(self, limit: int = 50) -> list[ResearchRun]:
        return self._list("research", self.get_research, limit)

    def save_roadmap(self, value: RoadmapPlan) -> None:
        self._save("roadmaps", value.roadmap_id, value.public())

    def get_roadmap(self, roadmap_id: str) -> RoadmapPlan | None:
        payload = self._read("roadmaps", roadmap_id)
        if not isinstance(payload, dict):
            return None
        items = [RoadmapItem(**_dataclass_values(RoadmapItem, item)) for item in payload.get("items") or []]
        return RoadmapPlan(**_dataclass_values(RoadmapPlan, {**payload, "items": items}))

    def list_roadmaps(self, limit: int = 50) -> list[RoadmapPlan]:
        return self._list("roadmaps", self.get_roadmap, limit)

    def save_proposal(self, value: EvolutionProposal) -> None:
        self._save("proposals", value.proposal_id, value.public())

    def get_proposal(self, proposal_id: str) -> EvolutionProposal | None:
        return self._load_dataclass("proposals", proposal_id, EvolutionProposal)

    def list_proposals(self, limit: int = 100) -> list[EvolutionProposal]:
        return self._list("proposals", self.get_proposal, limit)

    def save_issue(self, value: IssueSignal) -> None:
        self._save("issues", value.signal_id, value.public())

    def get_issue(self, signal_id: str) -> IssueSignal | None:
        return self._load_dataclass("issues", signal_id, IssueSignal)

    def list_issues(self, limit: int = 200) -> list[IssueSignal]:
        return self._list("issues", self.get_issue, limit)

    def save_campaign(self, value: EvolutionCampaign) -> None:
        self._save("campaigns", value.campaign_id, value.public())

    def get_campaign(self, campaign_id: str) -> EvolutionCampaign | None:
        payload = self._read("campaigns", campaign_id)
        if not isinstance(payload, dict):
            return None
        nodes = [CampaignNode(**_dataclass_values(CampaignNode, item)) for item in payload.get("nodes") or []]
        return EvolutionCampaign(**_dataclass_values(EvolutionCampaign, {**payload, "nodes": nodes}))

    def list_campaigns(self, limit: int = 100) -> list[EvolutionCampaign]:
        return self._list("campaigns", self.get_campaign, limit)

    def _save(self, category: str, identifier: str, payload: dict[str, Any]) -> None:
        with self._lock:
            atomic_write_json(self._path(category, identifier), payload)

    def _read(self, category: str, identifier: str) -> Any:
        with self._lock:
            return read_json(self._path(category, identifier))

    def _load_dataclass(self, category: str, identifier: str, model: type[T]) -> T | None:
        payload = self._read(category, identifier)
        if not isinstance(payload, dict):
            return None
        return model(**_dataclass_values(model, payload))

    def _list(self, category: str, loader: Callable[[str], T | None], limit: int) -> list[T]:
        rows: list[tuple[int, T]] = []
        with self._lock:
            paths = list(self.paths[category].glob("*.json"))
        for path in paths:
            value = loader(path.stem)
            if value is None:
                continue
            timestamp = int(
                getattr(value, "updated_at_millis", 0)
                or getattr(value, "completed_at_millis", 0)
                or getattr(value, "created_at_millis", 0)
            )
            rows.append((timestamp, value))
        rows.sort(key=lambda row: row[0], reverse=True)
        return [value for _, value in rows[: max(1, min(int(limit), 500))]]


def _dataclass_values(model: type[Any], payload: dict[str, Any]) -> dict[str, Any]:
    names = {item.name for item in fields(model)}
    return {key: value for key, value in payload.items() if key in names}
