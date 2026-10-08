# Shared Collaboration Workflow Core

Android's production `CollaborationWorkflowSelection` and
`CollaborationWorkflowInstantiation` call this Kotlin/JVM module. The local replay
adapter calls the same functions. There is no second research-only selector.

## Scope

- Evaluate Agent-authored applicability and counterconditions against declared inputs.
- Keep the baseline when data are unknown or an exclusion matches.
- Materialize the selected method's actual assignments, dependencies and review subjects.
- Preserve existing host work IDs and keep input data separate from instructions.

This is **not** the entire coordinator, a model runner, a causal estimator, or a
scientific evaluation suite. Android still validates exact workspace revisions,
scope, lineage, author independence, admission, persistence and side effects.
Replay does not bypass or simulate those checks and never executes a task.
Matching a condition is not evidence that a method improved quality.

## Standalone Tests and Replay

From the repository root, using JDK 17+ and the existing Gradle wrapper:

```powershell
apps/android/gradlew.bat -p apps/shared/collaboration-core test
Get-Content -Raw apps/shared/collaboration-core/examples/conditional-workflow.json |
  apps/android/gradlew.bat -q -p apps/shared/collaboration-core replay
```

These commands do not configure the Android application or require an Android SDK.
Dependencies must already be cached to add `--offline`.
Replay emits a selection and projected work, with `execution_performed=false`,
`host_admission_performed=false`, `quality_effect=null` and `causality_proven=false`.
The example is a developer-authored synthetic fixture, not an Agent discovery.

`org.json` is compile-only for the published core: Android provides its own
implementation. Only the standalone replay and JVM tests include the Maven
implementation. `SharedWorkflowCoreDeviceTest` checks the Android implementation
as well; do not substitute a successful JVM build for device verification.

Task IDs retain each existing host's JSON string encoding to avoid replaying
completed effects after an upgrade. Cross-host fixture comparisons should use
the source step identities as well as graph content; no cross-host task migration
is implemented by this module.

## Next Boundary

A full research host must reuse production scheduling and evidence feedback too,
not independently reimplement them. Active intervention selection, prospective
causal tests, transfer to unseen tasks and retained capability growth remain
separate, unproven work. No claim of intelligence gain follows from this refactor.
