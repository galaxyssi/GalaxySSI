from __future__ import annotations

import unittest

import evolution_manager
from evolution_v2 import legacy
from evolution_v2.manager import EvolutionManager


class CompatibilityTests(unittest.TestCase):
    def test_v1_symbols_are_reexported(self):
        self.assertIs(evolution_manager.EvolutionError, legacy.EvolutionError)
        self.assertIs(evolution_manager.GateCommand, legacy.GateCommand)
        self.assertIs(evolution_manager.EvolutionManager, EvolutionManager)
        self.assertTrue(callable(evolution_manager._normalized_scope))


if __name__ == "__main__":
    unittest.main()
