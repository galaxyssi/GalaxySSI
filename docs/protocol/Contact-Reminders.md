# Contact Reminders

## Interaction

Android 1.5.71 adds an independent reminder action to the direct-contact composer;
1.5.72 separates playback lifetime from the transient reminder window.
It reuses the Agent voice-entry waveform artwork, not the Agent voice handler.
An empty, idle contact composer shows the reminder icon. Editing and attachment
selection retain the existing more/send controls. Tapping the reminder does not
record, transcribe, invoke a model, clear the draft, or change hold-to-talk.

The receiving Android device shows a top-aligned, non-dimming panel around 20% of
the display height (with an accessibility minimum). Mute stops this reminder's
sound; Ignore dismisses it; Got it acknowledges it to the sender. Swipe up or Back
mutes and collapses the incoming panel. The sender can cancel an active reminder.
Status is stored in the contact conversation without creating an Agent run.

Long-press the contact reminder icon for receiving preferences. Receiving and
alarm-stream sound in silent mode are on by default; the lockscreen panel is off
by default. System notification, full-screen-intent, alarm volume, DND, and background
execution policies still apply. No keyguard dismissal or global volume change is
performed. A detected phone/VoIP call or active recording receives a quiet notification. Missing phone
state permission limits detection to Android audio mode. MQTT is not a guaranteed
OS wake-up or push service: offline/force-stopped peers may miss the lifetime.

Desktop 1.5.4 receives these reminders in an independent compact panel and returns
acknowledgements. Its existing voice recording controls are unchanged. A background
Desktop window uses a generic system notification, respecting the OS sound/DND
policy. Both peers must run a version supporting this feature; do not infer support
from the existence of a paired contact alone.

## Encrypted Control Envelope

The existing authenticated, end-to-end encrypted paired transport carries:

```json
{
  "type": "peer_attention",
  "peer_chat": true,
  "reminder_id": "b61bb9a5-bb9f-4d04-8a4d-3ecbd787a371",
  "reminder_action": "request",
  "created_at": 1792320000000,
  "expires_at": 1792320120000,
  "time": 1792320000000,
  "contact_id": "authenticated-target-or-sender"
}
```

The recipient identity comes from the authenticated paired transport, never from
an untrusted display name. Phone-to-Desktop `contact_id` must target this Desktop.
Phone-to-phone transport authenticates the sender independently of this field.

Actions: sender `request` / `cancelled`; recipient `received`, `quiet`, `muted`,
`acknowledged`, `dismissed`, or `disabled`. Delivered means the receiving app stored
the request, not that the person read it. Confirmation is an explicit user action.
Control traffic shares the existing reserved transport lane; no new public MQTT
topic, attachment, audio stream, WebRTC session, or Agent execution is introduced.

## Lifetime and Recovery

- Requests have a maximum 120-second lifetime and 30-second sound, independent of
  notification/ringer volume when silent-mode sound is enabled. The OS alarm
  volume and DND policy still apply; no global volume is raised.
- Reopening, backgrounding, or destroying the panel does not stop the sound.
  Explicit mute/ignore/acknowledge/cancel, audio focus loss, a call/recording,
  or the sound deadline stops it. Only opaque state is retained by the bounded
  application-owned player; it never retains the Activity.
- A reminder ID binds the authenticated peer, creation time, and expiry time.
- State is persisted before sound/UI side effects; duplicate delivery does not ring again.
- A cancellation arriving first creates a tombstone. Terminal state cannot regress.
- Expired incoming requests are discarded, including after restart/reconnect.
- Android schedules expiry independently of the panel; service startup restores
  pending expiry and expires stale records without restarting the sound.
- Android reminder rows use the existing Keystore-backed row cipher; Desktop rows
  use device-bound AES-GCM. Replay tombstones are pruned after expiry plus one day.
- Notification text hides the sender name on the lockscreen. Opening the panel
  does not unlock the device. Private names are hidden while keyguard is locked.

## Verification

`ContactReminderPolicyTest` covers envelope lifetime, terminal transitions, stale
receipts, and composer modes. `ContactReminderInstrumentedTest` checks encrypted
row reopening, pruning, the real contact layout, and the top panel's expiry. The
panel fixture writes only its own test reminder, with no history or network send.

Desktop `tests/test_peer_reminders.py` covers concurrent duplicates, restart,
wrong-peer controls, malformed input, encrypted fields, and expiry. Existing
peer-route, chat-store, voice-playback, and hold-to-talk tests remain part of the
regression run. Device-network validation is recorded separately from fixture
tests; neither fixture results nor broker ACKs prove human acknowledgement.

### Device validation (2026-10-18)

- Android 1.5.71 / 1354 was installed in place on SM-G9880 and SM-S9480,
  preserving pairing and chat data.
- Both devices remained in SILENT mode with DND off. Bidirectional reminders
  produced an active `USAGE_ALARM` player; the alarm streams remained unmuted.
  Mute stopped playback and Got it returned an acknowledged receipt.
- With the S20U app backgrounded, a reminder still played through the alarm
  stream and posted a notification. Sender cancellation stopped the playback.
- 25 Android unit tests and 14 S20U instrumentation tests passed, covering the
  reminder policy, MQTT priority, composer modes, encrypted records, panel expiry,
  text selection, and existing hold-to-talk behavior. The test host disables OEM
  remote smart selection so asynchronous callbacks cannot outlive its window.
- The APK passed the 16 KB alignment audit for 74 AArch64 libraries. Repository
  checks passed. Desktop fixture tests and responsive panel checks passed; a
  live Phone-to-Desktop reminder has not yet been verified.

These checks verify audio routing, not a microphone recording of audible output.
Real carrier-call interruption, OEM lockscreen/full-screen permissions, force-stop,
and alarm-blocking DND configurations still require separate device acceptance.

### Audible-output follow-up

The user reported that the 1.5.71 test was not audible despite active playback
telemetry. Do not treat that telemetry as successful acoustic acceptance.
The follow-up fixes a confirmed lifecycle defect: panel `onPause`, `onDestroy`,
and `onNewIntent` used to stop the independent sound, including a notification
reopening the already-visible panel. Debug builds now log non-sensitive start,
skip, and stop reasons; release builds do not emit these diagnostics.

`ContactReminderAudioDeviceTest` is deliberately opt-in (`-e reminderAudioProbe
true`). It plays but never records audio or sends messages. It checks real
playback across panel reopen/background/destruction, explicit stop, and unchanged
ringer/volume settings. `-e probeSeconds 8` adds an eight-second listening window.
This remains a playback-state test; human hearing confirmation is separate.

Android 1.5.72 / 1355 was subsequently installed in place on both phones. The
S20U real-audio probe passed, preserving SILENT mode and alarm volume 11/15, and
the user confirmed hearing the sound. The 13 policy unit tests, 3 reminder
instrumentation tests, and 11 composer regression tests passed in targeted runs.
The expiry fixture blocks live-device interaction with its synthetic reminder so
an unrelated acknowledgement cannot replace the expiration being tested.
No further live bidirectional test was performed after S26U reconnected.
