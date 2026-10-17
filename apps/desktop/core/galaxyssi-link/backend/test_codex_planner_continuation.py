import tempfile
import unittest
from pathlib import Path

from codex_planner_continuation import PlannerContinuations


class PlannerContinuationTests(unittest.TestCase):
    def setUp(self):
        self.cache = PlannerContinuations()
        self.prefix = "Stable tool definitions and goal instructions.\n" * 100

    def test_incremental_input_requires_confirmed_same_thread(self):
        first = self.prefix + "Observation: first page\n"
        second = self.prefix + "Observation: second page\n"
        _, _, receipt = self.cache.prepare("thread-a", first, [])
        self.assertEqual(second, self.cache.prepare("thread-a", second, [])[0])
        self.cache.commit("thread-a", receipt)
        delta = self.cache.prepare("thread-a", second, [])[0]
        self.assertIn("Observation: second page", delta)
        self.assertLess(len(delta), len(second) // 4)
        self.assertEqual(second, self.cache.prepare("thread-b", second, [])[0])
        self.assertNotIn("Stable tool", repr(self.cache.records))

    def test_changed_instruction_and_short_input_are_never_dropped(self):
        _, _, receipt = self.cache.prepare("t", self.prefix, [])
        self.cache.commit("t", receipt)
        for prompt in ("New instructions\n" + self.prefix, "short observation", ""):
            self.assertEqual(prompt, self.cache.prepare("t", prompt, [])[0])

    def test_images_deduplicate_by_content_not_reused_path(self):
        with tempfile.TemporaryDirectory() as directory:
            a, b = Path(directory) / "a.jpg", Path(directory) / "b.jpg"
            a.write_bytes(b"first image")
            b.write_bytes(a.read_bytes())
            _, _, receipt = self.cache.prepare("t", self.prefix, [str(a)])
            self.cache.commit("t", receipt)
            self.assertEqual([], self.cache.prepare("t", self.prefix, [str(b)])[1])
            a.write_bytes(b"changed image")
            self.assertEqual([str(a)], self.cache.prepare("t", self.prefix, [str(a)])[1])
            self.assertEqual([str(b)], self.cache.prepare("other", self.prefix, [str(b)])[1])

    def test_expiry_eviction_and_compaction_force_full_input(self):
        now = [0]
        self.cache = PlannerContinuations(clock=lambda: now[0], capacity=1, ttl=10)
        _, _, receipt = self.cache.prepare("a", self.prefix, [])
        self.cache.commit("a", receipt)
        now[0] = 10
        self.assertEqual(self.prefix, self.cache.prepare("a", self.prefix, [])[0])
        self.cache.commit("a", receipt)
        self.cache.commit("b", receipt)
        self.assertEqual(self.prefix, self.cache.prepare("a", self.prefix, [])[0])
        self.cache.forget("b")
        self.cache.commit("b", receipt)  # A compaction during turn submission fences this receipt.
        self.assertEqual(self.prefix, self.cache.prepare("b", self.prefix, [])[0])


if __name__ == "__main__":
    unittest.main()
