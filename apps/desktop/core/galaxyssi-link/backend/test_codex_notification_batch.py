import copy
import queue
import unittest

from codex_notification_batch import CodexNotificationBatcher


def delta(text, **fields):
    return {"method": "item/agentMessage/delta", "params": {
        "threadId": "thread", "turnId": "turn", "itemId": "item", "delta": text, **fields}}


class CodexNotificationBatchTests(unittest.TestCase):
    def drain(self, messages, limit=64_000):
        events = queue.Queue()
        originals = copy.deepcopy(messages)
        for message in messages:
            events.put(message)
        reader = CodexNotificationBatcher(events, limit)
        batches = []
        while True:
            try:
                batch = reader.get(timeout=0)
            except queue.Empty:
                break
            batches.append(batch)
            reader.task_done(batch)
        self.assertEqual(0, events.unfinished_tasks)
        self.assertEqual(originals, messages, "Do not mutate queued provider events")
        return batches

    def test_backlog_reaches_terminal_without_replaying_every_text_fragment(self):
        fragments = [str(index) + "," for index in range(1024)]
        terminal = {"method": "turn/completed", "params": {"threadId": "thread", "turn": {"id": "turn"}}}
        batches = self.drain([delta(text) for text in fragments] + [terminal])
        self.assertEqual(2, len(batches))
        self.assertEqual("".join(fragments), batches[0].message["params"]["delta"])
        self.assertEqual(1024, batches[0].entries)
        self.assertEqual(terminal, batches[1].message)

    def test_live_single_delta_is_available_without_waiting_for_a_batch(self):
        batches = self.drain([delta("first")])
        self.assertEqual(1, len(batches))
        self.assertEqual("first", batches[0].message["params"]["delta"])

    def test_different_member_turn_item_phase_and_metadata_are_barriers(self):
        for fields in ({"threadId": "other"}, {"turnId": "other"}, {"itemId": "other"},
                       {"phase": "commentary"}, {"extension": {"sequence": 2}}):
            with self.subTest(fields=fields):
                rows = [delta("A"), delta("B", **fields), delta("C")]
                self.assertEqual(rows, [batch.message for batch in self.drain(rows)])

    def test_tool_and_terminal_events_never_move_past_text(self):
        for method in ("item/completed", "item/tool/call", "turn/completed", "turn/started", "error"):
            with self.subTest(method=method):
                barrier = {"method": method, "params": {"threadId": "thread", "turnId": "turn"}}
                rows = [delta("A"), barrier, delta("B")]
                self.assertEqual(rows, [batch.message for batch in self.drain(rows)])

    def test_server_request_and_missing_identity_are_not_coalesced(self):
        request = {**delta("A"), "id": 1}
        for row in (request, delta("A", turnId=""), delta(None), delta("A", itemId=None)):
            with self.subTest(row=row):
                rows = [row, copy.deepcopy(row)]
                self.assertEqual(rows, [batch.message for batch in self.drain(rows)])

    def test_batch_size_bound_preserves_text_and_pending_acknowledgement(self):
        rows = [delta("abcd"), delta("ef"), delta("ghijklmno"), delta("p")]
        batches = self.drain(rows, limit=5)
        self.assertEqual("abcdefghijklmnop", "".join(b.message["params"]["delta"] for b in batches))
        self.assertEqual([1, 1, 1, 1], [b.entries for b in batches])

    def test_empty_and_unicode_fragments_are_not_lost(self):
        rows = [delta(text) for text in ("", "\u4e2d", "\u6587", "", "\n", "done")]
        batches = self.drain(rows)
        self.assertEqual("\u4e2d\u6587\ndone", batches[0].message["params"]["delta"])
        self.assertEqual(len(rows), batches[0].entries)

    def test_nonpositive_limit_rejected(self):
        for limit in (0, -1):
            with self.assertRaises(ValueError):
                CodexNotificationBatcher(queue.Queue(), limit)


if __name__ == "__main__":
    unittest.main()
