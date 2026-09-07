# S20U Recovery Discovery Coalescing Acceptance

## Candidate and Scope

- PR branch base: latest main `866e90bd4`, fetched again before submission.
- Android candidate: 1.0.37 / 881.
- Production-code commit: `09d6f02bd`; live wake-burst test: `2ae315580`.
- Local device integration: `afeb839b8`, on top of `efd8192a6`, retaining the
  previously installed background outcome fix and recovery-stage instrumentation
  from PRs #2845 and #2848. Those separate changes are not folded into this PR.
- S20U SM-G9880 only. The tablet and S26U were not operated.
- Running Desktop 1.0.32 remained in place; no backend restart or configuration
  change was needed. The separate high-resolution clock PR was not deployed.

The change coalesces automatic discovery during a current-generation body
transfer. It does not add a cooldown or change transport timeouts. Manual
inspection and explicit handoff recovery remain independent.

## Build and Regression Results

- PR branch: 60 targeted JVM tests passed, including 16 new registry tests.
- Device integration: Debug, instrumentation and Release builds passed;
  77 targeted JVM tests passed. Build duration was 14 min 41 sec.
- Both Debug and Release passed the 16 KB audit for all 72 AArch64 libraries.
- Repository checks, script syntax and whitespace checks passed.

The registry suite includes concurrent ownership, 200 completion/defer races,
generation replacement, all identity dimensions, database checks outside locks,
cancellation before coroutine entry, success eligibility and failure/reconnect
replay. These deterministic tests do not establish network latency percentiles.

## Live Cases

Commands:

```powershell
.\tools\dev\test-android-live-final-recovery.ps1 -Serial R5CN319CESA
.\tools\dev\test-android-live-final-recovery.ps1 -Serial R5CN319CESA -WakeBurst
```

Each case uses a fresh private test conversation and the existing paired Codex
contact. A real provider final reply is acknowledged at transport level but
deliberately withheld from the test inbox/UI. After a real process stop,
production readiness recovery fetches that same archived body. UI reconstruction
and a subsequent cold start verify exactly one matching assistant entry.

The second case waits for its authenticated body-transfer lease and then emits
20 production recovery-wake requests. It does not synthesize a reply, directly
fetch a body, or resubmit the model task.

| Observation | Normal restart | 20 wakes during body transfer |
| --- | ---: | ---: |
| Case source | 1788763329284 | 1788763388805 |
| Live phases passed | 4 / 4 | 4 / 4 |
| Phone task queries | 1 | 1 |
| Desktop task lookups | 1 | 1 |
| Phone page requests | 1 | 1 |
| Connection ready | 2,607 ms | 2,367 ms |
| Ready to persisted body | 6,819 ms | 6,443 ms |
| Total recovery | 9,426 ms | 8,810 ms |
| Task query round trip | 4,303.14 ms | 3,758.68 ms |
| Body recovery span | 2,193.33 ms | 2,407.41 ms |
| Page round trip | 2,023.94 ms | 2,200.16 ms |
| Checkpoint write | 18.89 ms | 37.58 ms |
| Inbox bus publish call | 47.45 ms | 56.57 ms |
| First UI visible | 1,783 ms | 1,814 ms |
| UI plus recreation | 2,215 ms | 2,218 ms |
| Subsequent cold visible | 1,180 ms | 1,135 ms |

Both cases verified exact content, its digest, execution generation, status
sequence, one persisted reply and one visible reply. The timing report asserted
one completed query and one completed page span per case, and one corresponding
Desktop lookup. Child spans overlap the total/body timings; they must not be
added together. All durations stay within one device/process clock domain.

Evidence is retained in the integration worktree under
`build/live-final-1788763329284` and `build/live-final-1788763388805`, including
four phase logs, `metrics.log`, `stage-timings.json` and the latter case's
`visible-release.png`. The collector from PR #2849 reads bounded diagnostic
journals, not message content. Missing/rotated points cannot be treated as zero.

Earlier 1.0.36 cases observed two discovery attempts while one body transfer
was in progress. This candidate removes that redundant lookup in both new
cases, including the deliberate wake burst. It does **not** establish faster
end-to-end recovery: network timing varies, these are only two observations,
and the 5-second recovery target remains unmet. This is not P95/P99 acceptance
or completion of the broader execution/recovery/performance goal.

## Device Restoration

Non-debug Release 1.0.37 / 881 was restored with an in-place update. Package flags
do not include DEBUGGABLE. First installation time remains
2026-09-07 00:28:13; the update completed at 14:44:29 local time. Only the test
package was removed. Main App data, identity, contacts, models and pairings were
not cleared. The release screenshot shows the single recovered answer.

Artifact SHA-256:

| Artifact | SHA-256 |
| --- | --- |
| Debug | `860d19be90d8d9824a1dd421c46783c2d033a289cd6f990e4a6c466c045c53ed` |
| Release | `49081f21ba4f61e4cb6aeec4dd5bb9454a6eed6bef9727077918a882bf9772d4` |
| Instrumentation | `7da7f4293b5337c14588e677dc1b3068af722a4ba9af9e43314267f10d875e90` |

The release uses the existing development signing identity for in-place device
validation; this record is not a production-signing attestation.
