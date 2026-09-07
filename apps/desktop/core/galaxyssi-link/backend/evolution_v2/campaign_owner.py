"""Serialize one campaign's dispatch/control transition, not child execution."""
from __future__ import annotations

from functools import wraps
import hashlib
from pathlib import Path
import re

from agent_task_dag import TaskDagError, identifier
from .os_owner import OwnerLocks


class CampaignOperationBusy(TaskDagError):
    code = "campaign_operation_busy"


def operation_owners(root: Path) -> OwnerLocks:
    return OwnerLocks(root / "campaign-owners", re.compile(r"campaign-v1-[0-9a-f]{64}"))


def campaign_operation(function):
    @wraps(function)
    def owned(self, campaign_id: str, *args, **kwargs):
        identifier(campaign_id, "campaign_id")
        key = "campaign-v1-" + hashlib.sha256(campaign_id.encode("utf-8")).hexdigest()
        with self.operation_owners.hold(key, create=True) as acquired:
            if not acquired:
                raise CampaignOperationBusy("Another executor is advancing this campaign; retry after its operation finishes")
            return function(self, campaign_id, *args, **kwargs)
    return owned
