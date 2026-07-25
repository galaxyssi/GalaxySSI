import inspect
import unittest

import mqtt_bridge


class MqttNarrationBoundaryTests(unittest.TestCase):
    def test_host_does_not_synthesize_assistant_narration(self):
        source = inspect.getsource(mqtt_bridge._start_remote_agent_task)

        self.assertFalse(hasattr(mqtt_bridge, "_initial_codex_narration"))
        self.assertNotIn("signalasi:ack", source)
        self.assertNotIn("signalasi_host", source)
        self.assertNotIn("acknowledgement", source)


if __name__ == "__main__":
    unittest.main()
