# Android #3815: paper hints in photo collections

Reference: `1006f6087`. The merged iOS #3827 already implements a native Vision
paper detector, manual crop controls, explicit saving and source-coordinate
conversion. Later crop-save/recovery work remains in place. This follow-up fills
the missing photo-collection inspection, persisted hint and handoff path; it does
not duplicate the independent crop implementation.

## Implementation

- Inspect report pages off the main actor using the existing bounded upright
  thumbnail and Vision detector after existing quality inspection. Device-reading
  mode never enters paper detection. Preserve task cancellation; a detector error
  is unchecked, not a false claim that no edges were found.
- Persist an optional paper hint with the encrypted draft entry, bound to the
  immutable original SHA256. A checked result may contain no bounds. Legacy entries
  remain unchecked. Validate finite in-range bounds and exact hash before install
  or display; a foreign hint cannot mutate the collection. Retakes clear previous
  suggestions unless a new validated result is supplied; reordering keeps bindings.
- Show checked/no-edge status and an aspect-fit, top-origin suggested rectangle in
  each collection thumbnail. Offer a localized suggested-crop action when present.
  These are image-quality hints, not medical interpretation or OCR guarantees.
- Pass the exact original-bound hint into the existing crop page. Reuse it only
  for the requested original ID and digest. Keep an existing saved crop first;
  otherwise seed the controls from the hint. Unchecked/legacy input follows the
  existing independent detection path. Saving remains explicit, encrypted,
  revision-checked and separate from the original bytes and recognition queue.
- No Android/Desktop, model, permission, backup format, cloud, CI or IPA changes.
  Vision is the existing iOS detector, not a byte-identical Android pixel algorithm.
  No claim of identical detector output or native rendered UI acceptance.

## Verification

Six dedicated XCTest methods authored, NOT executed: legacy/no-edge coding,
malformed/nonfinite bounds, foreign hash/device-mode refusal, reorder/retake,
encrypted page reload and failed foreign-hint commit, device inspection exclusion.
Four Xcode test registrations; the large existing health fixture file is unchanged.

`check-photo-paper-hints.cjs` pins the exact new hooks, three localized resources,
registration and 19 negative source mutations. It removes only owned hooks and
composes with the photo-retention guard if present, preserving all prior crop
encoding, detection, persistence, retention and owner/version checks. Source checks
do not compile Swift or run these scenarios.

No Swift/Xcode build, XCTest execution, Vision/device photos, native storage faults,
camera/album/crop UI, restart or performance acceptance, CI inspection or IPA.
