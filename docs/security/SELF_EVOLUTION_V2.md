# Self-Evolution V2 Security

## Threat model

An Agent can make a mistake or follow prompt injection embedded in repository or research data.
An external repository can be compromised, archived, relicensed, or contain malicious install
scripts. A candidate App or backend can crash, damage data, leak credentials, or lose connectivity.
The Desktop GitHub credential and the evolution controller itself are high-value targets.

## Required controls

### External content is data

The technology radar reads repository metadata through the Desktop GitHub CLI. Discovery does not
clone, install, import, or execute discovered code. A radar item can create only a proposal.

### Scoped writes

Every task declares source paths. A change outside the declared paths fails the attempt and removes
its disposable worktree. Self-evolution cannot modify:

- `.git`
- `.github/workflows`
- `.openai`
- `config/evolution-policy.json`
- `config/evolution-gates.json`
- `apps/desktop/core/galaxyssi-link/backend/evolution_v2/gate_cli.py`
- `apps/desktop/core/galaxyssi-link/backend/evolution_v2/gates.py`
- `apps/desktop/core/galaxyssi-link/backend/evolution_v2/policy.py`
- `apps/desktop/core/galaxyssi-link/backend/evolution_v2/review.py`
- `node_modules`
- `dist`
- `build`
- `runtime-data`

Workflow changes require an ordinary human-reviewed pull request so a candidate cannot weaken its
own gates or exfiltrate CI secrets.

### Production isolation

- Source edits happen in a disposable Git worktree outside the active checkout.
- Worktree storage and the active checkout may not overlap in either direction.
- Every candidate path is bound to its task ID, attempt number, generated branch, source commit, and
  repository common directory before an Agent or quality gate can use it.
- The active checkout is fingerprinted before and after implementation. A detected change blocks
  the task and leaves user files untouched for inspection instead of attempting an unsafe reset.
- Desktop candidate smoke tests use a temporary state directory and random loopback port.
- Desktop candidates must survive two isolated start/health/stop cycles against the same ephemeral
  state. A failed reload terminates the candidate and leaves the stable Desktop process untouched.
- The Android device gate snapshots the stable package before installing a candidate and restores
  the stable package in a final cleanup path. Stable APK and private-data archives are hashed before
  candidate installation and verified again before restoration.
- A failed attempt removes its candidate branch and worktree, prunes stale Git metadata, and
  verifies both identities are absent. Incomplete rollback blocks the task; it never performs a
  destructive reset of the active checkout.
- Cleanup refuses missing, external, overlapping, cross-task, or malformed paths before invoking
  Git or filesystem deletion.

### Approval binding

The approval hash binds protocol, task ID, base commit, candidate commit, scope, risk, and every
quality gate status and exit code. Any candidate or gate change invalidates an older approval.
Automatic merge is disabled.

### Credential boundary

Repository write credentials remain in the Desktop user's authenticated `gh` CLI:

- Android stores no repository write token.
- Tokens are not written to evolution JSON state or Agent prompts.
- Logs redact credential-shaped keys, bearer tokens, GitHub tokens, and private-key markers.
- Git commands set `GIT_TERMINAL_PROMPT=0`.
- The V2 HTTP API rejects non-loopback clients.

### Independent evidence

Static review runs after candidate commit creation and before approval. Policy can require an
independent Agent review for higher risk changes. Provenance records source and candidate commits,
changed files, gates, and review evidence. Audit entries include the previous record hash and their
own hash so offline tampering is detectable.

The local hash chain is tamper-evident, not remotely non-repudiable. Higher assurance deployments
should anchor the latest hash in a separate trusted system.

## Android restore gate

The device install/restore gate is mandatory for Android and shared-core self-evolution candidates
and must use a dedicated test device. It captures a PNG screenshot and logcat evidence, hashes the
APK and every evidence artifact, restores the stable App unconditionally, and binds the evidence
manifest to candidate approval. Missing, changed, or unmanaged evidence blocks publication.
Production-signed applications may not permit private-data backup through `run-as`; split APKs,
signature changes, downgrade restrictions, and OEM installers can also block restoration. Any
restore failure is a hard failure and requires manual recovery. Never use a primary phone as the
first restore-gate target.

## Deliberately unsupported automation

V2 does not automatically merge pull requests, publish production installers, edit workflows,
install radar discoveries, bypass signing or TLS, convert untrusted README text into a Skill, or
run critical production remote-control changes without review.
