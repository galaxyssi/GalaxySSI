# Android Cloud Image Annotation

## PR integration

Before submission, origin/main at `ced9fd5f4` was merged, preserving its memory
enrollment/count performance changes. Since main had advanced to 1.1.92 (978),
this PR advances Android to 1.1.93 (979). The device/live evidence below was
captured on the feature build 1.1.91 (977), before that merge; it must not be
described as a device acceptance run of 1.1.93. No device reinstall was requested
as part of PR submission.

## Problem and implementation

Direct cloud conversations exposed web tools but no image editing tool. A model
could describe mistakes in an uploaded worksheet without being able to produce
the marked-up image requested by the user.

When the current request has image attachments, its cloud tool catalog now
includes `image_annotate`. The model provides an image index, normalized upright
rectangles, a verdict, and correction notes. Android renders the annotation onto
a separate PNG and appends the verified local image block to the final response.
The uploaded original is not modified. Notes are below the source image, with
numbered boxes and verdict marks on the source image. Ordinary text requests do
not receive this extra tool or its instructions.

This is model-guided local image editing, not native generative-image inference.
It does not require a Desktop executor and cannot make a text-only provider see
images. The existing provider vision routing remains in effect.

## Boundaries

- Inputs are scoped to the current request; no arbitrary file paths or scripts
  are accepted as tool arguments.
- Coordinates, verdicts, note lengths and mark counts are validated. Unreadable
  handwriting must be marked uncertain, not guessed.
- At most 24 marks are accepted per invocation. Preview decoding is bounded to
  2000 x 2000, output to 12 million pixels and 12 MiB.
- One renderer runs at a time across windows. Web tools keep their existing
  parallel execution. Waiting is cancellable and bounded.
- Atomic files and SHA-256 metadata back the image cards. Saving rechecks the
  local output before writing to Downloads/GalaxySSI.
- Local image URIs are not included in tool results sent back to the provider.
- Reusing a cached annotation tool result selects that result's revision, so an
  A -> B -> cached A sequence cannot accidentally present B as A.
- Existing thumbnail, fullscreen and Save interfaces are reused without changing
  the conversation layout or background colors.

## Verification

- Android version: 1.1.91 (977).
- Build: debug APK and test APK compiled successfully with an 8 GiB build-only
  Gradle heap override and the existing Rust/NDK toolchain.
- JVM: 25 focused tests passed (annotation schema/progress 9, image payload 4,
  web grounding 8, tool-loop progress 4).
- Initial S26U (SM-S9480) device run: 5/5 passed, including the mock-provider tool
  loop and thumbnail -> fullscreen -> Save UI. No other device was operated.
- Real configured DeepSeek run: passed using `deepseek-v4-flash-vision-exp`,
  with one image returned. The synthetic worksheet had three answers: two
  correct and one incorrect. The model correctly corrected `6 - 2 = 5` to `4`.
  Total engine elapsed time was 3774 ms; the annotation tool ran at 2537 ms and
  completed at 2592 ms (55 ms). This excludes main-screen dispatch overhead.
- The returned PNG was 40693 bytes. Visual inspection confirmed three correctly
  placed boxes, verdict marks and Chinese notes; its SHA-256 was
  `6a4f827eb167b7338515a6576dca7657827eb3aab7d79352d4d1804ef3742a4f`.
- Final build and reinstall: debug APK and test APK rebuilt successfully; the
  same 25 JVM tests passed. S26U received the final 1.1.91 (977) APK, with app
  data retained, and the app was started after testing.
- Final device regression: 12/12 passed (annotation 5, annotation UI 1, model
  routing 2, existing Markdown image rendering 4). This includes cached A -> B
  -> A selection, failure retry, streaming/final/history rendering, fullscreen
  Save, Chinese titles and hidden technical footers.
- Second live DeepSeek run on the final package also passed: 3379 ms total,
  65 ms annotation execution, one 41620-byte PNG. Visual inspection again
  confirmed all three verdicts and the correct replacement answer of 4.
  SHA-256: `57e2a5c8a512cab4190b7fefe4291d9f6c7cbd35819f774b3aed3f50d5a11422`.

Device tests exercise rendered pixels, source preservation, content-provider
loading, rich-content persistence, request isolation, deduplication, save/hash
validation, a mock-provider/real-renderer tool loop, and fullscreen Save UI.

`CloudImageAnnotationLiveTest` is opt-in (`-e live_annotation true`). It uses the
configured DeepSeek provider and only a synthetic three-question worksheet. It
does not export credentials or existing conversation history. Its report and
rendered image are stored under the app's external `files/reports` directory.

## Remaining acceptance

Passing a renderer or mocked-provider test does not prove actual DeepSeek tool
calling or grading quality. The separately reported live result above covers
only the simple synthetic worksheet, not general grading accuracy.
Handwriting, dense worksheets, formulas and ambiguous answers need additional
accuracy evaluation; the existing model-input image compression also remains a
potential readability limit.
