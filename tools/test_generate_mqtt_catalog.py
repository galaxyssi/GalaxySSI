import json
import tempfile
import unittest
from pathlib import Path

from tools.generate_mqtt_catalog import ROOT, outputs


class BrokerCatalogTests(unittest.TestCase):
    def fixture(self, mutate):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / "config").mkdir()
        spec = json.loads((ROOT / "config/mqtt-multipath.json").read_text(encoding="utf-8"))
        mutate(spec)
        (root / "config/mqtt-multipath.json").write_text(json.dumps(spec), encoding="utf-8")
        return root

    def test_generated_android_and_desktop_catalogs_are_current(self):
        for path, content in outputs().items():
            with self.subTest(path=path.name):
                self.assertEqual(content, path.read_text(encoding="utf-8"))

    def test_default_or_manual_selection_is_rejected(self):
        for mutate in [lambda value: value.update(default_broker="emqx"),
                       lambda value: value.update(selection="manual"),
                       lambda value: value["brokers"]["emqx"].update(priority=1)]:
            with self.assertRaises(ValueError):
                outputs(self.fixture(mutate))

    def test_requires_three_candidates_and_strict_new_version(self):
        for mutate in [lambda value: value["brokers"].pop("mosquitto"),
                       lambda value: value.update(transport_version=True),
                       lambda value: value.update(transport_version=0)]:
            with self.assertRaises(ValueError):
                outputs(self.fixture(mutate))

    def test_rejects_unbounded_or_inconsistent_budgets(self):
        for mutate in [lambda value: value["limits"].update(global_inflight_packets=0),
                       lambda value: value["limits"].update(reserved_control_packets=12),
                       lambda value: value["limits"].update(small_packet_bytes=2_097_152),
                       lambda value: value["timing"].update(hedge_min_ms=3000),
                       lambda value: value["timing"].update(keepalive_seconds=True)]:
            with self.assertRaises(ValueError):
                outputs(self.fixture(mutate))

    def test_endpoint_values_cannot_inject_generated_source_or_disable_tls(self):
        for mutate in [lambda value: value["brokers"]["emqx"].update(host='"; bad()'),
                       lambda value: value["brokers"]["emqx"].update(tls_port="8883"),
                       lambda value: value["brokers"]["emqx"].update(tls=False)]:
            with self.assertRaises(ValueError):
                outputs(self.fixture(mutate))


if __name__ == "__main__":
    unittest.main()
