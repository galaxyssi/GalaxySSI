import unittest

from phone_planner_session import phone_planner_session


class PhonePlannerSessionTests(unittest.TestCase):
    def test_stable_identity_and_every_isolation_dimension(self):
        values = dict(mode="phone_supervised_project_plan_v1", client_route="phone-a",
                      conversation="chat-a", turn="goal-a", model="model-a", instance="agent-a")
        expected = phone_planner_session(**values)
        self.assertTrue(expected.startswith("phone-planner-v1:"))
        self.assertEqual(expected, phone_planner_session(**values))
        for field in ("client_route", "conversation", "turn", "model", "instance"):
            with self.subTest(field=field):
                self.assertNotEqual(expected, phone_planner_session(**{**values, field: "different"}))
        for field in ("client_route", "conversation", "turn"):
            with self.subTest(missing=field):
                self.assertEqual("", phone_planner_session(**{**values, field: " "}))
        for mode in ("", "chat", "screen_analysis"):
            self.assertEqual("", phone_planner_session(**{**values, "mode": mode}))
        self.assertNotIn("phone-a", expected)


if __name__ == "__main__":
    unittest.main()
