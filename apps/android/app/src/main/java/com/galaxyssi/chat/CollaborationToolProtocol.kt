package com.galaxyssi.chat

internal object CollaborationToolProtocol {
    fun instructions() = """
        Missing reusable tooling: publish executable_tool source + input contract, register tool_test_plan, then actually test it
        through the authorized galaxyssi.runtime.execute collaboration_tool input. Preserve failing checks and revise exact versions.
        A different member reviews the source, oracle and original test receipt before publishing tool_release. Reuse only that exact
        release in later authorized group tasks, checking applicability/environment first. No global tool/Skill is auto-installed.
        Inspect available tools first. A remote member with collaboration_test_tool can request execution in its originating
        phone runtime; otherwise delegate to an authorized member with that runtime. Do not fabricate a native receipt from a shell command.
        Plan build/test/review/reuse as ordinary dependent work; unrelated members continue. Recall evolution_rules for the schema.
        Pure numeric candidates can use numeric_model_trial for host-side case replay and exact failed-case feedback before final acceptance.
        Compare revised tools with tool_test_comparison on the same preserved cases; inspect improvements AND regressions before choosing the next action.
    """.trimIndent()

    fun rules() = """
        Publication envelope: {format:"galaxyssi.research-artifact.v1",summary,workspace:[{id,kind,title,
          body:{content,<kind>:{...}},parents:[],observations:[]}]}.
        Use kind="executable_tool" with body.executable_tool for source; kind="tool_test_plan" with body.tool_test_plan for tests;
        kind="tool_release" with body.tool_release for release review. These are distinct from experiment_plan and generic artifact.
        Publish the tool first, then register tests referencing its exact receipt. Copy object_id, integer revision and sha256.
        A generic artifact containing these fields is only documentation: registration_notice reports unregistered typed payloads.
        On rejection inspect record_validation (code, path, expected, actual, exact reference) and the original draft. The host
        distinguishes missing typed bodies, unavailable records, wrong kinds, changed hashes and stale versions; it does not choose
        a repair strategy or relabel saved records. Read the intended contract and choose a new correctly typed publication if needed.

        executable_tool: {name,purpose,language:"python",source:"Python defining run(parameters) returning JSON",
          input_schema:<existing Skill parameter schema>,applies_when,avoid_when,environment,dependencies,side_effects}.
        Sources are immutable, group-scoped candidates. Correct code by publishing a new linked tool, never overwrite a tested version.
        input_schema uses type object/array/string/integer/number/boolean, properties, required, additional_properties, items,
        enum, min_length/max_length, minimum/maximum, min_items/max_items. No unknown schema keywords. Root type is object.
        Python uses the existing on-device Linux runtime and its permissions/network/timeout/cancellation gates. It is NOT a new
        secure sandbox: the guest is persistent Linux. Review side effects and dependencies; never run untrusted downloaded code
        merely because it is a tool candidate. A source record is not proof of safety, quality, availability or goal completion.

        tool_test_plan: {executable_tool:<exact ref>,environment:"same declared tool environment",purpose,oracle_basis,coverage_gaps,
          cases:[{id,purpose:"target|edge|regression",reason,input:{...},expected:<explicit JSON value including null>}]}.
        Register before execution. Include useful target and regression cases; choose the number from the actual task. Code receives
        only inputs, not expected outputs. Each case gets a fresh Python namespace, not an OS security boundary. Test failures retain
        actual versus expected output and errors. The host compares exact JSON values; it does not accept a model's 'tests passed'.
        Call galaxyssi.runtime.execute with {collaboration_tool:{mode:"test",tool_test_plan:<exact ref>},timeout_ms:...}.
        Remote members may instead call collaboration_test_tool mode=start with execution_id, exact tool_test_plan and timeout_ms,
        then mode=status with the SAME execution_id. Both paths use the same saved-record checks and originating phone runtime.
        Do not also supply source/language/arguments/verification_kind/project_scope/discover_build_artifacts. Saved code and harness
        are compiled by the host. Existing network settings and artifact output remain explicit; a release grants no authority.
        Setup failure/timeout/partial output is NOT a pass. Read the original evidence receipt, diagnose, repair or delegate with the
        existing problem loop. No fixed retry count chooses the next strategy; never rerun side effects solely for a lost receipt.
        Validation feedback separates process exit, report parsing, report format, runtime identity, case coverage and value/type
        mismatch. Read evaluation.problems (code, JSON Pointer path, expected/actual or types, case_id when applicable) and the full
        retained checks. A parsed-object schema error is not a JSON syntax error. Each failed check names its first mismatch;
        the original complete expected/actual values remain available. Symptoms are not proof of a diagnosed capability gap.

        tool_release: {tool_test_plan:<exact ref>,observation:{evidence_id,sha256},review,applies_when,avoid_when,limitations,
          authorization_boundary,unresolved:[]} plus observations:[the original test observation].
        A different member from the code author must read the full original and review code/test coverage/oracle, then release only
        a complete passing host test receipt. Failure evidence remains available via mode=problems/evidence. Passing these examples
        is not general correctness or adversarial security certification. Text claims and generic shell reports cannot mint releases.
        Reuse: galaxyssi.runtime.execute {collaboration_tool:{mode:"run",tool_release:<exact ref>,parameters:{...}},timeout_ms:...}.
        The host loads the saved code/input contract, verifies exact source/test/release versions and applies the original gates.
        Recall mode=evolution + cursor to discover releases; page full source/contracts with mode=workspace. Same-group future tasks
        can reuse them; other groups and isolated current branches cannot. Receipt records retain version, member, run, turn, output
        and failure details. No second executor, scheduler, background polling or automatic global Skill activation is introduced.
        Remote members with collaboration_run_tool can start the same saved-release execution on their originating phone using
        {mode:"start",execution_id,tool_release:<exact ref>,parameters:{...},timeout_ms}. An exact capability_channel may replace
        tool_release. Copy only object_id/revision/sha256 from the selected record. Read applicability before choosing reuse.
        Query mode=status or cancel with the SAME execution_id; transport uncertainty never justifies repeating effects.
        Changing parameters/version under that ID is rejected. Read the full returned evidence for outputs; execution_mode=run
        and passed=true attest native execution, not task quality. Existing authorization, runtime and lineage checks still apply.
    """.trimIndent() + "\n" + CollaborationNumericModelTrial.rules() + "\n" + CollaborationExecutableAcceptance.rules() +
        "\n" + CollaborationToolComparison.rules()
}
