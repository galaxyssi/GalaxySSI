# Artifact availability probe

The iOS plan also accepts `galaxyssi.artifact-transfer-probe.v2` with the same
field names as its v1 format. Each case has one `withheld` slot with an empty
`sourceID` and one or more `available` slots referencing distinct declared
candidates. All slots in a case must contain byte-identical target material.
The shared control never opens candidate storage. No target slot can reuse
an acquisition identity or its task material.

`AgentArtifactAvailabilityProbeTests` exercises the paired controls from
Android #3394 in the production iOS team runtime. Each test dispatch has a
fresh conversation, run, turn and task, and exactly one responding worker.
The available arm reads the frozen source and validates the exact envelope
hash and provenance before exposing its final text as unverified data. The
withheld arm never opens the artifact. Both arms use byte-identical new task
material and the same frozen target, model and effort. Ambient handoff
context, source IDs, original drafts and observer outputs are not added.

## Opt-in fixture

Run `testOptInFrozenArtifactAvailabilityProbe` with these XCTest settings:

- `GALAXYSSI_ARTIFACT_PROBE_PLAN` and `GALAXYSSI_ARTIFACT_PROBE_PLAN_SHA256`:
  the manifest file and exact lowercase SHA-256.
- `GALAXYSSI_ARTIFACT_PROBE_ORIGINALS`: directory containing each original
  envelope as `<artifactSHA256>.json`.
- `GALAXYSSI_ARTIFACT_PROBE_MAX_DISPATCHES`: independently authorized slot count.
- `GALAXYSSI_ARTIFACT_PROBE_TARGET`, `GALAXYSSI_ARTIFACT_PROBE_MODEL` and
  `GALAXYSSI_ARTIFACT_PROBE_EFFORT`: independently selected fixture values.

The manifest has `format: galaxyssi.artifact-transfer-probe.v1`,
`toolScope: production_tools_not_isolated`, `pilot`, `target`, `model`,
`effort`, `timeoutMillis` (60000 to 600000), `sources`, and `slots`.
Each source entry has `id`, `artifactSHA256` and a `source` object containing
`pilot`, `identity` (`run`, `conversation`, `turn`, `task`),
`protocolSHA256`, `goalSHA256`, `target`, `model`, and `effort`.
An original envelope has that exact `source`, `finalOutput`, and
`observerOutputs`. Each slot contains `id`, `caseID`, `sourceID`,
`condition` (`available` or `withheld`), and `objective`. Include both
conditions for every source/case pair and use a fresh objective distinct
from the source's goal. The test attachment contains digests and fixture
identifiers, not the candidate text or the task.

Use synthetic inputs. The fixture does not invoke a provider or Desktop,
prove a fresh provider thread, validate a capability sandbox, or establish
learning, improved task quality, or equal compute. It does not change
production model settings, collaboration or tools.
