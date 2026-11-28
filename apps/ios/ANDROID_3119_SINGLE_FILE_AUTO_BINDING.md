# Android #3119: Isolated File-Read Auto Identity

Incremental follow-up to Android #3119 (`e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`)
on main `c6bad3465c673dfb2dcecb23b095185c129c7447`. It applies the existing
single-turn Auto binding contract to the iOS single-file reader introduced for
Android #4628. It does not claim a new Android #4628 implementation or full #3119 parity.

## Production Change

The single-file action previously consulted Auto routing independently in its
local, cloud and paired-Agent branches. It neither began an Auto turn for its
new child message nor committed the chosen dispatch to that turn's encrypted
conversation metadata.

After restoring and staging the exact one original, begin admission for the
existing read-only child message, capture one target (including explicit no-route),
and pass it to all three existing selectors. Commit the actual target before
entering the corresponding provider. Failed admission or binding writes use
the existing incomplete-read path; they do not dispatch another provider.
Manual target/model selection remains manual. An explicit no-route no longer
permits the selectors to recompute another Auto route or use legacy global
local-planner defaults.

Capture the conversation selection before asynchronous restoration. Its existing
validity callback now rejects a changed selection during restoration, staging,
provider execution and final report application. This is not cancellation of
bytes already sent, nor a new atomic provider/persistence transaction. A selection
changed away and back between observations is not independently detected.

Original-source hashes, current profile/session/foreground checks, isolated
instructions, one-file payloads, model self-report parsing, disclosure controls,
Desktop authorization and parent receipt application remain unchanged. No original
question, sibling attachment, execution permission or team context is added.

## Verification Boundary

`check-single-file-auto-binding.cjs` freezes the complete reviewed production
entry point, checks provider binding order and explicit no-route propagation,
retains the original reader/provider/receipt implementations, and rejects 13
synthetic source mutations. Its exact inverse is available to other iOS scope
validators; unknown modifications are not normalized away.

This is source validation only. Swift was not compiled or executed. No XCTest,
live provider, transport, persistence fault, device, CI or IPA validation is
claimed. Generic routing/fallback parity and native acceptance remain open.
