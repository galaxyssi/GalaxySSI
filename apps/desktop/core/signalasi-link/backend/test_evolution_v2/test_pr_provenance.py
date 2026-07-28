from __future__ import annotations

import unittest

from evolution_v2.legacy import EvolutionAttempt, EvolutionGate, EvolutionManager, EvolutionTask


class PullRequestProvenanceTests(unittest.TestCase):
    def test_self_evolution_title_and_body_are_visibly_distinct(self):
        task = EvolutionTask(
            task_id="evolve-routing",
            problem="Improve automatic\nimplementation routing",
            reproduction_steps=[],
            scope=["apps/desktop"],
            acceptance=["All gates pass."],
            risk_level="medium",
            max_attempts=3,
            agent_id="claude-code",
            base_commit="a" * 40,
            approval_hash="b" * 64,
        )
        attempt = EvolutionAttempt(
            number=2,
            status="passed",
            branch="evolution/evolve-routing-a2",
            worktree="managed-worktree",
            gates=[EvolutionGate(id="desktop-backend-tests", status="passed", duration_millis=1250)],
        )

        self.assertEqual(
            "[Self-Evolution] Improve automatic implementation routing",
            EvolutionManager._pull_request_title(task),
        )
        body = EvolutionManager._pull_request_body(task, attempt)
        self.assertIn("- Type: `self-evolution`", body)
        self.assertIn("- Task ID: `evolve-routing`", body)
        self.assertIn(f"- Base commit: `{'a' * 40}`", body)
        self.assertIn("- Implementer: `claude-code`", body)
        self.assertIn("- Attempt: `2` of `3`", body)
        self.assertIn("`desktop-backend-tests`: passed (1250 ms)", body)


if __name__ == "__main__":
    unittest.main()
