# Android Portable Health Backup

The Data and Files page exposes an encrypted backup creator and a read-only
verifier. The creator previews the current confirmed self measurements, date
range, counts, original names, known missing originals, and approximate size.
It requires separate confirmation and matching password input. Drafts, derived
AI results, profile background, device keys, and device-local paths are not
included. The optional owner label is inside the encrypted manifest.

## Format Version 2

- The binary header consists of the eight ASCII bytes `GSSIHBAK`, a big-endian
  32-bit format version, a random 16-byte salt, and a 32-byte unlock proof.
- PBKDF2-HMAC-SHA256 at 600,000 iterations derives a 32-byte master from the
  password and salt. HMAC-SHA256 with distinct versioned context labels derives
  the proof key and stream key. The proof authenticates the first 28 header
  bytes; those same bytes are associated data for the encrypted stream.
- The payload uses Tink AES256-GCM-HKDF streaming AEAD in 64 KiB segments.
  Inside the encrypted payload are a framed JSON manifest, original frames
  in ascending UUID order with exact bytes following each present entry,
  current observations in ascending UUID order, and an end marker. Each
  observation is followed by zero or more secondary source evidence frames
  for its current revision and a zero-length group terminator.
  JSON frames are limited to 256 KiB. Original payloads are streamed and are
  not unpacked as filesystem paths.
- Original lengths and SHA-256 digests, counts, ranges, primary and secondary
  source identities, and authenticated end of stream are verified. Missing
  original bytes are marked without dropping their associated evidence.
- Version 1 packages remain readable and contain only primary sources. Both
  formats use the original key derivation labels and authenticate the header
  version. Unknown and future formats are rejected.

The exporter reads observations, original metadata and source links in bounded database pages and
checks the frozen scope before and after generation. It verifies original
bytes while copying and never stages plaintext. Generation publishes the
private artifact only after the encrypted file is closed and synchronized.
System save requires user selection and SHA-256 read-back verification.
Sharing opens the system chooser only after a separate user action.

## Restoration Boundary

The verifier remains read-only. The separate
[restore flow](android-health-restore.md) stages encrypted data, verifies
authenticated EOF and previews conflicts before it can write to the live
database. Backup verification alone is not successful recovery.
