# Discovering Retained Procedures By Their Actual Method

## Failure And Change

A `procedure_skill` intentionally stores a reference to an independently retained lesson,
not a replacement copy of that lesson's method. Capability search previously inspected only
the skill's own name, keywords and metadata. Queries describing its reviewed procedure,
applicability or counterconditions could find the lesson but not the reusable skill. A new
task could therefore miss an available method even though the method was persisted correctly.

The regression test first failed on a query containing `environment`, a word present in the
saved applicability condition but not the skill metadata.

Capability search now includes:

- The skill's declared input names and descriptions.
- Its host-pinned domain.
- The exact retained lesson's procedure, applicability, counterconditions and transfer test.

Matching excerpts are prioritized within the existing bounded result preview. `linked_sources`
identifies the exact lesson revision and hash for the derived fields, with `complete_read:false`.
The directory remains lexical, live, paginated and scoped. It is not semantic retrieval,
an exhaustive search over all human methods, an adoption decision or evidence of comprehension.

## Integration And Boundaries

The existing task-related prompt, cloud recall, phone-native recall and Desktop recall bridge
all use the same phone-owned workspace search. No second model loop, idle polling, UI change,
database migration or additional permission is introduced. Desktop source does not change.

The linked lesson must separately pass the existing reader scope check and match the exact
reference, kind and retained state. Seeing a skill does not make all its dependencies visible.
Independent peers and other groups do not gain access through derived excerpts. A missing or
isolated source contributes no linked text. An altered original still fails workspace integrity
validation. A request-local cache avoids rereading the same linked lesson for each skill on a
page; nothing is cached between assignments or access scopes.

The original `procedure_use` admission remains authoritative for current lineage, domain,
inputs and applicability. Historical matches cannot bypass it. Search does not create a
full-read evidence receipt, execute a method, replay old effects, or turn prior success into
new-task success. Failure and avoidance conditions are discoverable, not hidden by a positive
name or keyword match.

## Verification

Focused JVM coverage includes discovery by reviewed conditions followed by normal work
admission, automatic task context, input descriptions, linked-source identity, isolated lessons,
rejected/non-lesson sources, request-local read reuse, pagination, revoked access, stale lineage,
procedure recovery, method experience and workflow selection.

The encrypted device test `CollaborationEvolutionDeviceTest` now discovers a skill through
its reviewed countercondition before using the same reference in the existing persisted DAG
and runtime test. It uses synthetic data and a local test executor, not a real model. Device
execution must be reported separately from compiling the instrumentation APK.

This increment fixes method discoverability. It does not establish that a model chooses the
right method, improves on unseen tasks, gains knowledge, outperforms an individual, or retains
abilities over months. Those require separate live and longitudinal evaluations.

Android version: `1.4.101` / `1186`.

Local verification on 2026-10-08:

- 104 JVM tests across seven suites passed, with no skipped tests.
- Debug APK and instrumentation APK built successfully.
- Kotlin source-size policy and `git diff --check` passed.
- After the S20U reconnected, Android 1.4.101 (1186) was installed over 1.4.98.
- Two `CollaborationEvolutionDeviceTest` tests passed on SM-G9880, including the
  new condition-based discovery followed by encrypted DAG recovery and local execution.
- Two additional device regressions passed: omitted-note publication recovery and
  late coordinator updates across cloud/native recall and evidence confirmation.
- All four device tests used synthetic local data. No real model trial was performed.
