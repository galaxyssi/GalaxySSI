from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from evolution_v2.policy import EvolutionPolicy


class PolicyTests(unittest.TestCase):
    def test_risk_is_elevated_for_high_and_critical_paths(self):
        with tempfile.TemporaryDirectory() as root:
            policy = EvolutionPolicy(Path(root), Path(root) / "missing.json")
            high = policy.decide(["apps/desktop/src/main.js"], "low")
            critical = policy.decide(["apps/android/app/src/main/AndroidManifest.xml"], "medium")
            self.assertEqual("high", high.effective_risk)
            self.assertEqual("critical", critical.effective_risk)
            self.assertTrue(high.allowed)
            self.assertTrue(critical.approval_required)

    def test_protected_scope_is_denied(self):
        with tempfile.TemporaryDirectory() as root:
            policy = EvolutionPolicy(Path(root), Path(root) / "missing.json")
            decision = policy.decide([".github/workflows/release.yml"], "low")
            self.assertFalse(decision.allowed)
            self.assertEqual("critical", decision.effective_risk)

    def test_candidate_cannot_modify_the_policy_or_its_own_guard(self):
        with tempfile.TemporaryDirectory() as root:
            policy = EvolutionPolicy(Path(root), Path(root) / "missing.json")
            for path in (
                "config/evolution-policy.json",
                "config/evolution-gates.json",
                "apps/desktop/core/galaxyssi-link/backend/evolution_v2/gates.py",
            ):
                with self.subTest(path=path):
                    decision = policy.decide([path], "low")
                    self.assertFalse(decision.allowed)
                    self.assertEqual("critical", decision.effective_risk)

    def test_auto_merge_remains_disabled_by_default(self):
        with tempfile.TemporaryDirectory() as root:
            policy = EvolutionPolicy(Path(root), Path(root) / "missing.json")
            decision = policy.decide(["docs/SELF_EVOLUTION.md"], "low")
            self.assertFalse(decision.auto_publish)
            self.assertFalse(decision.auto_merge)


if __name__ == "__main__":
    unittest.main()
