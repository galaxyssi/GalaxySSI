from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from evolution_v2.models import RadarItem, ResearchRun
from evolution_v2.roadmap import RoadmapPlanner
from evolution_v2.storage import EvolutionV2Store


class RoadmapTests(unittest.TestCase):
    def test_all_horizons_are_present(self):
        with tempfile.TemporaryDirectory() as root:
            store = EvolutionV2Store(Path(root))
            run = ResearchRun(
                run_id="research-1",
                query="agents",
                status="completed",
                items=[RadarItem(
                    item_id="radar-1",
                    repository="modelcontextprotocol/modelcontextprotocol",
                    name="modelcontextprotocol",
                    description="MCP",
                    total_score=90,
                    integration_targets=["MCP interoperability"],
                )],
            )
            plan = RoadmapPlanner(store).create("super agent", [run])
            horizons = {item.horizon for item in plan.items}
            self.assertEqual({"0-3-months", "3-12-months", "1-2-years", "3-5-years"}, horizons)
            self.assertTrue(any("modelcontextprotocol" in " ".join(item.candidate_sources) for item in plan.items))


if __name__ == "__main__":
    unittest.main()
