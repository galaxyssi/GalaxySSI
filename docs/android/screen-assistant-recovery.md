# Screen assistant connection recovery

The floating screen assistant uses an Android accessibility service, not a persistent
MediaProjection recording grant. The saved user preference, Android authorization,
and the live service connection are separate states.

## Recovery contract

- Only `onServiceConnected` publishes an active service. `onCreate` is not evidence
  that Android has bound it. Unbinding clears the active reference and the overlay.
- A missing or temporarily unavailable authorization never erases the user's
  assistant preference, pending screenshot, conversation, or turn identity.
- The settings page distinguishes disabled, permission required, disconnected, and
  connected states. Disconnected services offer an explicit system-settings action.
- Connection events update the visible settings page; there is no polling loop,
  automatic permission rewrite, or repeated authorization prompt.
- Android owns service binding. After a vendor force-stop leaves an authorized
  service disconnected, switching that service off and on in system settings may
  be necessary. The App does not silently toggle secure settings or other services.
- The optional system accessibility shortcut is separate from the App overlay.
  The App does not request an accessibility button; the OEM settings row is not
  part of the App UI and cannot be hidden by this change.

## Diagnosis and validation

On the affected S26U, the assistant preference and Android authorization were both
enabled, but `dumpsys accessibility` had an empty bound-service list and listed the
service as crashed. Recent process-exit records showed Samsung `MARs #2` force-stops,
not a contemporaneous Java exception. A crashed binding alone is not a Java-crash
diagnosis. System background restrictions must be inspected separately.

Regression coverage includes authorization without a connection, connection loss
and recovery, retained preferences, inactive service construction, settings-row
presentation, single event delivery, and listener removal before a queued callback.
On-device verification should also cover the floating entry after returning home
and re-entering the App, with the optional system shortcut left disabled.

This change does not modify world-model, message-service, news, or model settings.
