"""Separate measured artifact/UI phases from historical reply-terminal latency."""
import math
import statistics

PHASES = (
    "reply_terminal_ms", "assessment_started_ms", "assessment_completed_ms",
    "assessment_duration_ms", "ui_check_ms", "observed_end_to_end_ms",
    "artifacts_present_ms", "artifact_presence_wait_ms", "artifact_audit_ms",
    "save_verification_ms", "artifacts_verified_ms",
)
REQUIRED = PHASES[:6]


def summarize_phases(turns):
    samples = {key: [] for key in PHASES}
    measured = 0
    for turn in turns:
        timing = turn.get("phase_timing")
        if turn.get("driver_schema", 0) < 4 or timing is None:
            continue
        if not isinstance(timing, dict) or timing.get("schema") != 1 or timing.get("clock") != "elapsed_realtime":
            raise ValueError("Unsupported phase timing")
        for key in PHASES:
            value = timing.get(key)
            if (key in REQUIRED and value is None) or (value is not None and (type(value) is not int or value < 0)):
                raise ValueError("Invalid phase duration: " + key)
        reply, start, end, audit_duration, ui, total = (timing[key] for key in REQUIRED)
        if not (reply == turn.get("elapsed_ms") and reply <= start <= end <= total
                and end - start == audit_duration and total - end == ui):
            raise ValueError("Inconsistent phase chronology")
        wait = timing.get("artifact_presence_wait_ms")
        audit = timing.get("artifact_audit_ms")
        save = timing.get("save_verification_ms")
        present = timing.get("artifacts_present_ms")
        verified = timing.get("artifacts_verified_ms")
        if wait is None:
            if any(timing.get(key) is not None for key in PHASES[6:]):
                raise ValueError("Artifact phases lack a wait observation")
        elif (audit is None or save is None or wait + audit != audit_duration or save > audit
              or (present is not None and present != start + wait)
              or (verified is not None and (verified != end or not turn.get("assessment", {}).get("correct")
                                            or not turn.get("assessment", {}).get("all_artifacts_verified")))):
            raise ValueError("Inconsistent artifact phase timing")
        measured += 1
        for key in PHASES:
            if timing.get(key) is not None:
                samples[key].append(timing[key])
    def stats(values):
        values = sorted(values)
        return {"samples": len(values), "p50_ms": statistics.median(values) if values else None,
                "p95_ms": values[math.ceil(len(values) * .95) - 1] if len(values) >= 30 else None,
                "maximum_ms": max(values) if values else None}
    return {"measured_turns": measured, "unmeasured_turns": len(turns) - measured,
            "scope": "monotonic_test_observations_including_audit_and_ui_check_overhead",
            "phases": {key: stats(values) for key, values in samples.items()}}
