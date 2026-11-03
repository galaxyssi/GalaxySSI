# Direct Remote Input

The Android remote display uses the existing paired, authorized, signed Desktop
control request/receipt protocol. It does not grant Agent tasks additional access.

Remote Desktop screenshots use one baseline JPEG encode at quality 70 and 4:2:0
subsampling, with the longest edge limited to 1280 pixels without upscaling. The
encoder does not search multiple sizes/qualities, optimize Huffman tables, or use
progressive encoding. Frames above 100,000 bytes are rejected with
`screenshot_too_large`, not retried by the encoder or sent oversized. The shared
Agent image transport compressor and its 100,000-byte budget are unchanged.
The byte cap is not a target size or a guarantee that every screen fits: dense
4K text and high-entropy scenes can exceed it at the fixed 1280-pixel preset.
The default refresh rate is 1 FPS with one capture request in flight; slower
transport can extend the actual interval. Original screen dimensions remain in
the receipt so resizing does not change input coordinates.

The foreground display reconciles its stream with the actual scheduler and
Desktop session handle. A missing/expired handle renews authorization; a new
handle restarts observation and clears obsolete in-flight frames. Late failures
for previous sessions cannot stop the new stream. A bounded foreground watchdog
reconciles missing events, but never replays keyboard or mouse input. Frame errors
and a missing first frame are visible instead of an indefinite connecting label.

- `click_xy`, `type_text`, `hotkey`, and `scroll` accept `interactive_input: true`.
  These requests return compact signed receipts without capturing a new screenshot
  or publishing a redundant running event. Screenshot streaming remains separate.
- `click_xy` accepts `clicks: 1|2` (default 1). Double clicks are left-button only.
  A long press sends one right click, never a preceding left click.
- Receipts include `output.input_focus`: `available`, `editable`, `password`,
  `target_id`, and `bounds` relative to the selected display/window. No field text,
  password value, document content, or control name is returned. Windows reads only
  the focused UI Automation control through a lazy, bounded worker.
- `type_text` and `hotkey` may include `input_target_id`. If the focused editable
  control changed, Desktop returns `input_focus_changed` without injecting input.
  Manual keyboard mode omits this binding for inaccessible custom controls.
- Input actions retain durable action-ID deduplication. Android serializes actions
  until their own verified receipt arrives; screenshot receipts cannot overwrite
  input acknowledgments. Timeout, disconnect, or leaving the page clears pending
  queued actions. Unconfirmed input is never automatically replayed.
- A left click reporting an editable focused control opens the local composer and
  keyboard together, without an intermediate collapsed input step. The composer
  reuses the Agent/contact editor, action icons, and edit/hold-to-talk policy.
  IME composition, pasted text, newlines, and recognized speech stay in the local
  draft. Only the send button creates one `type_text` action; it does not append an
  Enter key or submit the computer form. The editor grows to eight visible lines.
- Successful receipts clear only the exact draft revision submitted. Edits made
  while waiting survive the receipt. Failure/timeout retains the foreground draft
  with a warning to check the computer before retrying. Backgrounding clears it;
  draft contents are never serialized into instance state, logs, or files.
- Voice input uses the existing 16 kHz local Whisper/QNN recognition path and
  appends the transcript to the draft, never dispatching an Agent task. The more
  menu switches to hold-to-talk; swiping up cancels, releasing transcribes. PCM
  buffers are cleared after use, and late results cannot revive a closed editor.
- Auto keyboard opens after a left click reports an editable focused control.
  Custom surfaces without accessibility metadata use the overflow keyboard action.
  Long press, pinch zoom, local panning, and two-finger remote scrolling use direct
  gestures; the existing advanced controls remain available in the overflow menu.

No broker topic, pairing key, identity, signature, or screenshot verification
format changes. Legacy callers without these optional input fields retain their
existing screenshot receipts.
