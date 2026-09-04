# Self-Evolution V2 Validation

Run commands from the repository root unless a command changes directory explicitly.

## Required source gates

```powershell
node tools/dev/check-no-chinese-outside-i18n.js
python -m compileall apps\desktop\core\galaxyssi-link\backend\evolution_v2
python -m unittest discover -s apps\desktop\core\galaxyssi-link\backend\test_evolution_v2 -p "test_*.py" -v
python -m unittest discover -s apps\desktop\core\galaxyssi-link\backend -p "test_*.py"
node apps\desktop\scripts\check.js
```

## Desktop gates

```powershell
Set-Location apps\desktop
node scripts\package-win.js
node scripts\smoke-ui.js
node scripts\smoke-packaged.js
```

The packaged backend must contain `evolution_v2/__init__.py`, `api.py`, and `manager.py`; source-only
success is not sufficient.

## Android gates

```powershell
Set-Location apps\android
.\gradlew.bat :app:testDebugUnitTest :app:assembleDebug `
  -Pgalaxyssi.requireEmbeddedRuntime=false `
  --no-daemon
```

Use this source-only command when the ignored local QEMU/runtime bundle is absent. Release packaging
must omit the override and prove that the complete signed runtime bundle is embedded.

The install/launch/evidence/restore gate is mandatory for every self-evolution candidate that
changes Android or shared core code. If no dedicated device is online, the candidate remains
blocked and no pull request can be published. The gate can also be invoked directly:

```powershell
python ..\desktop\core\galaxyssi-link\backend\evolution_v2\gate_cli.py android-device `
  --candidate app\build\outputs\apk\debug\app-debug.apk `
  --snapshot-root "$env:TEMP\galaxyssi-evolution-android" `
  --package com.galaxyssi.chat
```

Run it only on a dedicated device. Acceptance requires candidate build and unit tests first, then
candidate install, launch, PNG screenshot, logcat capture, cryptographic evidence manifest, and
unconditional restoration of the previously installed stable APK and supported data snapshot.
The approval hash binds the gate log and device manifest hashes.

## API and security acceptance

- Non-loopback V2 API requests return `403 loopback_required`.
- Technology radar tests prove trusted filtering and that discovery never clones or executes code.
- Protected paths are denied and high/critical paths escalate risk.
- A retry uses a fresh worktree.
- Worktree storage overlap is rejected in both directions.
- Candidate identity is verified against its managed path, branch, source commit, and Git common
  directory before execution.
- Tampered cleanup metadata cannot delete the active checkout, an external directory, or another
  task's worktree.
- An implementation Agent change to the active checkout blocks the candidate without resetting
  user files.
- Desktop runtime validation performs two isolated reload cycles, reuses only the candidate's
  ephemeral state, and proves every candidate process stops before the gate passes.
- Candidate changes after review invalidate approval.
- Audit tampering is detected and credential-shaped values are redacted.
- Auto-publish and auto-merge remain disabled.
- GitHub write operations use only the Desktop `gh` session.

## Pull-request workflow

`.github/workflows/evolution-candidate.yml` uses read-only permissions and
`persist-credentials: false`. It runs V2 tests, repository checks, Desktop packaging, and Android
source compilation. The existing Windows package workflow performs packaged smoke validation on
the same pull request. Neither workflow auto-merges or publishes a production release.
