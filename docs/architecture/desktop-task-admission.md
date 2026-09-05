# Desktop Task Admission

Explicit Agent selection validates the current visible Agent catalogue only.
It does not build a connector status snapshot or probe other providers. Automatic
selection still delegates to the Desktop coordinator. MCP selection still
requires the requested connection to exist. Unknown and hidden IDs remain 404s.
Execution continues to determine actual availability and publish failures through
the normal task lifecycle; admission is not an assertion that a provider is online.

The catalogue is read for each selection, so adding or removing a custom Agent
does not require a cache expiry, process restart, or a new conversation.

## Regression Coverage

`test_desktop_task_admission.py` prohibits diagnostic/runtime-health probes at the
admission boundary. It covers six explicit providers, all four automatic aliases,
unknown/hidden IDs, custom catalogue updates, requested MCP connection lookup,
asynchronous execution failure, and the existing loopback access boundary.
The controlled failure test waits for the actual terminal callback, rather than
assuming callback delivery is synchronous with persisted task status.

## Reproducible Real-Provider Probe

Use the existing Desktop Python runtime with backend dependencies installed:

```powershell
python apps/desktop/scripts/probe-task-admission.py --agent codex --selection-rounds 3
python apps/desktop/scripts/probe-task-admission.py --agent codex --selection-rounds 3 --live
```

`--live` explicitly invokes the real provider with three Chinese test prompts:
remember a random code, recall it in the same conversation, and answer in an
independent conversation. Each run creates new temporary GalaxySSI state,
configuration, workspaces and task databases. It does not start MQTT, read the
production chat database, reset identities, or change the running Desktop.
Codex uses its existing login through `CODEX_HOME`. Other CLI logins that depend
on HOME may require explicit provider-specific environment configuration.

The output report contains timings, status, response length and exact expected
substring checks, not prompt/response content or credentials. Test task records
remain in the reported temporary directory for deliberate investigation. The
probe timeout belongs to this test only, not the production Agent execution loop.
`selection.prof` provides a local cProfile of catalogue selection. Selection
measurements include profiler overhead; live task measurements do not.

`--backend` can point at another checkout's backend for before/after comparison.
Only configured real providers should be used; this probe does not supply a mock
LLM or install missing providers.

## Validation: 2026-09-05

Base: main `3f3b6a651`. Desktop source version: 1.0.6. Android unchanged.
Both runs used the same Windows host and unchanged default Codex configuration.

| Request | Before: API acceptance | After: API acceptance | After: complete response |
| --- | ---: | ---: | ---: |
| Remember code | approximately 5,125 ms | 93.071 ms | 20,582.237 ms |
| Same-conversation recall | approximately 4,797 ms | 62.713 ms | 15,047.396 ms |
| Independent conversation | approximately 4,094 ms | 65.488 ms | 14,985.384 ms |

All expected responses passed before and after. Before measurements used the
coarser Windows monotonic clock; final measurements use `perf_counter` (reported
clock resolution 100 ns). These are individual real-provider samples, not P95/P99
SLO acceptance or phone-to-model round trips.

Three profiled old selections spent 18.21 s in `connector_diagnostics`: unrelated
Ollama availability requests consumed approximately 6.05 s, and repeated command
discovery issued over 80,000 file existence probes. Afterward, ten profiled
catalogue-only selections took 0.288-0.638 ms each. No diagnostic result or
availability failure is cached or suppressed by this change.

- New regression tests: old code failed 10 and passed 6; fixed code passed all 16.
- Combined admission, Desktop UI tasks, task streaming and run-control tests:
  36 passed.
- Desktop renderer/source checks: 16 passed and structure checks passed.
- Repository checks: passed.

The live Desktop CLI path still did not report streamed output, and complete
responses remain provider-dependent. Shared warm execution and truthful first
output/verification tracing remain separate work. This patch does not claim to
achieve the overall 3 s first-output or 10 s complete-response targets.
