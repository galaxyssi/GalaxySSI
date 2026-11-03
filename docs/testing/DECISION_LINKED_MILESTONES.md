# Decision-linked interim collaboration

Interim evidence preservation and coordinator intervention are separate actions.
This is a general collaboration mechanism, not a domain-specific workflow or a
claim that multi-agent research already outperforms a strong single agent.

## Publication contract

`collaboration_publish` keeps its existing transport envelope. Its research
artifact JSON optionally includes one of:

```json
{"coordination":{"mode":"record_only"}}
```

```json
{
  "coordination": {
    "mode": "request",
    "decision": "Which measurement distinguishes the competing explanations?",
    "why_now": "An independent probe design could expose a confound while calibration continues."
  }
}
```

`record_only` commits original versions and receipts without a coordinator wake
or live-graph admission. `request` exposes the stated decision and its exact
evidence references to incremental coordination. Neither stops the researcher,
completes its assignment, verifies its claims, or expands its authority. An
omitted field retains existing notification behavior for already saved work.
Decisions and timing remain member-selected, not an N-step host heuristic.

A request can refer to this same assignment's previously saved milestones:

```json
{
  "format": "galaxyssi.research-artifact.v1",
  "summary": "Please independently check the measurement design.",
  "coordination": {
    "mode": "request",
    "decision": "Use the current sensor placement or repeat co-located readings?",
    "why_now": "Measurements may contain a location confound."
  },
  "milestones": ["raw-observations-v1", "measurement-program-v1"]
}
```

No original bytes are recopied or revised. Reference resolution is scoped to the
publishing assignment; original version hashes, authorship and linked tool
observations remain checked. The reference list does not grant arbitrary peer
or task access. Empty evidence requests are rejected.

The Desktop file/text publication tools accept the same optional `coordination`
object as an argument, freeze it with the existing snapshot, and pass it through
the phone's publication contract. A retry must keep its original ID, arguments
and bytes; escalation uses a new request ID, not mutation of an accepted record.

## Recovery and integrity

- Mode and request details are in the immutable receipt and checked index.
- A separate record-only run index keeps long-lived raw logs out of live
  coordination scans. Audit inventory traverses both indices with paging.
- Each consumed entry is checked against its immutable receipt and expected
  index; changing an index descriptor cannot reclassify a saved publication.
- Listing and auditing retain record-only versions; final output may reference
  both saved records and requests without duplicating workspace revisions.
- Live coordination and `team_updates` expose actionable requests, while the
  default audit inventory continues to include all publications.
- Existing user pause, assignment ownership, revocation, exact-version grants,
  deduplication and final dependency handling remain authoritative.
- Group deletion clears coordinator pages and grants as well as workspace rows.
  Their pre-existing wire-digest namespace is preserved for live groups but
  explicitly included in atomic deletion, avoiding stale references on reuse.
- Finished work still enters ordinary result coordination. This change does not
  suppress completed task results or require a request before independent work.

## Verification

Unit and device coverage checks persistence, quiet record-only retries, explicit
request admission before producer completion, exact-original reuse, audit
retention, pagination, corrupt index rejection, invalid request feedback and
immutable Desktop snapshots. Device scenarios use synthetic local data and the
real encrypted store/runtime, without invoking a model or existing research.

Scientific acceptance requires fresh real-model trials: did a peer's evidence
change an actual decision and improve externally measured quality at accounted
resource cost? Fewer coordinator calls alone does not establish intelligence,
innovation, lasting learning or collaboration benefit.
