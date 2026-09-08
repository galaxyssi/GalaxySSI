# Received Agent Reply Versus Late Transport Failure

## Defect

The 1.1.3 ten-window live test received ten correct replies while backgrounded. A later MQTT retry-exhausted callback marked three requests terminal and wrote the message-not-delivered row. Foreground recovery then discarded their queued replies because the source IDs were terminal. Only seven correct final answers remained in the conversation transcripts.

An application reply and a transport acknowledgement are not equivalent signals. A missing transport acknowledgement cannot establish non-delivery once the application has already received an authenticated reply for that request.

## Change

- Inbox schema 4 stores an indexed SHA-256 delivery identity derived from source message ID and contact ID, in the same transaction as the reply.
- The proof survives removal of the encrypted reply body during normal acknowledgement. It adds no plaintext message content or credentials.
- A remote model's failure reply also proves request delivery. A local attachment-delivery failure observation does not.
- MQTT retry exhaustion, MessageService, Activity failure callbacks and the failure recorder check the proof before reporting non-delivery.
- Pending schema-3 replies can lazily backfill proof using the known turn's index and an exact source/contact comparison. No full-inbox decode is required.
- Real non-delivery still marks the request failed. A reply for another request/contact cannot suppress that failure.

Version: Android 1.1.4 (890). No conversation layout, background color, encryption or model capacity changes.

## Verification Plan

1. Run the complete connector inbox device suite plus the received-delivery regression suite on SM-T575.
2. Invoke an Activity's late delivery-failure callback after durable receipt and verify that it cannot create a terminal/failure row.
3. Repeat ten real Codex requests in independent windows, return Home, close the first window, and verify every reply and restored transcript.
4. Inspect stored answers independently after the live run. Keep the original failing 1.1.3 report intact.

Previously discarded reply bodies are not reconstructed or fabricated by this migration. The original stress artifacts remain available for diagnosis; fresh end-to-end requests validate the fix.

## Executed Results (2026-09-08)

- Installed Android 1.1.4 (890) on SM-T575 only, preserving application data.
- All 17 device tests passed: the full connector inbox suite and received-delivery regression suite. This includes durable proof after body acknowledgement, exact contact/request isolation, schema-3 pending-body backfill and late Activity callbacks.
- Submitted ten real Codex requests in ten independent windows, returned Home and closed the first window. All ten remote outcomes arrived while the App was backgrounded.
- Five requests produced all 80 correct arithmetic rows each. Four failed with `thread/start` timeout and one with `turn/start` timeout. Model task success was therefore 5/10, not 100%.
- The unchanged strict live test failed while waiting for run 1's expected answer marker to render, because that run received a model startup error. The overall ten-successful-task/UI restoration acceptance has NOT passed.
- A separate device inspection compared all ten actual received outcomes with stored conversation text: 10/10 retained, zero `delivery-failed:` rows. Its assertion passed. This is result retention, not model quality or ten-window render coverage.
- The running Desktop was not replaced during this experiment. The Desktop isolation changes in this branch were tested separately; this run does not validate their deployed behavior or resolve the startup timeouts.

Local artifacts (build directory, not committed): `received-delivery-device.log`, `received-delivery-live.log`, `received-delivery-live-report.json`, `received-outcome-retention-device.log`, `received-outcome-retention.json`.

## Remaining Work

Profile Desktop startup contention and event-reader blocking, deploy the Desktop changes, then repeat the strict ten-task acceptance. Keep provider failures distinct from transport failures. Validate simultaneous receipt/failure races and longer reconnect/restart runs before extending the concurrency claim.
