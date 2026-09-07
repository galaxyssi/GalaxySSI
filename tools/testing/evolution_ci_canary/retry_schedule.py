"""Controlled CI-repair acceptance fixture; not production runtime code."""


def next_retry_delay(attempt, initial_delay=2, maximum_delay=60):
    """Return capped exponential delay for a one-based retry attempt.

    Inputs must be positive integers; booleans are not valid integer values.
    The maximum is a hard cap, including when it is smaller than the initial delay.
    Very large attempts must not allocate enormous intermediate integers.
    """
    values = {
        "attempt": attempt,
        "initial_delay": initial_delay,
        "maximum_delay": maximum_delay,
    }
    for name, value in values.items():
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            raise ValueError(f"{name} must be a positive integer")

    if initial_delay >= maximum_delay:
        return maximum_delay

    doublings = attempt - 1
    doublings_to_cap = ((maximum_delay - 1) // initial_delay).bit_length()
    if doublings >= doublings_to_cap:
        return maximum_delay

    return initial_delay << doublings
