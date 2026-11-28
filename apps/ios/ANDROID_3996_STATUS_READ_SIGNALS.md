# Android #3996: Status Read Signals

Android merge `0f1c2848515869c7fdf01c3e51d04631db06edbf` contains one
production-line change in AgentDeviceStatusShortcutCoverage despite its broader
CI-baseline PR title. This independent iOS increment is based on main
`c6bad3465c673dfb2dcecb23b095185c129c7447`; no CI policy is copied.

## Production Change

Remove if, when, unless and the Chinese conditional connector from the status
read-signal expression, matching the Android change. Those connectors alone no
longer force a device-subject request through phone-status reasoning. This is a
routing classification change, not an execution grant or a direct status read.

Explicit read/check/show/get/current/available/remaining/free/status/how-much
signals remain. A conditional that also asks for an actual read still qualifies
under those signals; this is not a blanket prohibition on conditional tasks.
Complete-query recognition, discussion exclusion, multi-status handling, explicit
Desktop/code/runtime exclusions and all direct action/planner implementations
are unchanged. Existing Chinese reading/status signals remain Unicode-escaped
in source rather than new untranslated UI text.

## Verification Boundary

Six Swift fixture methods cover English and Simplified/Traditional Chinese
conditional-only requests, retained explicit reads inside conditionals, complete
status queries, composite phone planning and discussion/Desktop exclusion.
They call the actual production policies but are NOT compiled or executed.

The source guard pins the exact Android parent/merge line difference, compares
the entire iOS policy against only the two declared removals, freezes direct
planner/intent/runtime kernels and rejects eight synthetic source mutations.
These checks do not execute Swift/ICU or establish routing, model, tool, UI or
device acceptance. No native build, XCTest, CI monitoring or IPA is included.
The broader Android/iOS backlog remains open.
