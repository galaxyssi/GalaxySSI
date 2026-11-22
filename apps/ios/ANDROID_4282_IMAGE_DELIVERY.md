# Android #4282: resumable image transport on iOS

Source: https://github.com/galaxyssi/GalaxySSI/pull/4282

## Production mapping

- New durable Signal transfers use a 60 KiB framed direct threshold and 44 KiB
  fragment data. Protocol ceilings remain unchanged. Encrypted resume metadata
  retains fragment geometry; pre-profile records use their original 380 KiB layout.
- Fragment flights outlive broker PUBACK. Only authenticated, committed peer
  bitmaps release those observations. Each broker starts with a 256 KiB peer
  window, grows to 512 KiB on unambiguous peer confirmation, and halves on expiry
  down to 128 KiB. An oversized legacy fragment can progress alone on an idle path.
- Selection and reservation both enforce the window. Reservation and observation
  are atomic. Congestion pauses the fragment pump without failing the durable
  message or advancing its retry counter when nothing was admitted.
- An in-flight request survives maintenance ticks for 30 seconds, allowing late
  bitmaps to release the window. Already tracked parts are skipped before sealing.
- Physical queues rotate a transfer's remaining parts behind other transfers.
  Path budgets reserve slots for other connected brokers and control traffic.
  Small messages account for unconfirmed image backlog when choosing a path.
- The production runtime coalesces chunk state by authenticated scope, transfer
  and request. Backpressure retains the newest revision, with 500 ms retries,
  30 second expiry, 64 entries per peer and 1024 globally. Complete bitmaps and
  probes are urgent but use the same limits. Relationship retirement clears slots.
- Receipt publication retains physical completion tokens. Enqueue is not success;
  one-second missing PUBACK or physical failure permits another authorized broker.
  At most one pending copy uses a broker/configuration/generation. Late completions
  cannot overwrite a newer copy. Successful PUBACK invalidates remaining copies.
  A committed receipt can still reply on current authenticated ingress before the
  outgoing route handshake completes; fallback paths require verified routes.
- Repeat application attachment chunks reuse an encrypted pending record for the
  same authenticated binding, transfer and chunk index before Signal encryption.
  Conflicting chunk digests fail closed. Optional metadata keeps old rows readable;
  no unencrypted attachment content or broad queue deletion is introduced.
- Incomplete inbound transfers are capped at 64 per peer / 128 globally, retaining
  the 16 MiB per-peer / 32 MiB global byte caps. Non-auto-downloaded documents
  start as available rather than showing an indefinite uploading indicator.

## Verification

Focused XCTest source covers smaller and legacy geometry, peer-window release,
expiry, wrong-peer isolation, PUBACK fallback, feedback replacement/retry/capacity,
coalescing across database reopen, and the real send drain's paused/resumed round.
The project structure check, Swift grammar comparison and diff whitespace checks
are runnable on Windows. XCTest execution, Swift type checking and live phone
image exchange require macOS/Xcode or devices and are not claimed here.
