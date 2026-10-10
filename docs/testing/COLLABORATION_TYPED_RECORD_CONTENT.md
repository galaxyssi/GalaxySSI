# Typed collaboration records without duplicate prose

Typed evolution records keep their substantive data under `body.<kind>`.
The extra `body.content` prose is optional. When supplied it must still be a
nonempty string; invalid values report `record_content_invalid` at
`/body/content`. No summary is invented, no source is copied and the original
body remains unchanged in the durable workspace.

This addresses observed repair work in which a complete independent tool review
was rejected solely for lacking a duplicate prose sentence. It does not establish
faster model execution, better research results or acquired capability.

The change covers only kinds validated by `CollaborationEvolutionContract`.
Typed fields, reference identity, original-read coverage, independent review,
test coverage and execution authorization are unchanged. Documentary candidates
and final user-facing deliverables still need their substantive `body.content`.
A typed record cannot replace an accepted final report.

`CollaborationTypedRecordContentTest` covers source preservation and replay,
reopened scope checks, native test preparation, independent release, unread and
self-review rejection, missing typed data, regression coverage, invalid optional
content and unchanged final-delivery requirements. These are synthetic tests,
not a real-model trial or a measurement of scientific gain.

## Verification

- Android 1.4.144 (1229): debug APK and instrumentation APK built successfully.
- 162 unit tests passed across typed records, validation, evolution, tools, final
  delivery, workflow selection, transfer and candidate evolution.
- One device test passed on SM-G9880: durable source preservation, reopen,
  idempotent replay and invalid optional-content diagnostics. The test created
  and removed its own synthetic workspace; it did not call a model or execute
  the published source.
- Kotlin source-size guard, Chinese text guard and `git diff --check` passed.

The device test reopens the durable store, not the Android process. It is not
evidence of process-death recovery or end-to-end model collaboration.
