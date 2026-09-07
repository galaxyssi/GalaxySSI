"""OS-held CI observer ownership, independent of PID reuse and wall-clock leases."""
from __future__ import annotations

from pathlib import Path
import re

from .os_owner import OwnerLocks, OwnerLockUnavailable


OWNER_PATTERN = re.compile(r"ci-lock-v1-[0-9a-f]{32}$")


class CiOwnerLocks(OwnerLocks):
    def __init__(self, root: Path):
        super().__init__(root, OWNER_PATTERN)
