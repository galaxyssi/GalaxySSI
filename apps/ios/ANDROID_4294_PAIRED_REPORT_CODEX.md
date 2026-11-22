# Android #4294: paired Codex report transcription

Reference: https://github.com/galaxyssi/GalaxySSI/pull/4294
Android merge: `9efdde33984b2c46070f99d47b333336445d7bb3`.

## Implemented iOS behavior

- Replaces the #4293 report-image cloud-model picker and HTTP bodies with the paired
  Desktop's Auto / Codex route. No cloud fallback or offline request queue exists.
- A fresh, verified, ready Codex contact must explicitly advertise
  `private_health_report_vision_v1`. Pairing fingerprint, current Signal session,
  route, model and saved reasoning effort are pinned and revalidated. Legacy links
  and unsupported Desktop versions fail closed. Retired model normalization cannot
  silently substitute another model.
- Preview still requires independent image, online-health and measurement permissions,
  exact source/job/crop snapshots and explicit confirmation for each image. Permission,
  owner, source, destination blocking or configuration changes stop/discard the request.
- JPEG preparation follows Android's 3200/2400/1800 maximum-edge and 92/82/70 quality
  order, with five million pixels and a 224 KiB limit. An image that cannot fit fails
  instead of creating attachment-transfer manifests or a durable request.
- Each request has a new `health-report-vision:` conversation, task/turn UUID and safe
  numeric source. Exactly one inline `report.jpg` goes through a dedicated Signal
  wire allowlist and current verified MQTT route. No durable chat source, task owner,
  managed-reply recovery record or outgoing business queue entry is registered.
- Replies are matched by authenticated Desktop/route and every task identity field,
  generation, terminal state and size. Failed or file-bearing replies fail closed.
  Unknown, late, duplicate and wrong-scope private replies do not become chat messages.
  The common encrypted inbound journal briefly accepts authenticated transport data;
  normal completion clears its payload. Report results are then retained only by the
  encrypted Health job after source/permission revalidation.
- Foreground wait is bounded (12 seconds for readiness, 180 seconds for a reply).
  Cancellation/expiry sends a best-effort transient cancellation, never an offline one.
  Terminal text gets a bound metadata-only result receipt, without a normal reply inbox.
  This receipt is best-effort too; no durable receipt retry is claimed by this route.
- Existing editable draft review remains unchanged: original/local OCR retained,
  model provenance explicit, no automatic confirmed measurements, plans or reminders.

## Server boundary and verification

The Desktop implementation from #4294 recognizes this exact request prefix plus
`screen_analysis`. It creates a separate ephemeral read-only Codex thread, disables
search, MCP/host tools, memory and plugins, forbids historical context, removes report
images from recovery snapshots, and cleans its temporary workspace. This iOS PR does
not modify Desktop or claim to independently enforce a remote sandbox.

New XCTest source checks wire identities and saved configuration, strict field and
image allowlists, retired models, feature/readiness gating, reply isolation and forgery,
terminal failures, size limits, cancellation and metadata-only acknowledgement. Updated
the image-bound regression and removed obsolete cloud-provider-body expectations.

Windows cannot run Xcode, XCTest, a paired Desktop pilot, real network interruptions or
inspect a live Codex sandbox. Static checks are not that evidence. Android's live pilot
is a reference only, not an iOS verification claim. No IPA is produced here.
