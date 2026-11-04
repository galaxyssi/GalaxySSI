# Android health report edge suggestions

Report-mode preparation decodes the saved image in EXIF-corrected orientation and scores quality before recognition. The detector samples a bounded grayscale image, requires consistent light-to-dark boundaries on all four sides, and proposes a padded rectangle containing the fitted corners. It does not deskew, automatically crop, start recognition, or modify the original. Device-display mode retains the existing quality checks without looking for paper edges.

The draft thumbnail shows the suggested rectangle. The crop control opens the existing adjustable crop editor at those bounds; manual cropping and retake remain available for unclear or clipped borders. The suggestion coordinates are encrypted with the page metadata, and no separate detection image is saved.

Coverage includes multiple image sizes, a skewed report with text, low contrast, clipped and borderless images, actual EXIF rotation, the native draft thumbnail, and crop-editor coordinates. Fixtures are synthetic; this is not live Camera2 autofocus, exposure or sensor validation.

Validated with 11 JVM tests and 76 Samsung Galaxy Tab Active3 instrumentation tests on Android debug 0.1.7.60. No test was skipped. The native draft screenshot was inspected with the original thumbnail and suggested crop visible.
