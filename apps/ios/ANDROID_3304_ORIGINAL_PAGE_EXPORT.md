# Android #3304: Original-page iOS Files export

Android merge: `3f2b6bf9ba3bb706fe1bf7edbadbda437c6c0c0a`.
iOS comparison base: `8a794e82ebe8f09790e41139295ffb7ac1ee9701`.

## Actual production integration

The existing phone public-HTML preparation already captures the fetched original
bytes and privately stores a non-executable `.html.txt` source. That remains
unchanged. Previously even an explicit Files export reconstructed all prose
first, followed by a separate image list. It could not preserve original order.

For an existing explicit save/export request with captured HTML and the concrete
URLSession provider, build a static original-DOM document using the existing
SwiftSoup dependency. Retain the ordinary readable model attachment, export ID,
private raw source archive, consent path and Files exporter. Replace only the
pending user export's bytes and give it an `-original.html` suffix. Other providers
and a failed original-document build retain the previous readable export.

Lazy article images are embedded before optional stylesheet decorations. Keep
stylesheet cascade order and resolve relative stylesheet images against the
stylesheet's final redirected URL. Asset requests reuse the existing bounded
HTTPS transport, address/redirect/content checks and original public-web
permission/consent. They cannot extend the existing preparation deadline.

Limits: 8 MiB source, 8 MiB per asset, 24 MiB aggregate accepted assets, 128 unique
asset attempts, eight optional decoration attempts and 48 MiB serialized output.
Repeated resources share a byte cache. Repeated embedded copies also spend a
separate encoded-output budget. Failed resource requests are not retried in the
same build. Images, styles and media that cannot be saved are marked incomplete.

Publisher HTML is parsed as data, never executed. Remove scripts, frames,
embedded content, forms/inputs, refresh/base metadata, event and non-allowlisted
attributes. Remove active/dynamic media, SVG images and unsafe anchor schemes.
Keep only allowed raster data images, rewritten inline CSS and public-HTTPS
anchors. A generated CSP blocks automatic remote resource loading, scripts,
forms and base overrides; links remain explicit user navigation. English and
Chinese incompleteness notices use existing localized resource bundles.

## Boundaries

The explicit export increment is now complemented by the scoped automatic
archive queue described below. A deadline may leave resources missing; the
notice and missing-asset metadata say so. Fonts,
dynamic media and unsupported/escaped CSS may not reproduce publisher layout.
The old raw source archive remains separate, not a safe page to execute.
Full Android #3304 parity and the overall backlog are not claimed complete.

## Durable automatic archive follow-up

The actual paired-Desktop public-page path now captures the profile before its
asynchronous fetch and enqueues only that same profile's exact conversation and
user turn. Encrypted job IDs bind profile/conversation/turn/URL/source hash;
private source filenames are hash-checked before copying. Pending source and
prepared output use the existing attachment cipher with profile/job/type-bound
purposes in Application Support, not public Downloads. Re-enqueue is idempotent.

The queue wakes independently of MQTT at coordinator startup/foreground recovery
and on store changes. A registered BGProcessingTask network request permits one
bounded background job; foreground slices process up to four. The OS may defer
or decline grants. Background grants now use the selective read-only owner path
below, including cold grants without a bound UI runtime. Returning
to the App also scans the current profile's queue even without a pending flag.

Foreground work requires protected data, a readable transcript, current profile, an active,
nonprivate/nonpaused/unmerged conversation, the original user turn and current
execution/connector policy before work and again before publication. Privacy,
lock, foreground-loss and runtime replacement cancel active work. Cancellation
propagates to the detached builder; a current blocking transport or synchronous
DOM parse is cooperative, not instantaneously interruptible. Each background
build retains the original Android-style 120-second total/15-second resource
budgets. Normal failures back off one/two minutes and stop after three failures;
OS cancellation does not consume a normal failure. Corrupt jobs remain retained
and are not overwritten or executed.

### Selective Background Owner

The first queue increment deferred cold grants and required the full Store's
readable transcript for warm grants. But normal backgrounding clears that cache.
BGProcessingTask now reads only existing encrypted account/safety state and the
exact encrypted conversation/user-turn rows, for both cold and warm launches.
It does not construct GalaxySSIStore, a coordinator, identity, model runtime,
database schema or a missing key. It does not restore the foreground cache.
Read-only SQLite handles use the existing exact turn blind index; missing rows,
indices, keys, schemas or account/database identity fail closed without repair.
Conversation/message encrypted rows are bounded at 4 MiB for this owner probe.

Before a network build and again before publication, require protected data,
an inactive App, matching existing profile/database ID, active nonprivate/
nonpaused/unmerged conversation and the actual original user message. Re-read
the encrypted account-state revision after the database queries. When a UI
runtime exists, also check its live profile/safety/conversation state; a newly
bound/replaced runtime cancels the old read-only slice. Protected-data loss,
plaintext-boundary notification and foreground reentry cancel the slice.
Foreground/background handoff cancels and awaits the previous worker before
starting another. In-flight network and parser cancellation remains cooperative.
The same extracted builder/staging implementation serves foreground and
background; no alternate transport or reconstructed prompt is introduced.

Queue writes now call the existing AEAD encryption API and atomically replace
the fully protected encrypted file. This avoids the generic file writer's
delete-before-move window for updates to an existing pending job. It still does
not establish fsync/power-loss durability or cross-file transactional atomicity.

Three more authored-only fixtures cover no identity/key/history creation on
missing state, existing-profile/privacy/pause/turn revalidation without writes,
and missing-index/database rejection without hydration or creation. The cold
source guard pins `a16f12311fa4ed70f576c347680a173f8f356fea`, proves the builder was
extracted unchanged, limits journal edits to the declared atomic replacement,
and freezes the surrounding queue/Coordinator/transport/database implementations.
The older queue guard retains all assertions through a checked normalization
hook. No cold/warm OS launch, database IO, Files or privacy-race acceptance run
has occurred. Full Android equivalence remains unproven.

Prepared output is encrypted before publication and reused after interruption.
Publish a deterministic fully protected HTML file under Files / GalaxySSI /
Downloads / WebPages / profile-hash. Existing identical output is recognized;
an edited, symlinked or mismatched user file is never overwritten. Link a fully
written temporary file into place without replacing an existing name. Commit
the encrypted completion marker before removing pending source/output. Failed
cleanup can be retried without another network build. This is not a cross-store
transaction or proof of fsync/power-loss durability. Final file publication runs
on the main actor to retain its live ownership boundary and can incur file-IO
latency; no UI performance acceptance is claimed.

Three additional authored-only Swift fixtures cover encrypted reopen/staging/
deduplication, account isolation/retry bounds, and refusal to overwrite a user's
edited output. None are compiled or executed. The queue guard pins the original
export increment `5e6167ab76ee808fa271504fb324c879916bb86b`, freezes its provider,
builder and attachment sources, and verifies exact Coordinator/AppDelegate/
project additions and the older guard's read hook. Scheduling, privacy races,
process restart, filesystem faults and Files rendering still require native
acceptance; no Android WorkManager or iOS BGTask behavioral equivalence is proven.

## Verification limits

Six synthetic Swift fixture methods are authored in the existing registered
test file: DOM order/lazy images, dangerous content and side channels,
stylesheet order/redirect base, failed-resource deduplication/request bounds,
invalid input, and actual asset-loader permission/deadline/private-host/byte
boundaries. They are not compiled or executed. The source guard checks
the actual explicit-export call site and new loader and compares the complete
surrounding preparation/provider/old fixtures/project/resource sources with the
pinned base after the declared additions. It does not prove DOM, CSS, network,
compiler, device, fault or privacy acceptance.

No native build/typecheck/XCTest run, live network test, CI monitoring or IPA.

Source verification: the new original-page export scope guard, its JavaScript
syntax check, iOS project structure check, changed-source/document literal-Han
placement and diff whitespace checks passed. No full repository or historical
Web scope-guard pass is claimed.

The durable queue increment additionally passed its dedicated retained-source
guard and JavaScript syntax check, alongside the same project/localization/
whitespace checks. These remain source evidence only, not encrypted IO, Files
publication, background-grant, cold-launch, cancellation or device acceptance.

The selective background increment passed the cold-owner retained-source guard,
both older archive/export guards, all three guard syntax checks and the same
project/localization/whitespace checks. The combined PR has twelve authored-only
Swift fixture methods; none have been compiled or executed.

## Main integration and merge-conflict repair

PR #4599 was merged while its main synchronization was being reviewed. Its
remote head `e245beb88` merged main `6aa0411b7449a6042da15addef4faa4ed126aad6`
and landed as `4114f7ae7`. Conflicts were concurrent additions to Xcode source registrations, the Debug and
Release BGTask permitted identifiers, and AppDelegate background registration.
Both original-page archive and main's knowledge-storage registration/identifiers
are retained, with all source IDs, build phases and groups intact. The original
archive owner, runtime, builder, transport hook and twelve authored fixtures are
unchanged from `d05a9a53c`. This follow-up changes only checks and this document,
not production code or project ordering. No approval or merge was performed by
this session, and merged status is not native acceptance. The checks-only follow-up
retains newer main `e95979579`, including #4600 durability source registrations;
it does not move, remove or reintroduce any production/project changes.

The new main-sync source guard verifies exact main coordinator/startup/project
content after only the declared archive hooks, and exact archive registrations
and hook placement. It then supplies the pinned old feature/checkpoint views to
the earlier source guards; their privacy/cold-owner/network assertions remain.
Raw production files must actually contain main changes, not just the old feature
tree. Equal, already-normalized historical views are accepted only as exact
checkpoint bytes for repeated guard composition.

Main-sync, cold-owner, queue and export source checks pass, alongside check:ios,
changed JavaScript syntax, localization placement and whitespace. These are not
Swift compilation, XCTest execution, actual OS background grants, Files rendering
or CI approval. No full repository pass, IPA or raw/private evidence upload.
