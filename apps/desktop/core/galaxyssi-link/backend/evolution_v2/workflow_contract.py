"""Shared planning knowledge about responsibilities already owned by the host."""

HOST_WORKFLOW = (
    "Each development child already uses a host-owned lifecycle: isolated source changes, independent "
    "candidate acceptance, tests, commit, PR publication, CI observation and integration verification. "
    "Do not create a second source-editing child solely to repeat those host steps. A completed child's "
    "observed outputs may satisfy work originally assigned to a later child. Inspect actual evidence "
    "before removing redundant work. A plan, an implementer's claim, or a PR URL alone is not verified completion. "
    "The original user goal and all its requirements remain binding."
)
