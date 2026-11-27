# Immutable Source Routing (Android #3007)

Reference: `65655f0c79c6ab04121150229a65b089180f82f2`,
`AgentWebIntelligenceEngineCatalog.entries` and per-request selection triples.
Incremental base: main `c6bad3465c673dfb2dcecb23b095185c129c7447`.

The current iOS implementation already registers the pinned Android catalog's
41 base IDs plus 247 indexed sites. Earlier historical notes about 18/22/40
engines are not current missing adapters. No engine or endpoint is added here.

The actual remaining difference addressed here was catalog lifetime and scoring
work: iOS rebuilt the same immutable spec list per selection and recalculated each
source's score inside the sort comparator. Like Android's immutable catalog and
request-local score triples, retain the bundled spec list once and materialize
one score per eligible source per request, preserving ordinal ties exactly.

Only static public/bundled metadata is retained. Learned sources, eligibility,
health, circuit clocks, requested order/categories/verticals and credential
availability still come from each call. Returned value-type specs cannot mutate
the shared catalog. Formulas, disabled-source rules, result order, permissions,
credentials, transport, parser, fusion and encrypted cache are unchanged.

This removes repeated allocations/comparator computations, not all search cost.
It does not relocate mandatory runtime construction, perform background catalog
hydration or demonstrate measured startup/query latency. Native startup prewarm,
remaining platform adaptations and the full backlog are separate work.

The new source guard compares the complete catalog with the baseline after only
the two declared changes and pins all 41 IDs to Android. Six XCTest methods are
authored but not executed: catalog coverage/order, live circuits/clocks, fresh
health scores/stable ties, learned-source lifecycle, explicit order/value-copy
isolation, and fanout/unknown-source boundaries. Prior routing/mixed-media guards
normalize only these exact hooks without removing any assertion.

Only focused JS/source/project and whitespace checks are run. No Swift/native
compilation, XCTest, live network/device/performance acceptance, full check,
CI monitoring, version change, IPA or private evidence upload.

The dedicated immutable-routing guard, `npm run check:ios`, JS syntax and
whitespace checks pass. The older automatic-routing and mixed-media scope
commands still fail their full WebMediaProvider snapshot assertions. Repeating
those assertions with unchanged Swift sources from the pinned main produces the
same failures; they are not counted as passing or suppressed by this change.
