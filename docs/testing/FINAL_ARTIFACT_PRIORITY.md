# Final artifact selection

Desktop v1.4.41 separates bounded workspace inventory from explicit final delivery.
Previously, a final report or archive could exist outside the first 50 inventory
entries. Final-link selection then fell back to intermediate files, sending those
instead of the requested deliverables.

## Contract

- Resolve final Markdown links directly within the current task's output areas
  when finalizing or persisting a task result.
- Preserve final-link order, deduplicate paths, and retain existing artifact
  metadata, including image provenance.
- Verify the selected final files, including archive integrity, before recording
  verification results. A corrupt final archive is not a verified deliverable.
- Keep inputs, conversation context, hidden files, signing sidecars, links to
  other tasks, external filesystem paths, and symbolic links out of discovery.
- Rich-output rendering never discovers additional files: it can only render the
  prepared transport list. Plan-only and read-only screen analysis retain their
  existing no-artifact final callback.
- Persist the selected metadata so reopening the task store retains the same
  files. Legacy replay with an existing artifact inventory resolves final links
  before transport preparation. An empty replay inventory does not enable new
  filesystem discovery.
- Replies without a valid explicit final file link retain the existing inventory
  fallback. This change does not remove workspace retention or transport limits.

## Regression tests

Run from `apps/desktop/core/galaxyssi-link/backend`:

```text
python -m unittest test_final_artifact_priority test_task_workspace test_rich_output test_blob_artifact_final_callback test_remote_image_delivery -v
```

The fixture creates 60 intermediate JSON files and two final deliverables. Its
bounded inventory deliberately omits both final files. Tests exercise production
finalization, the production MQTT final callback with isolated transport, task
store reopen, and legacy replay. No model or private research data is required.

These are product delivery tests, not evidence of scientific novelty, learning,
or multi-agent quality improvement. Real-phone delivery after deployment remains
a separate acceptance check.
