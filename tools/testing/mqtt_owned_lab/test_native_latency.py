import unittest
from unittest.mock import AsyncMock, patch

import native_latency


class NativeLatencyExitTests(unittest.IsolatedAsyncioTestCase):
    async def verdict(self, passed, fault=False):
        report = {"status": "measured_with_business_checks_passed",
                  "provisional_small_message_gate": {"passed": passed}}
        if fault:
            report.update(provisional_small_message_gate=None, provisional_fault_gate={"passed": passed})
        with patch("sys.argv", ["native_latency.py", "--endpoint-python", "unused-python",
                                "--report-dir", "unused-report"]), \
                patch.object(native_latency, "OwnedBrokers") as factory, \
                patch.object(native_latency.asyncio, "to_thread", new_callable=AsyncMock) as run, \
                patch("builtins.print"):
            factory.return_value.__aenter__.return_value = object()
            run.return_value = report
            result = await native_latency.main()
            factory.return_value.__aexit__.assert_awaited_once()
            return result

    async def test_business_success_cannot_hide_failed_performance_gate(self):
        self.assertEqual(2, await self.verdict(False))

    async def test_limited_gate_success_returns_zero(self):
        self.assertEqual(0, await self.verdict(True))

    async def test_fault_gate_failure_cannot_exit_successfully(self):
        self.assertEqual(2, await self.verdict(False, fault=True))

    async def test_fault_gate_success_does_not_require_a_warm_comparison(self):
        self.assertEqual(0, await self.verdict(True, fault=True))

    def test_invalid_sample_budget_fails_before_broker_or_file_access(self):
        for count in (0, 29, 31, 181):
            with self.subTest(count=count), self.assertRaises(ValueError):
                native_latency.run(None, None, None, None, count, 0)


if __name__ == "__main__":
    unittest.main()
