# Evidence query stage diagnosis

Read-only evidence import now correlates Android publication, Desktop receive
stages, evidence lookup, Desktop publication and Android response validation with
the first 16 hexadecimal SHA-256 characters of the random request ID. Request,
task, contact, route and evidence contents are not logged by these observations.
Desktop publication logs its elapsed time separately from the local lookup.
Publication acceptance remains distinct from authenticated phone receipt.

The production eight-second query wait and bounded late-response correlation are
unchanged. There is no extra request, model execution, durable queue or retry
introduced by instrumentation. A diagnostic failure must not turn a valid
response into failure or invoke publication twice.

The opt-in `CollaborationEvidenceTransportDeviceTest` accepts
`remoteEvidenceObserveLateMillis` (0 by default, at most 60000). On an initial
query timeout it saves the failed sample and keeps the receiver alive for this
observation period. It then fails the same assertion even if a late response was
logged. This avoids killing the receiver at the precise moment a late response
needs to be diagnosed; it is not a longer success deadline.

This test reads only an explicitly supplied, already completed dedicated fixture.
It does not create or rerun model work. Real measured results and private task
identifiers belong outside the repository. Timing observations alone do not
demonstrate peer revision, learning, transfer or scientific performance.
