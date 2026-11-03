import unittest

from collaboration_recall_bridge import RESPONSE, RecallBroker, tool_spec, validate_arguments


class WorkflowCheckBridgeTest(unittest.TestCase):
    def arguments(self, **changes):
        return dict(mode="workflow_check", object_id="a" * 64, revision=1, sha256="b" * 64,
                    inputs={"data": {"count": 3, "mutable": False}}, **changes)

    def test_schema_exposes_typed_inputs_and_inspection_not_execution(self):
        spec = tool_spec()
        self.assertIn("workflow_check", spec["inputSchema"]["properties"]["mode"]["enum"])
        self.assertEqual("object", spec["inputSchema"]["properties"]["inputs"]["type"])
        self.assertIn("not method quality or probe value", spec["description"])

    def test_partial_inputs_are_deep_copied_without_coercion(self):
        values = self.arguments()
        values["inputs"]["data"].update(count="3", nullable=None, examples=[False, 4])
        checked = validate_arguments(values)
        self.assertEqual(values, checked)
        checked["inputs"]["data"]["count"] = 99
        self.assertEqual("3", values["inputs"]["data"]["count"])
        self.assertEqual({}, validate_arguments({**values, "inputs": {}})["inputs"])

    def test_invalid_or_oversized_json_and_foreign_selectors_are_rejected(self):
        base = self.arguments()
        for value in ("{}", None, [], {1: 2}, {"data": float("nan")}, {"data": float("inf")},
                      {"data": (1, 2)}, {"data": "x" * 4096}, {"data": "\U0001f600" * 2000}):
            with self.subTest(value=str(value)[:40]), self.assertRaises(ValueError):
                validate_arguments({**base, "inputs": value})
        for key, value in (("revision", True), ("revision", 0), ("sha256", "x" * 64),
                           ("offset", -1), ("cursor", ""), ("group_id", "other"), ("query", "find")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_arguments({**base, key: value})
        for key in base:
            with self.assertRaises(ValueError):
                validate_arguments({k: v for k, v in base.items() if k != key})

    def test_inputs_are_not_accepted_by_other_modes(self):
        for mode in tool_spec()["inputSchema"]["properties"]["mode"]["enum"]:
            if mode != "workflow_check":
                with self.subTest(mode=mode), self.assertRaises(ValueError):
                    validate_arguments({"mode": mode, "inputs": {}})

    def test_bound_phone_round_trip_has_no_observation_confirmation_or_task_dispatch(self):
        task = dict(task_id="task", client_route_id="phone", client_conversation_id="group", client_turn_id="turn",
                    source_message_id="42", contact_id="contact", agent_id="codex", status="running", execution_generation=1)
        broker = RecallBroker()
        arguments = self.arguments(offset=0)
        expected = {"success": True, "content": "declared condition inspection", "next_offset": None}
        calls = []
        def publish(request):
            calls.append(request)
            self.assertEqual(arguments, request["arguments"])
            self.assertFalse(broker.receive({**request, "type": RESPONSE, "result": expected}, "other-phone"))
            self.assertFalse(broker.receive({**request, "type": RESPONSE, "turn_id": "other", "result": expected}, "phone"))
            self.assertTrue(broker.receive({**request, "type": RESPONSE, "result": expected}, "phone"))
            return True
        self.assertEqual(expected, broker.query(lambda: task, arguments, publish))
        self.assertEqual(["read"], [request["phase"] for request in calls])
        self.assertEqual({}, broker._pending)


if __name__ == "__main__":
    unittest.main()
