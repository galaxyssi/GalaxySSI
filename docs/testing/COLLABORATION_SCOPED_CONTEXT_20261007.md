# Scoped Collaboration Context Retrieval

## Purpose

A member resolving one missing dependency or work-inventory section previously
had to page through the goal, criteria, source mapping and preceding context.
This made long-lived collaboration spend model/tool calls retrieving unrelated
material even when the required section's name was already known.

This change provides exact section retrieval, not a summary, a new planner, or a
relaxation of acceptance criteria. It is a general product capability. It does
not establish improved reasoning, autonomous learning, scientific validity, or
superintelligence.

## Contract

`collaboration_recall` and `galaxyssi.phone.collaboration.recall` accept:

```json
{
  "mode": "goal_contract",
  "section": "context:Dependency evidence",
  "cursor": ""
}
```

- Reserved selectors are `goal`, `criteria` and `source`.
- Named sections use `context:<exact section name>`.
- Keep the selector unchanged while following `next_cursor` until null.
- Null ends the selected section, not all pages in the snapshot.
- Omit `section` to retain whole-snapshot browsing.
- Unknown sections fail explicitly; they do not silently return other context.

New snapshots contain a hash-bound page-range index. Section reads fetch only
the original pages intersecting that section. Boundary pages may also contain
neighboring fragments already authorized in the same snapshot. No content is
rewritten, truncated or hidden from whole-snapshot retrieval.

Older pinned snapshots remain readable and unchanged. Their index is derived
from hash-verified originals on demand; this fallback still has a local scan
cost. Newly created snapshots do not scan unrelated pages on section reads.

## Isolation and Progress

- The host still resolves group, turn, node, member and immutable snapshot.
- Section cursors bind all of those identities plus the selector. They cannot
  cross sections, members, snapshots or the whole-snapshot cursor namespace.
- Delivery registration checks the exact returned envelope and records only
  pages actually delivered. A descriptor or selected section is not full review.
- Cloud progress deduplicates by immutable snapshot/reader/page identity, so
  reading the same page through different selectors cannot invent progress.
- Cloud, native-phone and authenticated Desktop-forwarded tools expose the same
  selector contract. No phone UI, contact operation or model route is changed.

## Validation

- Desktop collaboration backend: 57 tests, 97 subtests passed.
- Desktop JavaScript/source checks: 68 tests passed; structure check passed.
- Android compilation and APK/test-APK assembly passed.
- Android unit regression: 1,387 tests across 114 suites passed, no skipped tests.
  The first run exposed three assertions for the old recall hint wording; those
  now check the new exact selector, including a recovered-context section read.
- S26U (`SM-S9480`) was upgraded without clearing data. The encrypted-store
  device test passed: cloud and native tools retrieve identical section/page
  hashes, missing sections fail, full goal reconstruction remains exact,
  unbound/revoked readers fail, and no full-delivery receipt is invented.
- Desktop `1.4.25` was restarted while idle. Its main window was checked and all
  three MQTT paths were receive-ready with no queued ingress messages.
- No real model calls were made for this increment. Model-selected retrieval,
  end-to-end research completion, coordination efficiency and quality gains
  require a subsequent real trial.

Versions: Android `1.4.91` (`1176`), Desktop `1.4.25`.

APK SHA-256:
`2061a559fb8e1b00f88da3278de2a12b42c38150dcca8316d834037f4c20b733`.
