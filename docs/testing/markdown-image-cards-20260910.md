# Markdown Image Cards

## Regression and Scope

Android rendered explicit `![label](https://...)` as a literal exclamation mark
and an ordinary clickable link. Final replies wrapped in TEXT blocks and saved
history had the same problem. Image cards also exposed English artifact filenames
and generated category/size footers such as `outputs - 97.6 KB`.

- Parse explicit web images in text paragraphs with CommonMark; keep ordinary
  links, escaped examples, and code samples unchanged.
- Use the same promotion for streaming text, final TEXT blocks, and history.
- Reuse thumbnails, the full-screen viewer, and save controls.
- Keep a visible failure placeholder, retry, and source action on load failure.
- Cache downloads off the UI thread, with a 12 MiB per-image and 64 MiB cache limit.
- Automatic downloads require HTTPS and reject credentials and local/private DNS
  destinations. Each redirect is checked. Unsupported or HTTP sources keep the
  failure UI rather than silently becoming text links.
- In Chinese UI, retain Chinese image titles or use an unambiguous matching
  Markdown link label. Otherwise display the localized image label, without
  guessing a translation or renaming the downloaded file.
- Hide generated image category/size footers while retaining meaningful captions.
- No Desktop, MQTT, database, pairing, or contact changes.
- PR version: 1.1.60 (946), refreshed onto main `9d6761ed7`.
- Device validation build: 1.1.59 (945), based on main `3bdd66140`.

## Verification

- `AgentMarkdownImagesTest`: 10 passed.
- `AgentImagePresentationTest`: 8 passed.
- `AgentRichContentTest`: 18 passed.
- `AgentFinalMarkdownTableTest`: 5 passed.
- `AgentInlineMarkdownTest`: 2 passed.
- Debug APK and instrumentation APK built successfully.
- S26U / SM-S9480: installed with `adb install -r`, preserving user data.
- `AgentMarkdownImageRenderingTest`: 4 passed on device validation build 1.1.59.
  Covers streaming/final/history image views, failure/source/retry recovery,
  full-screen saving with exact byte equality, Chinese titles, and hidden footers.
- The original historical external image loaded visibly after installation.
  Its Wikimedia URL returned JPEG successfully. The saved 723,580-byte original
  matched the cached SHA-256:
  `ede6da3379d84903a6b36958bea407058a888da04f8d810d4fcb8292ea67e66d`.
- The user's later two-image reply was checked on 1.1.59: no English filename
  headers and no category/size footers. No associated Chinese link labels were
  available in that reply, so both cards correctly used the localized fallback.
- App relaunched after instrumentation. No other connected phone was operated.

The instrumented network failure/cache fixtures are deterministic. They do not
prove availability of every external image host, expired URL, or hotlink policy.
The later main-branch memory changes and version-only increment were not part
of that device run; submitting this PR does not reinstall or alter the phone.
