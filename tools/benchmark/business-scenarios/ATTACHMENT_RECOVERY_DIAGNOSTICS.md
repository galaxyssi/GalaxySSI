# Task-scoped attachment recovery diagnostics

## Real failure retained

The frozen catalog remains 100 cases and 1,100 turns. This investigation does
not convert a terminal driver observation into a successful business result.
The eleven-turn warehouse XLSX evidence is tracked separately in PR #3287.

Observed on Active3 (SM-T575), Android 1.3.24 (1067), with the still-running
Desktop 1.3.23 process:

- A006 turn 10 requested the current native workbook, PDF and previews.
- The task ended with `Phone attachment recovery timed out`; no final artifacts
  passed the delivery checks. The original report is unchanged.
- The task identity saved on the phone matches the remote task, conversation,
  turn and source message. No weakening of identity validation is warranted.
- A read-only inspection found a staged phone transfer for this exact recovery
  request, created at Unix millisecond `1790691752744`. Its input was the
  previously received 219,158-byte `ART-006-v10.pdf`, with artifact hash prefix
  `039a185e4b06afc5b92f2916`. This proves the phone received and prepared at least
  this requested attachment. It does not prove Desktop received the file.
- Phone logs at 22:22:32 show encrypted publications after staging. Desktop logs
  around the failed turn contain repeated publish failures and inbound OSError
  reports, but lack sufficient correlation to attribute a specific inbound
  failure to this attachment. No broker-specific root cause is claimed.
- The later read-only phone outbox snapshot is empty, while the transfer staging
  remains. An empty outbox does not prove a verified attachment receipt.

The fault is narrowed to the response/transfer/receipt path after phone
preparation, not model generation or failure to receive the original request.
The phone process was absent after instrumentation ended. Gaps between separate
instrumentation runs must not be counted as continuous background uptime.

## Changes in Desktop 1.3.28

Recovery phase logs correlate a hashed request and hashed task with only counts,
elapsed time and a fixed phase. No route, credential, filename, attachment ID,
question or model output is logged.

| Observation | What it proves |
| --- | --- |
| `request_created` | A scoped request exists locally |
| `transport_accepted` | The transport accepted it; not phone confirmation |
| `phone_response` | A matching, validated recovery response arrived |
| `file_verified` | One matching stored-file receipt arrived |
| `completed` | All requested file receipts passed matching |
| `timed_out` / `awaiting_phone_response` | No matching phone response or receipt was observed by this broker |
| `timed_out` / `awaiting_files` | A response or partial receipt arrived, but verification is incomplete |

The existing 120-second deadline is unchanged. New timeout details do not claim
the phone is offline: the real case demonstrates that a phone can have prepared
the transfer even when Desktop has no matching recovery response.

Invalid response statuses and contradictory available/missing lists are now
rejected before mutating pending state. Previously an unknown status carrying
a missing ID could terminate a pending request. Exact route, conversation,
task, turn, contact, source-message and request matching remain mandatory.

A receipt arriving at the timeout boundary is checked under the broker lock
before reporting a timeout. Repeated unchanged responses and duplicate file
receipts do not produce repeated progress logs.

## Verification and remaining work

55 isolated backend tests pass across recovery phases, request broker,
conversation artifact recovery, input transfers, durable MQTT publication and
task recovery. Tests include unknown/contradictory responses, cross-scope
responses and receipts, partial receipt counts, stored-status-without-file,
timeout-boundary completion, and content-free diagnostics.

32 host benchmark tests and 61 Desktop JavaScript tests also pass. The full
`npm run check` command still fails at the pre-existing packaging source-string
assertion: `check.js` expects only `web_source_sites.tsv`, while `package-win.js`
also includes `research_contract`. Both files are unchanged from base main
`dbd03a80e`; this unrelated check was not relaxed or counted as passing.

This change fixes receipt validation and improves failure attribution. It is
**not** proof that the real PDF retransmission failure is fixed. The existing
Desktop process has not loaded these changes; updated-runtime MQTT acceptance
and the full 100-case campaign remain incomplete. S26U installation is also
pending its ADB connection; Active3 was not installed as a substitute.
