# Voice Message Recipient Correction

Android parity source: PR #4627, merge 5b074d5f5f9fa3f001b44638d3f7ccd2f6b92d02.

`galaxyssi.app.voice_message` owns a transient phone-side draft. Legacy
`galaxyssi.app.send_message` prepares rather than sends during voice control.
Ordinary typed messaging is unchanged. Both tools retain foreground, session,
privacy, consent, deadline and native idempotency checks.

- A monotonic 180-second lifetime and owner/window/conversation/session scope
  prevent drafts from surviving navigation, privacy clearing or voice exit.
  Moving to the next utterance in the same capture surface preserves the draft.
- Exact-name lookup returns at most 64 verified phone/Desktop candidates. Names
  are not substring-selected. Duplicate names produce native numbered choices;
  the actual later spoken ordinal must match the requested contact ID.
- Recipient correction preserves the body byte-for-byte and rotates revision.
  Choosing a recipient also rotates revision. A later captured utterance must
  exactly match a supported explicit confirmation phrase. Model booleans,
  negations, quoted prose and typed/edited legacy submissions do not authorize it.
- Capture controllers supply speech evidence independently of model tool input.
  When correction review exists, confirmation uses its original fast ASR text,
  not model-corrected text. Unknown legacy origins fail closed. A nullable
  `voiceInput` classification is stored in the existing encrypted turn receipt;
  an absent historical field is not inferred to mean text.
- Confirmation claims the revision synchronously before any queue operation and
  rechecks the exact recipient identity/route binding. Phone transport is retained;
  Desktop uses its existing journal queue or encrypted legacy durable outbox.
- Queue failure or uncertainty consumes the draft. Queued/published/uncertain
  drafts cannot be changed, recalled, or confirmed again with a different tool
  key. No result asserts delivery. Terminal states remove draft body/candidates.
  An explicitly new message on a later turn may create a separate draft.

The draft controller and speech facts are memory-only. Existing encrypted native
tool history may still contain preparation inputs/results; this change does not
introduce a second persistent draft or silently erase established audit history.

Source validation: `node apps/ios/tools/check-voice-message-draft-scope.cjs` and
`npm run check:ios`. Synthetic XCTest source covers revisions, confirmation,
choice, replay, expiry, uncertain sends and lifecycle fencing. These checks do
not establish Swift compilation, ASR quality, device behavior or transport
delivery; native compilation/tests and IPA generation are not part of this PR.
