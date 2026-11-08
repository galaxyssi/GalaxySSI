import json
import subprocess
import sys
import unittest

from codex_cli_stream import collect_codex_stream, final_codex_answer, supports_json_stream


class CodexCliStreamTest(unittest.TestCase):
    def test_only_native_exec_commands_are_changed(self):
        self.assertTrue(supports_json_stream(["C:/tools/codex.exe", "exec", "-"]))
        self.assertTrue(supports_json_stream(["codex.cmd", "exec", "resume", "abc", "-"]))
        self.assertFalse(supports_json_stream([sys.executable, "wrapper.py", "exec"]))
        self.assertFalse(supports_json_stream(["codex", "app-server"]))

    def test_answer_arrives_before_process_exit_without_tool_or_reasoning_leaks(self):
        events = [
            {"type": "turn.started"},
            {"type": "item.completed", "item": {"type": "reasoning", "text": "PRIVATE"}},
            {"type": "error", "message": "Reconnecting... 1/5 (secret detail)"},
            {"type": "item.completed", "item": {"type": "error", "message": "Falling back from WebSockets to HTTPS transport."}},
            {"type": "item.completed", "item": {"id": "a", "type": "agent_message", "text": "Answer"}},
            {"type": "turn.completed"},
        ]
        script = "import json,sys,time\nsys.stdin.read()\n"
        script += f"events = {events!r}\n"
        script += "for event in events: print(json.dumps(event), flush=True)\n"
        script += "sys.stderr.write('diagnostic\\n'); sys.stderr.flush(); time.sleep(1)\n"
        process = subprocess.Popen([sys.executable, "-c", script], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        observed = []
        with process:
            out, err = collect_codex_stream(process, input_bytes=b"input", timeout=5,
                on_event=lambda kind, text, elapsed: observed.append((kind, text, process.poll(), elapsed)))
        self.assertEqual("Answer", final_codex_answer(out.decode()))
        self.assertEqual(b"diagnostic\n", err.replace(b"\r\n", b"\n"))
        answer = next(event for event in observed if event[0] == "answer")
        self.assertIsNone(answer[2])
        self.assertNotIn("PRIVATE", str(observed))
        self.assertNotIn("secret detail", str(observed))
        self.assertEqual(["model_started", "reconnecting", "https_fallback", "answer", "model_completed"], [event[0] for event in observed])

    def test_timeout_terminates_child(self):
        process = subprocess.Popen([sys.executable, "-c", "import sys,time; sys.stdin.read(); time.sleep(30)"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with process, self.assertRaises(subprocess.TimeoutExpired):
            collect_codex_stream(process, input_bytes=b"x", timeout=0.2, on_event=lambda *args: None)
        self.assertIsNotNone(process.poll())

    def test_final_answer_ignores_invalid_lines_and_deduplicates_items(self):
        def answer(id, text):
            return json.dumps({"type": "item.completed", "item": {"type": "agent_message", "id": id, "text": text}})
        raw = "not json\n[]\n" + "\n".join([answer("a", "First"), answer("a", "First"), answer("b", "Second")])
        self.assertEqual("First\n\nSecond", final_codex_answer(raw))

    def test_no_answer_does_not_return_protocol_json(self):
        self.assertEqual("", final_codex_answer('{"type":"turn.completed"}'))


if __name__ == "__main__":
    unittest.main()
