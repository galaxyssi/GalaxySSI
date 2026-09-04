# Desktop Agent Output Delta

GalaxySSI Desktop now exposes only user-visible Agent output as cumulative,
sequenced snapshots. Private reasoning events remain excluded from the wire
protocol.

## Contract

- `status_seq` orders task state snapshots.
- `partial_result.sequence` orders cumulative visible output.
- `partial_result.mode` is `cumulative`, so replay replaces rather than appends.
- The latest partial snapshot and first-output timestamp are stored with the
  existing Agent task record.
- MQTT keeps the latest snapshot per task and coalesces running output for
  150 ms. Approval and other non-running states bypass the delay.
- Terminal results remain reliable and compatible with clients that ignore the
  new fields.
- Persistent JSONL Agents negotiate visible-delta, progress, and cancellation
  capabilities; old Agents may return only a final response.

The rollout gate is `agent.output_delta_v1`, controlled by
`GALAXYSSI_FEATURE_AGENT_OUTPUT_DELTA_V1`. It is enabled by default and can be
disabled without changing the existing final-result path.
