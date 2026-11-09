# Business artifact delivery evidence on iOS

The iOS XCTest collector inspects the attachments declared by the delivered
reply for the exact conversation and turn. It requires every file to resolve
to stored bytes matching the receipt, open as its claimed container, match
the frozen filename version, save through the same file wrapper used by the
exporter, and read back with the same SHA-256. It also checks required
extensions and preview formats, dimensions, and count. A verified preview
cannot compensate for a missing or unverified Office original.

The regression uses a temporary encrypted artifact store and synthetic
documents and removes the materialized and exported copies. The check
does not interact with the Files picker or verify document contents, formulas,
or that the preview is faithful to the original. Those outcomes require
separate evidence; this is not a rerun of the Android warehouse campaign.

To recheck a saved synthetic assessment without changing it, run only
`AgentBusinessArtifactEvidenceTests.testOptInRecheckRecordedDelivery` with
`GALAXYSSI_BUSINESS_ARTIFACT_EXPECTATION` pointing to the frozen
`artifact_expectations` object and `GALAXYSSI_BUSINESS_ASSESSMENT` pointing to
the saved `assessment` object. Both are standalone JSON files readable by
the XCTest host. A legacy `correct: true` flag cannot replace missing
per-attachment checks. Text-only cases require zero unexpected files.
