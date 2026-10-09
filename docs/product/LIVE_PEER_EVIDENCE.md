# Live Peer Evidence During Collaboration

## Purpose

An executing researcher can offer an intermediate result to a specific colleague.
The colleague can inspect it and change the next action without waiting for the
author's complete assignment or starting an additional model task. This is a
communication capability, not evidence of collaboration advantage or innovation.

## Work Contract

The coordinator may add `peer_updates_from: ["exact-person-id"]` to an ordinary
work item. This is distinct from a completion dependency and does not cause a
task to wait. Omitted or empty means no live peer exposure. Independent reviews
cannot opt in. Unknown, duplicate or self IDs are rejected. The list is preserved
in the durable work contract and cannot be rewritten after admission.

The sender publishes with the existing `collaboration_publish` tool:

```json
{
  "mode": "publish",
  "milestone_id": "alternative-v1",
  "artifact": "<research artifact with workspace and requests>"
}
```

The research artifact contains a substantive `workspace` object plus:

```json
{
  "coordination": {"mode": "record_only"},
  "requests": [{"to": ["exact-recipient-person-id"], "question": "Check this alternative against your measurement."}]
}
```

All exact workspace revisions in that milestone, and their host-observation
references, are offered to eligible recipients. Unpublished work, other versions,
unaddressed publications and transitively linked originals are not automatically
exposed. Larger material remains in the existing paged original-evidence store.

## Recipient Flow

1. Call `collaboration_recall(mode="peer_updates", cursor="")` at a useful work
   boundary. Only the host-bound current assignment determines identity and peers.
2. Follow `next_cursor` until `caught_up_at_read` is true. One milestone is offered
   per page; this is a transport page size, not a research or team-size limit.
3. Read exact `workspace` revisions and `evidence` pages before judging the claim.
4. Accept, reject or defer the request, and record the actual effect on the next
   action in public progress and versioned results. A published response can link
   the received original as its parent and cite the original observation.
5. Reuse the latest cursor at later useful checkpoints. Empty means no new
   eligible publication at that instant, not that another researcher finished.

There is no automatic polling loop or broadcast wakeup. Existing final-result
mailboxes, task scheduling and coordinator replanning remain separate.

## Recovery and Evidence Semantics

- Original publication, recipient index and receipt commit atomically.
- A returned page and its exact read grants commit atomically and replay after
  uncertain delivery or process restart without creating another revision.
- Cursors are scoped to group, run, turn, round, assignment and declared inputs.
- Paused, stopped, terminal, removed or superseded assignments cannot acquire new
  offers. Granted originals remain usable by the original final-publication
  validator so recovery does not discard valid references.
- Group deletion removes both coordinator and peer replay journals.
- The App owns identity, admission, storage and grants. Desktop forwards the
  existing authenticated task-bound recall operation; it cannot choose a recipient.

Offering a page does not prove delivery, reading does not prove understanding,
and an Agent's acceptance does not prove scientific correctness. Product tests
cover transport and persistence; causal collaboration benefit still requires
independent, budget-matched experiments with actual downstream actions.
