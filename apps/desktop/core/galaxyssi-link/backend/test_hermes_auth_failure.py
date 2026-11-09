import unittest

from agent_gateway import BASE_AGENTS, _agent_reply_failed, clean_agent_output
from agent_execution_harness import looks_failed_reply


class HermesAuthenticationFailureTests(unittest.TestCase):
    def test_exit_zero_authentication_diagnostic_is_a_failure(self):
        raw = "HTTP 401: Authentication Fails, Your api key: ****test is invalid (request_id: synthetic)"
        reply = clean_agent_output(BASE_AGENTS["hermes"], raw)
        self.assertTrue(_agent_reply_failed(reply))
        self.assertTrue(looks_failed_reply(reply))
        self.assertNotIn("****test", reply)
        self.assertNotIn("synthetic", reply)

    def test_normal_answer_and_quoted_error_are_not_reclassified(self):
        for raw in ("Hello", "HTTP 401 means unauthorized.",
                    "The log says: HTTP 401: Authentication Fails",
                    "HTTP 401: Authentication Fails\nThis example explains a server response."):
            with self.subTest(raw=raw):
                reply = clean_agent_output(BASE_AGENTS["hermes"], raw)
                self.assertEqual(raw, reply)
                self.assertFalse(_agent_reply_failed(reply))

    def test_other_connectors_are_not_changed(self):
        raw = "HTTP 401: Authentication Fails"
        self.assertEqual(raw, clean_agent_output(BASE_AGENTS["codex"], raw))


if __name__ == "__main__":
    unittest.main()
