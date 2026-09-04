import unittest

from security_red_team import ATTACK_CASES, run_security_red_team


class SecurityRedTeamTests(unittest.TestCase):
    def test_all_required_attack_surfaces_are_covered(self):
        surfaces = {case.surface for case in ATTACK_CASES}
        self.assertEqual({"readme", "web", "mcp", "model_output"}, surfaces)
        self.assertGreaterEqual(len(ATTACK_CASES), 16)

    def test_all_attack_cases_preserve_the_host_boundary_and_detect_tampering(self):
        results = run_security_red_team()
        failures = [result for result in results if not result.passed]
        self.assertEqual([], failures)
        self.assertEqual(len(ATTACK_CASES), len(results))
        self.assertTrue(all(len(result.checks) == 5 for result in results))


if __name__ == "__main__":
    unittest.main()
