"""Route-body checks without importing main's process-wide startup services."""
import ast
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


class MqttDiagnosticsApiTest(unittest.TestCase):
    def setUp(self):
        tree = ast.parse(Path(__file__).with_name("main.py").read_text(encoding="utf-8-sig"))
        function = next(item for item in tree.body if isinstance(item, ast.FunctionDef)
                        and item.name == "api_link_transport_diagnostics")
        self.assertEqual("/api/link/transport-diagnostics", function.decorator_list[0].args[0].value)
        function.decorator_list = []
        self.guard = Mock()
        namespace = {"Request": object, "require_loopback": self.guard}
        exec(compile(ast.Module(body=[function], type_ignores=[]), "diagnostic-route", "exec"), namespace)
        self.route = namespace[function.name]
        self.snapshot = Mock(return_value={"counts": {"duplicate_message": 2}})
        self.health = Mock(return_value={"connected": True, "ready": False, "scheduling": {"verified_delivery": {}}})
        self.modules = patch.dict("sys.modules", {
            "link_transport_diagnostics": SimpleNamespace(link_transport_diagnostics=lambda: SimpleNamespace(snapshot=self.snapshot)),
            "mqtt_bridge": SimpleNamespace(mqtt_bridge_status=self.health),
        })
        self.modules.start()
        self.addCleanup(self.modules.stop)

    def test_existing_counts_and_live_transport_are_both_returned(self):
        request = object()
        result = self.route(request)
        self.guard.assert_called_once_with(request)
        self.assertEqual(2, result["counts"]["duplicate_message"])
        self.assertFalse(result["mqtt"]["ready"])
        self.assertIn("verified_delivery", result["mqtt"]["scheduling"])
        self.health.assert_called_once_with()

    def test_remote_request_is_rejected_before_observation(self):
        self.guard.side_effect = PermissionError("loopback only")
        with self.assertRaises(PermissionError):
            self.route(object())
        self.snapshot.assert_not_called()
        self.health.assert_not_called()

    def test_unavailable_transport_is_not_fabricated_as_healthy(self):
        self.health.side_effect = RuntimeError("owned status failure")
        with self.assertRaises(RuntimeError):
            self.route(object())


if __name__ == "__main__":
    unittest.main()
