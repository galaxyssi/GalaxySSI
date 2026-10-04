# Evidence-Bound Executable Tools

Increment 8 turns a missing-tool proposal into saved executable code, a preregistered test plan,
actual execution, independent release review and exact-version reuse in later authorized group tasks.
It does not create a new execution service, poller, native capability or global Skill installation.

## Records And Execution

1. Publish immutable `executable_tool`: Python source defining `run(parameters)`, the existing Skill
   input schema, purpose, applicability, exclusions, environment, dependencies and side effects.
2. Publish immutable `tool_test_plan` referencing that exact revision/hash. Register target,
   regression and relevant edge cases with inputs, explicit expected JSON outputs and oracle rationale.
   Cases are agent-selected; there is no research-stage/retry cap. Existing payload/resource limits remain.
3. Call the existing `galaxyssi.runtime.execute` with `collaboration_tool.mode=test` and the plan ref.
   The host loads scoped records, generates the harness, preserves runtime gates and compares actual
   outputs itself. Expected answers are not passed to the generated function. Fresh namespaces avoid
   accidental Python global-state leakage between cases; they are NOT OS security boundaries.
4. An independent member reads the original tool evidence and reviews source, oracle and limitations.
   `tool_release` requires the exact complete passing host receipt. Generic command text saying
   "tests passed", wrong versions, isolated branches and unresolved blockers cannot create a release.
5. Later authorized work calls the same runtime with `mode=run`, an exact release ref and parameters.
   Source, schema, test plan and release are loaded from immutable records. Caller code/argument overrides
   are rejected. The harness reports Python version/implementation/machine; changed runtime identity
   makes reuse fail explicitly and requires retesting. This identity is diagnostic, not hardware attestation.

The native dispatch retains member/group/run/turn identity. Sources and reports remain in the existing
encrypted workspace/evidence ledger and are browsable with evolution/workspace/evidence recall. A new
task in the same group can reuse them, but current blind branches and other groups remain isolated.
Deleted groups/revoked membership lose access. Source correction means a new linked candidate and tests,
not silently replacing code behind a released reference.

## Failure And Authority

- Failed cases retain expected/actual values and exceptions; incomplete/duplicate/nonzero/invalid output
  never passes. The existing problem-resolution loop can inspect evidence, repair code or the test oracle,
  ask a peer, or choose another approach. A lost receipt is not a reason to repeat a side effect.
- Existing Linux availability, explicit network choices, cancellation, deadlines and tool execution gates
  remain authoritative. Ordinary calls take a no-workspace-I/O fast path. No idle model calls are added.
- The Linux guest remains the existing persistent environment. Agent-authored Python is NOT made safe
  against malicious code by these checks. Review side effects before authorized execution; passing sample
  cases does not certify security, general correctness, measured usefulness or scientific validity.
- A release never grants permissions, installs/enables a global Skill, changes model routes or marks the
  original goal complete. The caller still chooses authorized work in the existing task DAG.
- First implementation supports Python JSON-in/JSON-out functions on the existing phone runtime.
  Cloud members with exact native dispatch bindings execute the tests. Desktop members can author code,
  retrieve evidence and review a release, delegating execution to a phone-runtime-capable member in the
  existing DAG. Direct Desktop-only shell execution cannot impersonate the native host receipt, and
  no new Desktop execution bridge is claimed. Other language/package deployment adapters are not claimed.
  No runtime or model download is automatic.

## Verification Scope

Local tests execute tiny Python fixtures for build/test/release/reopen/reuse, plus wrong implementations
and exceptions. Device fixtures exercise encrypted persistence and exact native dispatch bindings using
clearly synthetic receipts, without Linux/model execution or original research. This demonstrates the
mechanism, not that a real model autonomously invents useful, novel or safe tools.

## Design References

- [Voyager](https://arxiv.org/abs/2305.16291): executable skill libraries and environment-feedback iteration.
- [Code execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp): reusable code
  and progressive loading of tools, without bloating every prompt with full implementations.
- [Writing tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents): explicit
  interfaces, actionable errors and evaluation against real workflows.

These motivate design choices; their benchmarks do not establish GalaxySSI performance.
