# Android #4558: iOS Model Catalog and Routing

Pinned source: `9229e18652978c14e3bb4fe3454b32d77ff3f0a7` (open Android/Desktop PR #4558).
This iOS-only change is based on main `ee17e7cac043350e3f65c10ba025ecf55cde10c7`, not on unmerged iOS PR #4557.
The accompanying JSON accounts for all 19 source paths with SHA-256 and dispositions.

## Implemented

- Copy the 21 cloud preset rows, names, endpoints and protocol styles exactly.
  Direct OpenAI remains Chat Completions; GPT-6.2 is offered via OpenRouter only.
  Catalog parity is not a claim of live vendor availability or account entitlement.
- Decode optional Desktop `model_aliases`; accept only aliases from noncurrent IDs to
  current advertised models. No dangling redirects, chains or replacement of current IDs.
  Older advertisements decode with an empty map. Unknown saved IDs remain unknown when
  canonicalizing an outbound explicit choice.
- Keep Desktop model options authoritative from the paired advertisement, including
  new Codex/Claude options. Do not add an invented local catalog. Keep reasoning effort.
- Official DeepSeek legacy Flash/vision IDs resolve to `deepseek-flash`.
  Image turns selecting direct Pro temporarily use Flash. Current canonical credentials
  win, followed by explicit legacy request, selected legacy ID, legacy vision and Flash.
  Only matching direct HTTPS routes may supply those Keychain references.
- Other official providers expose presets only after exact endpoint/protocol verification.
  Gemini verifies the saved model-bearing path before substituting another preset.
  Custom/proxy endpoints, insecure/lookalike hosts and other model IDs remain unchanged.
- Switch pages and home/picker labels use canonical IDs. Explicit switching persists a
  derived configuration on the same contact, with a Keychain reference, not a copied
  plaintext key. Remove the former arbitrary first-key reuse across endpoints.
- Preserve exact replay route fingerprints; a changed legacy route fails closed and
  requires a fresh user-approved turn rather than silently rebinding an archived retry.

## Scope and Verification

No Android/Desktop code, version bump, IPA, CI watching, native build, XCTest execution
or live API invocation. The existing registered routing test file contains the added
fixture source; these cases are **not executed**. This is not native acceptance evidence.

Source checks: `npm run check:ios`, literal cloud catalog comparison against the pinned
Android source, `git diff --check`, and Swift grammar inspection. The large Services file
has 96 baseline parser ERROR nodes, including a whole-file node; the other 95 node texts
are unchanged. Changed Swift files outside that baseline file have zero ERROR nodes.
Grammar inspection is not Xcode typechecking, UI verification or device execution.

The Android PR is still open; later changes to its head need a separate review.
