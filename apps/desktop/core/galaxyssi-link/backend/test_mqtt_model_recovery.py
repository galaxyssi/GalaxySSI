import unittest

import mqtt_bridge


class MqttModelRecoveryTests(unittest.TestCase):
    def tearDown(self):
        with mqtt_bridge.codex_task_callbacks_lock:
            mqtt_bridge.codex_task_callbacks.pop("task-recovery", None)

    def test_terminal_codex_event_keeps_callback_when_recovery_turn_is_scheduled(self):
        def callback(_task_id, event):
            event["_galaxyssi_keep_callback"] = True

        with mqtt_bridge.codex_task_callbacks_lock:
            mqtt_bridge.codex_task_callbacks["task-recovery"] = callback

        mqtt_bridge._dispatch_codex_event(
            "task-recovery",
            {"status": "completed", "result": "internal recovery request"},
        )

        with mqtt_bridge.codex_task_callbacks_lock:
            self.assertIs(callback, mqtt_bridge.codex_task_callbacks.get("task-recovery"))

    def test_terminal_codex_event_removes_callback_without_recovery(self):
        callback = lambda _task_id, _event: None
        with mqtt_bridge.codex_task_callbacks_lock:
            mqtt_bridge.codex_task_callbacks["task-recovery"] = callback

        mqtt_bridge._dispatch_codex_event(
            "task-recovery",
            {"status": "completed", "result": "done"},
        )

        with mqtt_bridge.codex_task_callbacks_lock:
            self.assertNotIn("task-recovery", mqtt_bridge.codex_task_callbacks)


if __name__ == "__main__":
    unittest.main()
