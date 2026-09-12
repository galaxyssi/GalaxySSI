# Desktop MQTT offline send investigation

## Observed failure

The running Desktop 1.1.48 returned `mqtt_not_connected` when sending a direct
peer message. Its local HTTP service and Signal sidecar were healthy, but the
MQTT bridge was disconnected for more than two hours. All 10 expected
subscriptions were inactive.

The backend repeatedly received `Server unavailable` from `broker.emqx.io:8883`.
An independent TLS MQTT v5 connection with a fresh diagnostic client ID received
`Server busy`. The diagnostic client did not subscribe or publish. These results
demonstrate a broker connection rejection on this network at the observation
time; they do not establish a global outage or a phone/pairing fault.

## Scoped fixes (Desktop 1.1.49)

- Record connection-attempt progress separately from total disconnected time.
  Give the normal Paho backoff and a connection attempt time to finish before
  forcing recovery. A genuinely stalled retry loop still receives watchdog
  recovery, with a cooldown and a fresh-progress recheck.
- Preserve a rejected CONNACK reason when the subsequent generic disconnect
  callback arrives. A successful connection clears the old error.
- Return expected peer-send failures as structured IPC results. The renderer
  shows a localized connection failure instead of an Electron invocation trace.
- Do not mark the message sent or discard its text/attachments on this failure.
  This change does not introduce an offline outbox or automatic message resend.

No pairing, broker, account, proxy, TLS, or phone configuration was changed.
The independent broker remains an external dependency: these fixes cannot make
a refusing server accept the connection. A successful real-phone delivery must
be verified after MQTT connectivity and subscriptions recover.

## Verification

Focused tests cover recent disconnects, repeated broker rejections, stalled
retry recovery and cooldown, recovery races, connection failure callbacks,
preserved/cleared failure reasons, offline send without a publish or database
write, structured/localized renderer errors, and composer restoration.

Results: 63 backend tests (plus 10 subtests) passed across lifecycle, transport
probe, subscription, blob peer delivery, and phone-tool routing suites.
`npm run check` passed all 34 Node tests and the Desktop structure check.
`git diff --check` passed.

The runtime has not been restarted in this investigation, to avoid discarding
the user's currently unsent message. No phone interface was operated.
