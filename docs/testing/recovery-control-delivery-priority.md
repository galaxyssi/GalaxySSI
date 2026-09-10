# Recovery control delivery under backlog

## Evidence

The SM-T575 normal Agent Loop acceptance task
`live-completion-contract-1788967495742` completed correctly in 218,017 ms.
Desktop monotonic timing, grouped by clock and operation, showed:

| Stage | Initial plan | Final review |
| --- | ---: | ---: |
| Result outbound queue | 608.45 ms | 390.26 ms |
| Queue to peer receipt | 50,449.72 ms | 25,063.28 ms |
| Agent execution | 44,803.40 ms | 34,472.79 ms |

These peer-receipt intervals include delivery and the receipt's return trip;
they are not one-way network latency. One initial broker ACK took 16,596.39 ms;
a later attempt took 290.56 ms. Legacy wall-clock trace stages cross device
clocks and even show a negative interval, so they are not used for attribution.

The same task traces contain additional queued control records after task
completion. That observation prompted the priority audit; it does not prove
which payload type every historical ciphertext contains.

## Confirmed scheduling defect

`agent_task_recovery_result`, `agent_task_result_page`, and
`agent_task_result_receipt_confirmed` previously had ordinary priority 50.
At a saturated ordinary window none could be selected, including the response
needed to retire a phone's durable result receipt. They now use dependency
priority 95, below final results (100), through the existing bounded reserve.

No inflight limits are increased. Existing ciphertexts, ACK tracking, encryption,
retries, and identity validation are unchanged. Old queued ciphertexts are not
deleted or relabeled. This change affects newly queued recovery controls.

## Validation and limits

- Before the change: both new regression tests failed across all three control
  types (six failing subcases).
- After the change: 111 backend tests passed, including saturated-lane selection,
  one-slot reserve bounds, existing-message retention, broker ownership, result
  receipt persistence, result outbox, recovery queries, and timing.
- Repository guard passed.
- Desktop version is 1.1.38; Android remains 1.1.36.

The saturated scheduler tests use an injected MQTT publisher and queue records.
They do not claim real public-broker chaos acceptance or a measured reduction of
the complete 218-second task. That broader latency/network matrix remains open.
