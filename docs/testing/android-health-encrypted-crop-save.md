# Android health encrypted crop save

The health crop editor uses the existing image cropper with a one-shot, same-UID output pipe. Unlike the ordinary chat attachment flow, it never creates a plaintext crop file. The importer writes the streamed bytes into authenticated encrypted staging, verifies that the encoder reported success, and checks image quality from the encrypted staging stream before publication.

In a photo draft, the ready crop, new job and original metadata replace the old page in its existing position in one transaction. An invalid image, failed write, submitted batch, or stale page leaves the old draft intact. A retained original is not modified; review-only data remains review-only, and the previous review-only file is released only after a successful replacement. Cropping an image from original detail instead creates a separate import. Recognition of camera draft pages still requires explicit submission.

Regression coverage: native cropper output with a filesystem observer on the ordinary plaintext cache path, exact original bytes, expected cropped dimensions, one-writer enforcement, truncated or rejected encoder output, late cancelled writes, transaction rollback, and review-only retention.

Validated on Samsung Galaxy Tab Active3 (SM-T575), Android debug 0.1.7.61: 47 crop, editor, capture and review tests, 65 original-library, migration and export tests, and one additional JPEG and cancellation test passed without skips. Tests used synthetic images and did not open the camera. Physical process-death acceptance remains separate.
