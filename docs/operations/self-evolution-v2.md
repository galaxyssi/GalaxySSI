# Self-Evolution V2 Operations

## First-time setup

Install Git, GitHub CLI, Python, Node.js, JDK 17, and the Android SDK on Desktop. Authenticate the
Desktop account:

```powershell
gh auth login
gh auth status --hostname github.com
```

Point the runtime at a real GalaxySSI checkout:

```powershell
$env:GALAXYSSI_SOURCE_ROOT = "C:\src\GalaxySSI"
python apps\desktop\scripts\evolution-preflight.py --repo-root $env:GALAXYSSI_SOURCE_ROOT
```

If ignored build runtimes live in another explicitly trusted checkout, point dependency discovery
at that checkout. Desktop mounts only the Electron, Python, and embedded Android gate directories,
then detaches them before staging the candidate:

```powershell
$env:GALAXYSSI_EVOLUTION_DEPENDENCY_ROOT = "C:\trusted\GalaxySSI"
```

The equivalent POSIX setup is:

```bash
export GALAXYSSI_SOURCE_ROOT=/src/GalaxySSI
python3 apps/desktop/scripts/evolution-preflight.py --repo-root "$GALAXYSSI_SOURCE_ROOT"
```

Start with a low-risk documentation or focused test candidate. Enable the dedicated Android device
gate only after the source-only path is stable. Enable independent Agent review and high-risk tasks
last.

## Bootstrap and CLI

Run the repository bootstrap check:

```powershell
apps\desktop\scripts\evolution-bootstrap.ps1 -RepoRoot C:\src\GalaxySSI
```

```bash
apps/desktop/scripts/evolution-bootstrap.sh /src/GalaxySSI
```

Inspect the control plane without placing GitHub credentials in the Android App:

```powershell
python apps\desktop\scripts\evolution-cli.py preflight
python apps\desktop\scripts\evolution-cli.py health
python apps\desktop\scripts\evolution-cli.py audit
```

## Automatic schedule

Open **Settings > Self-evolution > Schedule** to:

- pause or resume automatic evolution;
- choose 1 to 96 runs per day;
- run serially, waiting for the previous task to finish; or
- run in parallel with a limit of two to four isolated tasks.

Missed intervals are coalesced after Desktop was offline. They do not create a burst backlog.
Pausing prevents new scheduled runs without deleting an isolated task already in progress.
Successful candidates create labeled pull requests, but GalaxySSI never merges them automatically.

## Failure handling

`source_root_missing`
: Set `GALAXYSSI_SOURCE_ROOT` to a Git checkout containing `.git` and `apps`.

`source_fetch_failed`
: Restore access to `origin/main` and retry. No candidate worktree is created before the fetch
  succeeds.

`agent_unavailable`
: Configure a local/custom CLI coding Agent and verify its executable and runtime health.

`implementation_channel_failed`
: The failed Agent is avoided on the next attempt when another healthy implementer is available.
  A sole healthy Agent remains retryable.

`github_auth_missing`
: Run `gh auth login` on Desktop. Do not copy a token into Android or evolution state.

`scope_violation`
: Keep the task narrow. Add only the source path required by the acceptance criteria.

`quality_gate_failed`
: Inspect `%APPDATA%\GalaxySSI\evolution\logs\<task-id>`. A retry receives the bounded failure
  summary and starts in a new worktree.

`candidate_review_failed`
: Treat review failure as a failed attempt. Do not bypass it or reuse the rejected worktree.

`worktree_cleanup_failed`
: Stop the task and inspect Git worktree and local branch state. GalaxySSI does not report rollback
  until both the managed worktree registration and generated candidate branch are absent. Never
  delete or reset the active checkout to resolve this condition.

Android restore failure
: Stop device testing, find the snapshot path in task metadata, manually reinstall the stable APK
  or split APK set, verify identity and data, and only then re-enable the gate.

## Retention

Keep failed logs for 30 to 90 days, dedicated-device snapshots for 7 to 30 days after verified
restoration, and provenance plus audit records long term. Do not delete snapshots whose restore
status is unknown. Rollback removes the candidate worktree and branch, prunes stale Git worktree
metadata, then verifies that neither candidate identity remains.

The integration tool may create `/.galaxyssi-evolution-backup/` and
`/evolution-v2-integration-report.json`. Both are local integration evidence and are ignored by
Git; they are not runtime backups.
