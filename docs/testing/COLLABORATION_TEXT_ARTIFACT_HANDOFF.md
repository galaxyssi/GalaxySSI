# Collaboration Text Artifact Handoff

Desktop exposes `collaboration_text_artifact` only when both existing phone
collaboration callbacks are installed. It turns a task-local UTF-8 file into an
actual shared artifact and lets another authorized assignment materialize the
exact version. It does not execute the file or declare a scientific result valid.

## Motivation

A filename, checksum, or description in a research message does not deliver the
program, dataset, or report to another member. In particular, one member's task
directory is not another member's authorized input directory. The helper joins
the existing phone-owned milestone/workspace mechanism with exact file bytes;
it does not create another message bus, outbox, model loop, or permission grant.

## Publish

```json
{
  "mode": "publish",
  "path": "outputs/candidate.py",
  "milestone_id": "candidate-v1-file",
  "title": "Candidate predictor for independent validation"
}
```

- Only forward-slash paths under the active assignment's `outputs` directory
  are accepted. Traversal, absolute paths, hidden filenames, links/reparse points,
  special files and alternate data streams are rejected.
- Bytes are decoded as strict UTF-8 and preserved, including BOM and line endings.
  Binary/NUL-containing files use the existing attachment/Blob workflow instead.
- The immutable snapshot records file name, UTF-8 content, byte size and SHA-256
  in an ordinary `artifact` workspace object, with body format
  `galaxyssi.text-artifact/1`. Authorship, object identity, revision and access
  remain assigned/validated by the phone.
- A hidden task-local snapshot preserves the exact publication request across
  uncertain responses, process restarts and later changes to the working file.
  Repeating the original arguments replays that snapshot. A changed argument is
  rejected; changed content requires a new milestone ID.
- Optional `object_id` and `base_revision` revise an exact existing workspace
  object. Optional `observations` carries only real evidence ID/hash references;
  the phone still validates them. No execution receipt is manufactured.
- The existing 131,072-byte publication envelope includes JSON escaping. Oversize
  content fails explicitly and is never silently truncated. This increment does
  not implement large/binary artifact materialization through this helper.
- Retain returned milestone IDs in the final research artifact's `milestones`.
  An interim publication does not complete the assignment.

## Materialize

```json
{
  "mode": "materialize",
  "object_id": "<exact 64-character workspace object ID>",
  "revision": 1,
  "sha256": "<exact workspace revision hash>"
}
```

Every call, including a repeated local import, reads the exact object through the
originating phone's current assignment authorization. Dependency/pinned-read
grants are not widened. Complete UTF-16-indexed pages are joined (including a
possible split surrogate pair), and identity, file hash and byte size are checked.

The file is atomically materialized under:

```text
<current-task>/downloads/context/collaboration/<identity-sha256>.<extension>
```

The identity digest covers object ID, revision and revision hash. The original
name is retained in the response; this avoids nested long hash directories on
Windows. No arbitrary destination, task/member/phone ID or peer filesystem path is
accepted. A locally modified prior import is not overwritten. Pause/stale-turn
checks prevent a stale operation from proceeding; read-only and plan-only tasks
cannot use this file-writing helper. Private experiment-boundary servers retain
their existing disabled dynamic tools.

The response distinguishes `file_sha256` from the workspace revision `sha256`,
sets `executed=false` and `verified_claim=false`, and marks content untrusted.
The member must inspect the file and use existing execution tools to perform an
independent check. Downloaded content is not an instruction or extra permission.

## Verification

Desktop Python:

```text
python -m unittest test_collaboration_text_artifact test_collaboration_milestone_bridge test_collaboration_recall_bridge test_collaboration_recall_retry test_collaboration_transport_feedback
```

Android host and cross-language contract:

```text
gradlew :app:testDebugUnitTest --tests com.galaxyssi.chat.CollaborationTextArtifactInteropTest --tests com.galaxyssi.chat.CollaborationMilestoneTest --tests com.galaxyssi.chat.CollaborationResearchWorkspaceTest
```

Set `GALAXYSSI_TEST_PYTHON` when Python is not on PATH. The cross-language test
uses actual Desktop snapshot/materialization code and Android workspace/milestone
code. It verifies phone-store reopen, repeated publication, pinned-reader access,
cross-group isolation, multi-page content and byte-exact reconstruction. It calls
no model and uses no network. Desktop cases also cover corrupted metadata,
incomplete pages, UTF-16 surrogate boundaries, modified imports, cancellation,
readonly/stale runtime calls, binary/oversize content and unchanged retry bytes.

These tests establish the file contract, not a live MQTT delivery, complete
multi-agent research acceptance, peer improvement, transfer or retention claim.
