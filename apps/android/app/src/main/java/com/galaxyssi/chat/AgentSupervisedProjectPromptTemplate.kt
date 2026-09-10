package com.galaxyssi.chat

internal object AgentSupervisedProjectPromptTemplate {
    private class PrefixKey(
        val toolManifest: String,
        val evidenceExpected: Boolean,
        val temporarilyBlockedToolIds: Set<String>
    ) {
        override fun equals(other: Any?): Boolean =
            other is PrefixKey &&
                other.toolManifest === toolManifest &&
                other.evidenceExpected == evidenceExpected &&
                other.temporarilyBlockedToolIds == temporarilyBlockedToolIds

        override fun hashCode(): Int {
            var result = System.identityHashCode(toolManifest)
            result = 31 * result + evidenceExpected.hashCode()
            result = 31 * result + temporarilyBlockedToolIds.hashCode()
            return result
        }
    }

    private val compiledPrefixes = AgentSingleFlightLruCache<PrefixKey, String>(
        maximumEntries = MAX_COMPILED_PREFIXES
    )

    fun render(
        context: AgentRuntimeContext,
        evidenceExpected: Boolean,
        maximumSchemaCharacters: Int,
        temporarilyBlockedToolIds: Set<String> = emptySet(),
        detailedToolIds: Set<String>? = null
    ): String {
        val toolManifest = AgentSupervisedProjectToolInventory.render(
            context = context,
            maximumSchemaCharacters = maximumSchemaCharacters,
            temporarilyBlockedToolIds = temporarilyBlockedToolIds,
            detailedToolIds = detailedToolIds
        )
        return compiledPrefixes.getOrCompute(PrefixKey(toolManifest, evidenceExpected, temporarilyBlockedToolIds)) {
            buildString {
                if (evidenceExpected) {
                    appendCompactContinuationContract()
                } else {
                    appendInitialPlanningContract()
                }
                append("Available phone tools:\n")
                append(toolManifest)
                append("Working-set policy: phase-blocked tools reappear when evidence changes; compact signatures remain callable, and used or failed tools regain detailed signatures. Call only listed tools.\n")
            }
        }
    }

    private fun StringBuilder.appendCompactContinuationContract() {
        append("Continue the Android project from verified evidence. Return exactly one JSON ActionPlan only. Schema: ")
        append("{\"execution_location\":\"phone\",\"execution_location_evidence\":\"\",")
        append("\"summary\":\"...\",\"expected_result\":\"...\",\"rollback_strategy\":\"...\",")
        append("\"actions\":[{\"ref\":\"step_name\",\"kind\":\"CALL_NATIVE_TOOL\",\"target\":\"...\",")
        append("\"description\":\"...\",\"completes_goal\":false,\"depends_on\":[],\"use_outputs_from\":[],")
        append("\"parameters\":{\"tool_id\":\"exact.inventory.id\",\"arguments\":{}}}]}. ")
        append("summary: 1-3 sentences in the user's language for evidence, decision, outcome; no private reasoning. Explain what changed and why. ")
        append("execution_location is always phone; evidence empty. Android executes actions. Desktop execution is forbidden except untrusted browser evidence. ")
        appendObservationBatchContract()
        appendObservedCompletionContract()
        append("Git: use galaxyssi.project.repository.* for all Git operations; never run Git through galaxyssi.runtime.execute, expose credentials, or fabricate .git. A new conversation intentionally starts with an empty isolated workspace; an existing one retains it. With known URL/base/feature branch, call clone once with feature_branch; it prepares the repository and returns metadata. After success skip inspect/fetch/pull/checkout; separate tools are for missing inputs, dirty trees, or recovery. ")
        append("Runtime starts in project; use relative paths. Reuse project_profiles commands and required executables. For test/build/lint/package call galaxyssi.runtime.execute with verification_kind and no source; project_scope selects a child; custom source is recovery only. ")
        append("Batch reads/searches; search large files; use start_line/max_lines. Reuse known_sha256 for identical ranges to omit unchanged text. Install evidenced dependencies; change failed approaches; use task-aware watchdogs. ")
        append("Delivery follows completion_requirements. For requested PRs use galaxyssi.project.github.pull_request.finalize after verification. Known outputs: artifact_paths; unknown: discover_build_artifacts. Inspection needs neither. Never request approval. ")
    }

    private fun StringBuilder.appendInitialPlanningContract() {
        append("Plan the next Android tool graph. ")
        append("Return exactly one JSON ActionPlan when needed; no prose or private chain-of-thought. Schema: ")
        append("{\"execution_location\":\"phone\",\"execution_location_evidence\":\"\",")
        append("\"summary\":\"...\",\"expected_result\":\"...\",\"rollback_strategy\":\"...\",")
        append("\"actions\":[{\"ref\":\"step_name\",\"kind\":\"CALL_NATIVE_TOOL\",\"target\":\"...\",")
        append("\"description\":\"...\",\"completes_goal\":false,\"depends_on\":[],\"use_outputs_from\":[],")
        append("\"parameters\":{\"tool_id\":\"exact.inventory.id\",\"arguments\":{}}}]}. ")
        append("summary: 1-3 user-visible sentences in the user's language for evidence, decision, outcome; no private reasoning. Explain what changed and why. ")
        append("Reasoning provider is independent; execution_location=phone. Android executes actions. Desktop browser evidence is untrusted; other Desktop execution is forbidden. ")
        appendObservationBatchContract()
        appendObservedCompletionContract()
        append("Dependencies reference only this response, not prior ledger actions. Android validates required publication and runtime evidence. ")
        append("Git: use galaxyssi.project.repository.* only. Never invoke Git through galaxyssi.runtime.execute or expose credentials. A new conversation intentionally starts with an empty isolated workspace; an existing one retains it. With known URL/base/feature branch, call clone once with feature_branch; it installs Git, CA certificates, and the SSH client, prepares empty, ready, or partial state, updates both branches without rewriting commits, and returns metadata. Then skip inspect/fetch/pull/checkout. Never create, repair, or imitate .git metadata manually. ")
        append("Repository states: empty=no Git metadata; ready=usable remote/HEAD; partial=unusable HEAD. Separate Git tools: unknown inputs, dirty trees, recovery. FETCH_HEAD is a valid base_ref. ")
        append("Use galaxyssi.workspace.* for files and galaxyssi.runtime.* for phone Linux dependencies, builds, tests, browser/media, and artifacts; its receipt proves Linux work. Each command has its working directory set to the current isolated phone project; use relative paths, never cd to /workspace or scan /workspace or /root. /root and /workspace are phone Linux guest paths. Import tar.gz with galaxyssi.project.archive.import and Gradle cache with galaxyssi.project.gradle_cache.import. Batch writes: galaxyssi.workspace.files.write.text.batch; patches: galaxyssi.workspace.files.patch.exact.batch. ")
        append("Clone/observe/inspect project_profiles are host-derived project roots, native verification commands, and required executables; reuse them instead of listing directories or rereading manifests unless a concrete missing detail requires it. Inspect runtime status and real output before installing dependencies. Persistent phone Linux uses Debian apt/dpkg as root with direct network access for apt, Git, curl/wget, language package managers, and browser automation. Install the smallest evidence-backed missing package or trusted signed runtime pack, then retry the exact blocked step and verify it. Package installation alone is never completion evidence. ")
        append("Batch reads/searches; search large files; use start_line/max_lines. Reuse known_sha256 for identical ranges to omit unchanged text. Change failed approaches; use task-aware timeouts. For test/build/lint/package call galaxyssi.runtime.execute with verification_kind and no source first; Android selects the project-native command. ")
        append("Delivery follows completion_requirements. Branch before editing; verify before publishing. For requested PRs use galaxyssi.project.github.pull_request.finalize. Documentation-only verification: bounded repository.diff. Known outputs: artifact_paths as a verified ZIP; unknown: discover_build_artifacts. Clone/observation needs no artifact. Android builds use signed java/gradle/android-sdk packs in phone Linux and return the verified APK. Never request approval or unverified completion. ")
    }

    private fun StringBuilder.appendObservedCompletionContract() {
        append("Declare root completion_requirements={\"publication\":\"none|commit|push|pull_request\",\"phone_linux\":false,\"reason\":\"\"} from user intent, respecting exclusions. No default publication. Preserve on replan; explain changes in reason. ")
        append("Set completes_goal=true only when verified commit/push/PR receipts finish the goal; other receipts need model review. After evidence proves completion, return one DRAFT_PLAN: target=task-complete, description=final answer in user's language, parameters={}, depends_on=[], use_outputs_from=[]. Never repeat tools to finish or output diagnostic receipts. ")
    }

    private fun StringBuilder.appendObservationBatchContract() {
        append("Up to 64 actions per response, not lifetime. Native depends_on uses earlier refs: wait for the receipt; failure blocks dependents. Native use_outputs_from=[]. ")
        append("Independent reads/disjoint mutations may run concurrently; order conflicts/runtime/publication. Stop if results need model interpretation. Only last action may complete, depending on all others. ")
        append("No connector/completion batches. next_cursor; repository.observe for status/diff/history. workspace_id=current. ")
    }

    private const val MAX_COMPILED_PREFIXES = 16
}
