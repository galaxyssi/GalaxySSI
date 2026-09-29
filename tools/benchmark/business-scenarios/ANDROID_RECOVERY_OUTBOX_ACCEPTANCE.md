# Android attachment recovery outbox acceptance

## Refined A006 evidence

The original A006 final-delivery failure remains unchanged. Additional read-only
inspection of its Desktop task workspace confirms two transfer manifests with
the same recovery request:

| Prior output | Size | Desktop state |
| --- | ---: | --- |
| `ART-006-v09.xlsx` | 12,489 bytes | Complete, restored input file exists |
| `ART-006-v10.pdf` | 219,158 bytes | Manifest exists, complete=false, no completed PDF |

The phone retains the matching PDF staging. Therefore this was a partial file
recovery, not a failure to receive the original request. The two retrying
OSError records in Desktop's durable inbox predate this task; those records
alone do not identify the PDF failure. No broker-specific root cause is proven.

## Confirmed code defect

Android handled `input_attachment_request` and `input_attachment_receipt`
controls in the durable background inbox. However, the recovery handler ignored
`MqttPublishResult.FAILED` for its response, manifest and chunks. The missing-chunk
receipt handler also ignored failed chunk publication. Both handlers could then
return normally, allowing the inbox to mark the incoming control complete even
though no durable outgoing record was committed.

The fix checks durable acceptance before completing either handler. Publications
use queue-only dispatch: an offline but durably queued publication is valid;
rejection due to route, encryption, capacity or persistence does not retire the
incoming control. The existing inbox failure path releases dispatch ownership
and permits replay, rather than adding a second retry scheduler or new task.

The recovery handler also reuses `AgentAttachmentPublishOrder.initialSteps`:
small files retain fast eager delivery with the manifest explicitly declaring
that mode; larger files use manifests followed by the receiver's bounded missing
chunk windows. Previously recovery eagerly emitted every chunk regardless of
file size, while its manifest advertised non-eager mode and could trigger
redundant receiver requests. A planner-only fixture of ten 16-MiB files begins
with ten manifests, not 640 queued chunks; this does not claim a real 160-MiB
recovery passed the storage quotas or network. This uses the existing transfer protocol,
not a new wire format or a larger queue limit. Blob relay ownership is unchanged.

Exact task/conversation/turn/peer matching, transfer IDs and chunk hashes are
unchanged. This is not permission to resend an unrelated model task or external
side effect. A successful outbox commit still does not prove file delivery.

## Acceptance boundary

This repairs an independently reproducible loss-of-retry path. The recorded PDF
failure has not yet been proven to originate from an enqueue rejection, and its
failed result is not relabeled. Updated-runtime MQTT verification and the full
100-case / 1,100-turn campaign remain outstanding.

## Verified on 2026-09-29

- Android 1.3.25 (1068) debug APK and instrumentation APK built successfully.
- 23 targeted JVM tests passed: control inbox/publication, recovery protocol,
  publish ordering, transfer protocol and peer transfer progress.
- Active3 (SM-T575) was upgraded in place, retaining user data. Package manager
  reports version 1.3.25 / 1068; the app started with no new crash observed.
- 24 targeted device tests passed in 4.097 seconds: two new isolated durable
  recovery tests, 21 atomic inbox tests and one local attachment provider test.
- The new tests inject publication rejection and confirm that the actual
  encrypted inbox remains pending across repository recreation, then completes
  only after accepted publication. A peer's accepted control cannot complete a
  different peer's rejected control with the same message ID. They do not
  simulate a successful MQTT transfer or a process-death recovery.
- 32 business-catalog/report host tests passed. The prior 25 isolated Desktop
  protocol tests passed; this branch does not change Desktop production code.

The running Desktop still reports the older 1.3.23 process. New live business
observations must record that runtime rather than attribute un-deployed Desktop
fixes to it. The original A006 failed final delivery remains failed evidence.
