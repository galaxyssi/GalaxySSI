# Optional Research Publication Notes

The host accepts omitted, empty top-level `candidates` and `findings` in
`galaxyssi.research-artifact.v1`. Decoding supplies `[]`; it does not invent
findings, rewrite the original submission, or verify any claim. This avoids
asking a model to regenerate a substantive delivery solely to add empty arrays.

An interim publication can use this envelope:

```json
{
  "format": "galaxyssi.research-artifact.v1",
  "summary": "Observations ready for independent review",
  "workspace": [
    {
      "id": "observations-v1",
      "kind": "artifact",
      "title": "Synthetic observations",
      "body": {"content": "The complete original observations belong here."}
    }
  ]
}
```

The example is a format illustration, not measured evidence. `workspace` bodies,
candidate transitions, reviews, observation references and version conflicts
retain their existing validation. An empty interim workspace is still rejected.
Explicit `null`, objects or strings in place of the two note arrays are rejected
with the field name. The format and a nonblank summary remain required.

Raw drafts and their hashes remain unchanged in both final and milestone
journals. Accepted milestone retries must use the identical ID and raw artifact;
adding explicit empty arrays afterward is a changed submission, not an identical
retry. Desktop forwards the original bytes in the artifact string and does not
normalize them before transport. A recorded artifact is not task completion,
peer consumption, or independent verification.

## Regression Coverage

- `CollaborationResearchArtifactTest`: absent arrays, malformed supplied values,
  required fields, complete note preservation and decoded handoffs.
- `CollaborationPublicationEnvelopeTest`: interim/final publication, raw journal
  preservation, reopen/retry, invalid workspace bodies, exact references and
  revalidation of an unchanged previously rejected draft.
- `test_collaboration_milestone_bridge.py`: the opaque artifact crosses the
  Desktop bridge without being rewritten.
- `CollaborationMilestoneDeviceTest#omittedNotesPublishAndRecoverWithoutChangingRawIdentityOrEvidenceState`:
  local encrypted-store and tool-path coverage, with dedicated fixtures cleaned
  afterward. It invokes no model and does not touch existing conversations.

Build/host tests and device execution are distinct acceptance steps. Passing
these tests does not establish autonomous capability growth or a successful
real-model collaboration trial.
