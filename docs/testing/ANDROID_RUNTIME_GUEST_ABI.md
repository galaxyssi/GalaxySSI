# Android Runtime Guest ABI

The product name is GalaxySSI. Published guest API v1 identifiers are a separate
binary contract with signed runtime images and must not follow branding changes.

## Observed Failure

On S20U, Android 1.4.105 could not execute the saved-tool native acceptance suite.
The linux-base 1.3.9 image is both installed on the phone and bundled in the APK.
Its SHA-256 is
`19b1338a36239c195bbff914187b593e4969a34cccbb721035771472a5d04ac3`.
It reads `opt/com.signalasi/runtime-session` from QEMU firmware configuration.
The renamed host supplied `opt/com.galaxyssi/runtime-session` instead, despite
retaining guest API version 1. The guest reported `FileNotFoundError`; retries
could not repair this deterministic mismatch.

The same rename also changed the serial channel, workspace mount tag, persistent
mount path and staged script directory. Correcting only the first missing file
would leave subsequent startup/execution failures.

## Restored Contract

| Contract | Guest API v1 value |
| --- | --- |
| Serial channel | `org.signalasi.runtime` |
| Session firmware configuration | `opt/com.signalasi/runtime-session` |
| Runtime firmware configuration | `opt/com.signalasi/runtime-config` |
| Workspace mount tag | `signalasi_workspaces` |
| Guest persistent mount | `/var/lib/signalasi` |
| Staged executable directory | `.signalasi-runtime` |
| Language pack descriptor | `signalasi-pack.json` |

Host constants, current guest source and future pack generation use these same
published identifiers. QEMU-internal IDs, Android app paths, product UI, tools and
device names remain GalaxySSI. Existing Android persistent disks are not renamed,
deleted or reformatted by this change. The ordinary guest filesystem checks still
apply when the runtime starts.

Both the published and accidentally rebranded control directories stay excluded
from project synchronization, checkpoints and Git output. This avoids exposing
temporary drivers while preserving actual project files.

## Validation Scope

The Python guest suite pins the released ABI and checks the Android constants.
Kotlin launch-plan tests verify actual QEMU arguments and generated guest config;
workspace tests verify script placement and control-file exclusion. Pack-builder
tests verify the descriptor emitted into new images. A real device suite must
also boot the unchanged signed image and execute Python; source-only checks cannot
establish that a downloaded binary is compatible.

`availability=AVAILABLE` with `ready=false` means the installed runtime is eligible
for a startup attempt, not that a health handshake or program execution succeeded.
Only original native test reports count as execution evidence. This infrastructure
repair is developer intervention, not evidence of autonomous learning or innovation.

## Verified On S20U, 2026-10-08

- Android 1.4.106 (1191) was installed as an update. Installed and built APK
  SHA-256: `690a941253bbe2e62a92ab3033dae501a284aa3da56660c02708339ee6173324`.
- The signed linux-base image hash was unchanged before and after testing. No
  runtime was downloaded or replaced; no app data reset was performed.
- Android JVM: 66 passed. Python guest: 43 passed. Pack-builder/default bundle:
  17 passed, three skipped because Windows symbolic-link policy prevents those
  cases. Repository guards and embedded-runtime verification passed.
- S20U instrumentation: 18 passed in 92.615 seconds. The native suite executed
  both developer-authored Python candidates using the production saved-tool
  wrapper: broken candidate `native_status=failed, passed=false`; repaired
  candidate `native_status=succeeded, passed=true`. Original ledger reports,
  two-case coverage and reopened execution receipts were checked.
- The runtime subsequently reported `QEMU_TCG`, `ready=true`.

The remaining 17 device cases used synthetic observations for persistence,
scoping and recovery. No real model was called, and the running Desktop was not
restarted. Full live remote Codex/MQTT execution remains a separate acceptance
requirement. These results do not establish autonomous tool creation, multi-agent
learning gains, unseen-task transfer or scientific novelty.
