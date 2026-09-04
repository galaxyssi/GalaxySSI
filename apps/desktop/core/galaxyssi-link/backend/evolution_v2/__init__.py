"""GalaxySSI Desktop Self-Evolution V2."""

from .agent_adapters import default_evolution_patch_agent
from .manager import EvolutionManager, evolution_manager
from .runtime import EvolutionV2Runtime, evolution_v2_runtime

__all__ = [
    "EvolutionManager",
    "EvolutionV2Runtime",
    "default_evolution_patch_agent",
    "evolution_manager",
    "evolution_v2_runtime",
]
