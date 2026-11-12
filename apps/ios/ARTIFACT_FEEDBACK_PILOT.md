# External artifact feedback pilot

`AgentArtifactFeedbackPilotTests` ports the feedback contract of Android
#3397. It runs a draft, review and final worker through the production iOS
team runtime with synthetic outputs. No Desktop connection, model request,
user workspace or production tool settings are used.

The exchange binds the exact UTF-8 original, pilot, slot, node, frozen
protocol digest and evaluator digest. A response references the exact
request bytes. Later workers receive both the unchanged artifacts and the
accepted feedback as untrusted observations. The report records a SHA-256
of each full prepared prompt, including the feedback actually handed to
the fixture worker. Missing, duplicate, changed, truncated, foreign and
oversized feedback cannot authorize a dependent dispatch.

## Opt-in file exchange

Run `testOptInExternalFeedbackExchange` with these XCTest environment values:

- `GALAXYSSI_FEEDBACK_DIRECTORY`: writable directory also accessible to the evaluator.
- `GALAXYSSI_FEEDBACK_PILOT` and `GALAXYSSI_FEEDBACK_SLOT`: distinct identifiers
  containing only letters, digits, underscore and hyphen.
- `GALAXYSSI_FEEDBACK_PROTOCOL_FILE`: frozen synthetic protocol file.
- `GALAXYSSI_FEEDBACK_PROTOCOL_SHA256` and `GALAXYSSI_FEEDBACK_EVALUATOR_SHA256`:
  exact lowercase SHA-256 digests of the protocol and evaluator.
- `GALAXYSSI_FEEDBACK_TIMEOUT_MS`: the authorized slot deadline, at most 600000 ms.

The test reserves `exchange-<pilot>-<slot>` once and writes each complete
`feedback-<pilot>-<slot>-<draft|review>.request.json` there. Return an
atomically published `.response.json` for that node with exactly four fields:
`format` set to `galaxyssi.pilot-execution-feedback-response.v1`,
`request_sha256`, `evaluator_sha256`, and an `evaluation` JSON object.
Hash the exact request file, not reconstructed JSON. Do not overwrite a
response or reuse an interrupted reservation. The report and exchange files
are retained for inspection outside the repository.

A hash binds data; it does not prove that the evaluator ran, that its
observations are true, or that teams outperform another configuration.
No provider or physical-device acceptance is implied by the fixture.
