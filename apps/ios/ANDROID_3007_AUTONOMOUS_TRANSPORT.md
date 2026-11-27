# Autonomous Attempt Transport

Independent iOS follow-up based on main
`c6bad3465c673dfb2dcecb23b095185c129c7447`. This closes the original-transport
limitation recorded in ANDROID_3007_AUTONOMOUS_SOURCE_FOLLOWUP.md; it does not
claim Android #3007 introduced a new wire protocol or transport codec. Existing
iOS cognition already records transport. Autonomous action/review records did not.

## Change

Persist optional `resourceTransport` alongside the selected resource and attempt
correlation for both actions and plan reviews. Action encoding explicitly retains
the optional field; review uses synthesized Codable. Old records remain readable
with nil proof, not a transport inferred from today's contact configuration.

Before dispatch, require a successful stored update with the selected resource,
transport and positive correlation. The store now refuses unreadable snapshots
and returns nil after a failed commit instead of returning an uncommitted object.
Dispatch no longer falls back to its caller's old run after a missing update.
The live request boundary also requires its transport to match the recorded
owned attempt, in addition to all existing source/current-contact checks.

Before accounting/parsing a response, derive transport only from its uniquely
owned running action or current-revision review. Missing proof fails closed.
Local transport accepts only phone-local-model; that reserved ID cannot acquire
cloud/paired transport. Cloud proof requires the current cloud contact and cloud
permission. Paired proof requires the current verified link-family contact and
paired permission. A contact changing type cannot substitute another grant.
Existing private/paused/source membership, positive correlation, task/turn scope,
resource ID, lease/retry/review and budget algorithms remain unchanged.

## Evidence

Nine XCTest methods authored in the existing registered fixture, NOT executed:
action/review optional codec roundtrips; owned/ambiguous response transport;
review revision ownership; legacy no-proof; reopen and independent action/review
fields; unreadable-state refusal; write-failure return/retention; current resource
type/grant and local-ID confinement. They are not actual model dispatch, process
restart, cloud/paired transport or native storage-fault acceptance.

The dedicated source guard pins exact approved sections to feature commit
`0c178e6ccc7b357d7ff81441680e140fbad2990e`, restores only those sections, then
compares complete files with main. Mutations within approved sections fail;
unrelated changes remain visible. Related policy files remain byte-identical.
The historical autonomous source checker keeps every assertion with only two
normalization hooks. It still fails its old full GalaxySSIServices snapshot;
substituting unchanged main Swift sources reproduces that failure. This is not
reported as a passing check or suppressed.

Dedicated source guard, JS syntax, iOS project structure and diff whitespace
checks pass. No Swift/native build, XCTest execution, full check, CI watching,
device/network/model acceptance, IPA or private evidence upload.

## Limits

Host-maintained metadata is not cryptographic transport authentication. Existing
legacy blank response scopes retain their compatibility semantics; IDs alone do
not authenticate a sender. No retroactive proof migration, live-effect retraction,
queued payload cancellation, cross-store transaction, independent-writer CAS,
fsync/power-loss guarantee or exactly-once dispatch is added. Model budget may
already be reserved when attempt persistence fails, conservatively consuming that
admission rather than fabricating a backend call or refund. Missing legacy proof
is not enough to authorize late results; ordinary explicit retry policy still
governs new attempts. Android #3007 and the overall backlog remain incomplete.
