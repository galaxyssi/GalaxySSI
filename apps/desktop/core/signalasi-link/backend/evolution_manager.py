"""Compatibility facade: preserve the V1 public/private API while running V2."""
from evolution_v2 import legacy as _legacy

# Existing tests and modules import both public and underscore-prefixed V1 helpers.
for _name, _value in vars(_legacy).items():
    if not _name.startswith("__"):
        globals()[_name] = _value

from evolution_v2.agent_adapters import default_evolution_patch_agent  # noqa: E402,F401
from evolution_v2.manager import EvolutionManager, evolution_manager  # noqa: E402,F401

__all__ = sorted(
    {
        *[name for name in vars(_legacy) if not name.startswith("__")],
        "EvolutionManager",
        "default_evolution_patch_agent",
        "evolution_manager",
    }
)
