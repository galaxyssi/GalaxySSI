from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from evolution_v2.models import RadarItem, ResearchRun, RoadmapItem, RoadmapPlan, TaskMetadata
from evolution_v2.storage import EvolutionV2Store


class StorageTests(unittest.TestCase):
    def test_nested_models_round_trip(self):
        with tempfile.TemporaryDirectory() as root:
            store = EvolutionV2Store(Path(root))
            run = ResearchRun("research-1", "query", status="completed", items=[
                RadarItem("radar-1", "openai/codex", "codex", "agent", total_score=91)
            ])
            store.save_research(run)
            restored = store.get_research("research-1")
            self.assertIsNotNone(restored)
            self.assertEqual("openai/codex", restored.items[0].repository)

            roadmap = RoadmapPlan("roadmap-1", "title", "goal", items=[
                RoadmapItem("item-1", "safe harness", "0-3-months", "verification", "outcome", "why")
            ])
            store.save_roadmap(roadmap)
            self.assertEqual("safe harness", store.get_roadmap("roadmap-1").items[0].title)

            metadata = TaskMetadata("task-1", research_run_ids=["research-1"])
            store.save_task_metadata(metadata)
            self.assertEqual(["research-1"], store.get_task_metadata("task-1").research_run_ids)


if __name__ == "__main__":
    unittest.main()
