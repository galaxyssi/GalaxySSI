# Contact Chat Top Alignment

## Scope

Short contact conversations previously used bottom stacking, leaving most of
the viewport empty above their messages. Disable bottom stacking both during
RecyclerView initialization and when switching contacts. Keep chronological
adapter order, latest-message navigation, history paging, and the existing
system-notification behavior unchanged.

No message data, bubble styling, input controls, Desktop code, or voices changed.

## Validation

- ChatMessageViewportPolicyTest: 4 passed.
- ChatHistoryLoadPolicyTest: 3 passed.
- Debug APK and instrumentation APK built with the complete embedded runtime.
- Both APKs installed with replacement, without clearing data, only on SM-T575.
- ChatMessageViewportDeviceTest: 3 passed in 3.397 seconds. This includes short
  and long RecyclerView layout cases plus the existing DESKTOP-T14 conversation.
- Existing short-chat acceptance verifies the first row touches the viewport
  start and all rows fit without scrolling. No messages were sent or deleted.
- Kotlin source-size and git diff whitespace checks passed.

The first package attempt lacked the pinned llama.cpp submodule. It was
initialized from the identical local commit and the complete build passed.
The temporary build heap override and generated runtime paths are not committed.

The device acceptance above used Android 1.0.39 (883), a local validation build.
The PR rebases the fix onto main and increments Android from 1.0.40 (884) to
1.0.41 (885). The version bump does not constitute a new device installation;
the earlier device results are not claimed as a retest of the rebased APK.
