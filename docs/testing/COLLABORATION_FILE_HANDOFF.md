# Same-Desktop Collaboration File Handoff

`collaboration_file_artifact` lets a Codex member publish a complete file and
another authorized member materialize its exact version on the same Desktop.
It avoids manually splitting programs or datasets into repeated control messages.
The Android collaboration workspace remains the authority for version visibility.

## Contract

1. `publish` freezes an `outputs`-relative file in the Desktop data directory's
   `collaboration-file-artifacts` store. Copying is streamed and limited by the
   existing 1 GiB Blob file limit; it does not load the whole file into memory.
2. A small descriptor, not the file bytes, is submitted through
   `collaboration_publish`. It includes content hash, length, name and opaque store
   identity. It contains no absolute source path or credentials.
3. The Desktop records the authenticated phone receipt's exact
   `object_id`, `revision` and workspace `sha256`. Unconfirmed publication is not a
   grant to read. Retrying identical arguments uses the frozen file, even if the
   original has changed or disappeared; new content requires a new milestone ID.
4. `materialize` requires the exact phone version. Every call reads that version
   through phone-authorized recall, including when a local copy already exists.
   Copying a descriptor into another workspace object does not authorize access.
5. Verified bytes are copied into the receiving task's `downloads/context`
   directory. Existing modified copies are never overwritten. The tool does not
   execute files, validate their scientific claims or complete an assignment.

The bridge derives current task, conversation, turn, source message, execution
generation and paired-device identities from host state, never tool arguments.
Pause, cancellation, re-pairing and changed assignment invalidate an in-flight
operation. Read-only, planning and screen-analysis executions cannot use this
write-capable tool. Isolated experiment servers do not expose production tools.

## Automated Verification

- Python tests cover a complete 2 MiB binary file with a control publication below
  2 KiB, exact peer bytes, uncertain publication, idempotent retry and new revisions.
- A fresh Python process can retrieve a confirmed version after deletion of the
  producer's original file. Corruption, wrong phone identity, copied descriptors,
  changed assignment, reparse paths and peer edits are rejected.
- `CollaborationFileArtifactInteropTest` passes the real Python publication through
  Android's milestone parser and collaboration workspace with retained in-memory
  test rows, checks scoped version visibility, reopens that workspace, and
  materializes the resulting exact bytes in another Python process. This is a JVM
  contract test, not an MQTT trial or Android process-restart test.
- Existing text artifacts, publication, recall, and transport-feedback regressions
  remain in the verification set.

Run from `apps/desktop/core/galaxyssi-link/backend`:

```powershell
python -m unittest discover -p "test_collaboration*.py"
```

Run from `apps/android`, with `GALAXYSSI_TEST_PYTHON` pointing to the Python runtime:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.galaxyssi.chat.CollaborationFileArtifactInteropTest
```

## Scope and Remaining Acceptance

- File bytes stay on the originating Desktop. This is not a phone download or
  cross-Desktop/cloud-model delivery mechanism. Those routes still need integration
  with the existing Blob/attachment data plane; text delivery remains available.
- Revocation prevents new reads but cannot erase a copy already granted to a member.
- Checksums detect accidental corruption, not tampering by a privileged host process.
  This store is not a sandbox against arbitrary code with the same OS permissions.
- Frozen files are retained outside producer workspaces. There is no automatic
  retention/garbage-collection policy in this increment; storage failures are surfaced.
- Real App-to-Desktop MQTT handoff and independent peer execution still require an
  end-to-end trial. Unit/interop results do not demonstrate improved model reasoning,
  scientific validity, transfer, or multi-agent superiority.
