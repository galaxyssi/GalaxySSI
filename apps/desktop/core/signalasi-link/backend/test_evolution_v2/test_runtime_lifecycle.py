from __future__ import annotations

import unittest
from unittest.mock import Mock, patch

from evolution_v2.runtime import EvolutionV2Runtime


class EvolutionRuntimeLifecycleTests(unittest.TestCase):
    def runtime(self, *, enabled: bool):
        manager = Mock()
        manager.recover_interrupted.return_value = ["task-one"]
        scheduler = Mock()
        scheduler.config = {"enabled": enabled}
        with (
            patch("evolution_v2.runtime.evolution_manager", return_value=manager),
            patch("evolution_v2.runtime.EvolutionScheduler", return_value=scheduler),
        ):
            runtime = EvolutionV2Runtime()
        return runtime, manager, scheduler

    def test_disabled_runtime_rolls_back_without_resuming_interrupted_work(self) -> None:
        runtime, manager, scheduler = self.runtime(enabled=False)

        runtime.start()

        manager.recover_interrupted.assert_called_once_with(resume=False)
        scheduler.start.assert_called_once_with()
        manager.audit.append.assert_called_once_with(
            "runtime_started",
            payload={
                "recovered_tasks": ["task-one"],
                "resumed_interrupted": False,
            },
        )

    def test_explicitly_enabled_runtime_resumes_interrupted_work(self) -> None:
        runtime, manager, scheduler = self.runtime(enabled=True)

        runtime.start()

        manager.recover_interrupted.assert_called_once_with(resume=True)
        scheduler.start.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
