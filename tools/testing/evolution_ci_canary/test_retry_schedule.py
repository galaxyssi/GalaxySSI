import unittest

from retry_schedule import next_retry_delay


class RetryScheduleAcceptance(unittest.TestCase):
    def test_exponential_sequence(self):
        self.assertEqual([2, 4, 8, 16, 32, 60, 60], [next_retry_delay(n) for n in range(1, 8)])

    def test_custom_delays_and_lower_cap(self):
        self.assertEqual([3, 6, 12, 20, 20], [next_retry_delay(n, 3, 20) for n in range(1, 6)])
        self.assertEqual(1, next_retry_delay(1, 3, 1))

    def test_invalid_integer_inputs(self):
        for value in (0, -1, True, False, 1.5, "2", None):
            for field in ("attempt", "initial_delay", "maximum_delay"):
                with self.subTest(value=value, field=field):
                    args = {"attempt": 1, "initial_delay": 2, "maximum_delay": 60, field: value}
                    with self.assertRaises(ValueError):
                        next_retry_delay(**args)

    def test_large_attempt_is_capped_without_large_intermediate_allocation(self):
        self.assertEqual(60, next_retry_delay(1_000_000_000))


if __name__ == "__main__":
    unittest.main()
