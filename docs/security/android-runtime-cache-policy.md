# Android runtime cache policy

## Sensitive caches

Decrypted transcript entries, decrypted preference values and decoded contact
image thumbnails have a fixed 600-second cache lifetime. Cache hits do not
extend that lifetime. Existing entry and byte capacity limits still apply, so
entries may be evicted earlier under load.

A single background sweeper removes expired cache references even when no
further reads occur. It checks once per second while values remain and stops
when the registered caches are empty. Android process suspension may delay
maintenance; every lookup independently rejects expired values.

The existing MainActivity background/lock-screen cleanup and memory-pressure
handling also clear registered sensitive caches. The longer TTL does not
disable those lifecycle boundaries, change persisted history, unload ASR/QNN
models or modify attachment encryption.

Preference cache character arrays are overwritten on eviction. Transcript
strings and bitmaps are released from the cache, not forcibly overwritten or
recycled while UI consumers may still own them. This policy bounds these
caches, not the lifetime of every plaintext reference elsewhere in the process.
It is not a guarantee that garbage collection immediately erases physical RAM.

## Non-sensitive static metadata

The model invocation catalog uses a separate, bounded 24-hour cache containing
model identifiers, names, descriptions and supported reasoning strengths. It
does not retain the source JSON, credentials, pairing secrets, routes, messages
or live availability. Oversized catalogs remain usable but bypass retention.

Catalog content fingerprints prevent reuse for changed metadata. Application
version changes, model selection/planner changes, contact changes and pairing
or trust changes invalidate cached catalog entries. Runtime route availability
continues to be evaluated outside this cache.

## Verification

Unit tests cover fixed TTL boundaries, maintenance without subsequent reads,
capacity eviction, lifecycle clearing, catalog invalidation, immutable catalog
collections and exclusion of credential fields. The complementary recovery and
database changes and device comparison are described in
[Android recovery efficiency](../architecture/android-recovery-efficiency.md).
Cache lifetime changes alone do not resolve background reconciliation or
database allocation hotspots.
