import unittest

from task_progress_window import TaskProgressWindow


class TaskProgressWindowTests(unittest.TestCase):
    def test_receipt_is_scoped_and_limits_only_its_recipient(self):
        window = TaskProgressWindow()
        self.assertTrue(window.reserve("a", "1"))
        self.assertTrue(window.reserve("a", "2"))
        self.assertFalse(window.reserve("a", "3"))
        self.assertTrue(window.reserve("b", "3"))
        self.assertFalse(window.release("b", "1"))
        self.assertFalse(window.reserve("a", "4"))
        self.assertTrue(window.release("a", "1"))
        self.assertFalse(window.release("a", "1"))
        self.assertTrue(window.reserve("a", "4"))

    def test_lost_receipt_expires_without_unbounded_route_state(self):
        now = [0.0]
        window = TaskProgressWindow(limit=1, ttl=30, max_routes=1, clock=lambda: now[0])
        self.assertTrue(window.reserve("a", "1"))
        self.assertFalse(window.reserve("b", "2"))
        now[0] = 29
        self.assertFalse(window.reserve("a", "3"))
        now[0] = 30
        self.assertTrue(window.reserve("b", "2"))
        self.assertFalse(window.release("a", "1"))

    def test_invalid_scope_cannot_consume_credit(self):
        window = TaskProgressWindow()
        self.assertFalse(window.reserve("", "1"))
        self.assertFalse(window.reserve("a", ""))

    def test_concurrent_tasks_cannot_overfill_one_phone_window(self):
        from concurrent.futures import ThreadPoolExecutor
        window = TaskProgressWindow()
        with ThreadPoolExecutor(max_workers=16) as pool:
            accepted = list(pool.map(lambda number: window.reserve("phone", str(number)), range(1000)))
        self.assertEqual(2, sum(accepted))
        self.assertTrue(window.reserve("other-phone", "other-task"))
