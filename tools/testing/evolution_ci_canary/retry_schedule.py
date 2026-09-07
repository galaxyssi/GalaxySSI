"""Controlled CI-repair acceptance fixture; not production runtime code."""


def next_retry_delay(attempt, initial_delay=2, maximum_delay=60):
    """Return capped exponential delay for a one-based retry attempt.

    Inputs must be positive integers; booleans are not valid integer values.
    The maximum is a hard cap, including when it is smaller than the initial delay.
    Very large attempts must not allocate enormous intermediate integers.
    """
    return initial_delay * attempt
