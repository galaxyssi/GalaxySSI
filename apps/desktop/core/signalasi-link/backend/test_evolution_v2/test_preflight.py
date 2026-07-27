from pathlib import Path
import unittest

from evolution_v2.preflight import PreflightInspector
from evolution_v2.runner import CommandResult


class FakeRunner:
    def __init__(self, resolved: str = "") -> None:
        self.resolved = resolved
        self.calls: list[tuple[str, ...]] = []

    def which(self, _name: str) -> str:
        return self.resolved

    def run(self, argv, cwd, **_kwargs) -> CommandResult:
        values = tuple(str(item) for item in argv)
        self.calls.append(values)
        return CommandResult(list(values), str(cwd), 0, "11.13.0\n", 1)


class PreflightInspectorTests(unittest.TestCase):
    def test_command_runs_the_resolved_windows_launcher(self) -> None:
        runner = FakeRunner(r"C:\tools\npm.CMD")
        inspector = PreflightInspector(Path.cwd(), runner=runner)

        check = inspector._command("npm", ("npm", "--version"), required=True)

        self.assertEqual("passed", check.status)
        self.assertEqual((r"C:\tools\npm.CMD", "--version"), runner.calls[0])

    def test_command_reports_a_missing_required_tool(self) -> None:
        inspector = PreflightInspector(Path.cwd(), runner=FakeRunner())

        check = inspector._command("missing", ("missing-tool", "--version"), required=True)

        self.assertEqual("missing", check.status)
        self.assertTrue(check.required)


if __name__ == "__main__":
    unittest.main()
