# Closed-Book Collaboration Calibration Pilot

Android v1.4.55 adds an **opt-in test harness**, not a new default research loop.
It compares the existing managed cloud execution runtime in two conditions:

| Arm | Draft | Review | Revision |
| --- | --- | --- | --- |
| Single | Analyst | Same analyst | Same analyst |
| Team | Analyst | Separate reviewer identity | Original analyst |

The task, requested model, assignments, dependency visibility, output-token cap,
temperature and three-request admission budget are the same in both arms. Each
trial gets a new group and dedicated execution store. No earlier conversation or
research archive is inserted into the experimental prompt. Member identity is
the treatment; a separate identity with the same model is **not** independent
training, independent knowledge, or evidence of general team superiority.

The three assignments are actual `AgentTeamExecutionRuntime` work, executed by
`ActionExecutorAgentTeamMemberWorker` and the app's cloud transport. They are not
mock responses or direct HTTP calls that bypass the application. This narrow
pilot does not test autonomous research, tools, persistent learning, innovation,
parallel exploration, or the full coevolution architecture.

## Frozen Input And Explicit Consent

Keep the manuscript, cases, answer keys, raw results and figures **outside Git**.
Push only the frozen task-input protocol to the authorized app's external-files
directory. The host must retain its pre-execution digest, treatment order and
independent scoring rubric. Answer keys and grading instructions do not belong
on the evaluated device. The parser rejects unknown protocol/slot fields,
unpaired cells, unequal paired inputs, duplicate IDs and excessive admissions.

The protocol has `format: galaxyssi.collaboration-pilot.v1`, `pilot_id`,
`target_id`, `model_id`, `text_profile`, `trial_timeout_ms`, and `slots`.
Each slot has `id`, `case_id`, `arm` (`single` or `team`) and `prompt`.
Every case has exactly one slot per arm. At most 32 slots are accepted; actual
authorization is separately supplied and may be much smaller. Each trial uses
three admissions, including failed requests and any transport fallback.

The `galaxyssi.trial-text-profile.v1` object specifies `max_output_tokens`,
`temperature`, `thinking_mode: disabled`, `external_tools: false`, and
`model_summarization: false`. The first intended provider is DeepSeek's
OpenAI-compatible endpoint. Explicit non-thinking mode makes the temperature
control meaningful under its [documented API](https://api-docs.deepseek.com/guides/thinking_mode/).
This is not a portable promise about other providers' inference settings.

The fixture requires all of these instrumentation arguments:

- `collaborationPairedPilot=true`
- `pilotDeviceModel=SM-S9480` (this pilot's specifically authorized S26U)
- `pilotInput=<safe-basename>.json`
- `pilotSha256=<digest of the exact input bytes>`
- `pilotMaxAdmissions=<explicitly authorized maximum>`

Run only `CollaborationPairedPilotDeviceTest#runPairedPilot` when authorized.
`#preflight` separately requires `collaborationPilotPreflight=true` and the same
device argument. It exports cloud target IDs and display names, never API keys.
Installing the APK or running the ordinary test suite cannot start the pilot.

## Accounting And Isolation

The optional profile disables external tools and model-based context summaries
before prompt preparation. It pins request controls and verifies their typed
values at admission, before network I/O. The recorded controls omit prompts,
tool definitions and arbitrary malformed string values. Final receipts cannot
rewrite the admitted controls. Ordinary requests without a profile are unchanged.

The admission policy pins the target and model, disables hidden HTTP retries
and redirects, and rejects unmetered adapters. Remote Codex is intentionally not
included until its internal model calls can be collected and bounded correctly.
Output/context envelopes are explicit; truncated dependency results fail the
trial instead of being silently treated as complete evidence. No model-based
grader runs on the phone. Provider usage remains distinct from billing cost;
unknown cost stays null. Equal admission caps are **not equal actual token cost**.

## Failure And Reporting

An atomic journal lists every assigned slot before the first model call. A
previously assigned pilot ID cannot run again, even after failure. A timeout,
unavailable target, invalid output or exhausted cap remains an outcome rather
than a discarded trial. Deadline admission closure does not terminate an HTTP
request by itself; the fixture also cancels the runtime and waits for managed
responses to stop. It exports receipts before removing dedicated test groups.
Unconfirmed cleanup retains state and prevents later slots from starting.

`execution_elapsed_ms` ends before cleanup; `cleanup_elapsed_ms` and the total
are separate. A process killed mid-test leaves the started slot and remaining
assigned slots in the journal; these must not be omitted from the denominator.
This initial fixture does not automatically resume a killed pilot or reissue
its model calls. Retained state needs explicit inspection/cleanup before another
pilot. The input digest and actual request receipts must accompany host scoring.

Local tests verify plan structure, equal opportunities, parameter pinning,
privacy, immutable receipts and no silent truncation. Compilation or synthetic
tests are not live-model validation. Two paired cases are only a feasibility
sample: no stable p95, significance claim or general collaboration advantage can
be inferred. A larger preregistered protocol and budget remain separate work.
