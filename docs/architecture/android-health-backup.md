# Android Portable Health Backup

The Data and Files page exposes an encrypted backup creator and a read-only
verifier. The creator previews the current confirmed self measurements, date
range, counts, original names, known missing originals, and approximate size.
It requires separate confirmation and matching password input. Drafts, derived
AI results, profile background, device keys, and device-local paths are not
included. The optional owner label is inside the encrypted manifest.

## Format Version 1

- The binary header consists of the eight ASCII bytes `GSSIHBAK`, a big-endian
  32-bit format version, a random 16-byte salt, and a 32-byte unlock proof.
- PBKDF2-HMAC-SHA256 at 600,000 iterations derives a 32-byte master from the
  password and salt. HMAC-SHA256 with distinct versioned context labels derives
  the proof key and stream key. The proof authenticates the first 28 header
  bytes; those same bytes are associated data for the encrypted stream.
- The payload uses Tink AES256-GCM-HKDF streaming AEAD in 64 KiB segments.
  Inside the encrypted payload are a framed JSON manifest, original frames
  in ascending UUID order with exact bytes following each present entry,
  current observation frames in ascending UUID order, and an end marker.
  JSON frames are limited to 256 KiB. Original payloads are streamed and are
  not unpacked as filesystem paths.
- Original lengths and SHA-256 digests, counts, ranges, exact observation-to-
  original links, and authenticated end of stream are verified. A package
  with known missing original bytes stays explicitly incomplete. Unknown,
  legacy, and future formats are not interpreted as ordinary JSON imports.

The exporter reads observations and originals in bounded database pages and
checks the frozen scope before and after generation. It verifies original
bytes while copying and never stages plaintext. Generation publishes the
private artifact only after the encrypted file is closed and synchronized.
System save requires user selection and SHA-256 read-back verification.
Sharing opens the system chooser only after a separate user action.

## Restoration Boundary

The verifier is read-only. Its streaming callbacks are available for a future
restore staging area; callbacks alone are not proof that the entire file is
valid. The merge path must verify authenticated EOF before writing any live
data. The restore batch, per-conflict choices, alternate profiles, historical
revisions, durable task history and crash rollback are not implemented by the
portable export increment. Do not claim successful recovery from successful
backup verification.
