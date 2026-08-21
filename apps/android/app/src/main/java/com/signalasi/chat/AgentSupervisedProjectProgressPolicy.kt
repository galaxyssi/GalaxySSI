package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Keeps model-directed project work moving from verified evidence instead of replaying stale steps. */
internal object AgentSupervisedProjectProgressPolicy {
    fun canonicalize(action: AgentAction, history: List<AgentAction>): AgentAction {
        if (action.kind != AgentActionKind.CALL_NATIVE_TOOL) return action
        val completed = history.filter { it.status == AgentActionStatus.COMPLETED }
        val sameWorkspace = completed.filter { previous ->
            previous.kind == AgentActionKind.CALL_NATIVE_TOOL &&
                previous.workspaceId() == action.workspaceId()
        }
        val recovery = repositoryRecoveryState(sameWorkspace) ?: return action
        if (action.toolId() !in setOf(
                AgentMobileProjectNativeTools.CLONE,
                AgentMobileProjectNativeTools.INSPECT,
                AgentMobileProjectNativeTools.CHECKOUT_BRANCH
            )
        ) {
            return action
        }
        val input = action.inputObject()
        val branch = input.optString("branch").trim()
            .takeUnless { it in setOf("main", "master") }
            .orEmpty()
            .ifBlank { recoveryBranch(action.id) }
        val canonicalInput = JSONObject()
            .put("workspace_id", input.optString("workspace_id").ifBlank { "current" })
            .put("branch", branch)
            .put("base_ref", recovery.baseRef)
            .put("create", true)
            .toString()
        return action.copy(
            target = AgentMobileProjectNativeTools.CHECKOUT_BRANCH,
            description = "Recover the fetched phone repository on a dedicated branch",
            parameters = action.parameters + mapOf(
                "tool_id" to AgentMobileProjectNativeTools.CHECKOUT_BRANCH,
                "input_json" to canonicalInput,
                "host_canonicalization" to "partial_repository_fetch_checkout"
            )
        )
    }

    fun violation(
        action: AgentAction,
        history: List<AgentAction>,
        durablePullRequestEvidence: Boolean = false
    ): String? {
        if (action.kind != AgentActionKind.CALL_NATIVE_TOOL) return null
        val toolId = action.toolId()
        val completed = history.filter { it.status == AgentActionStatus.COMPLETED }
        val sameWorkspace = completed.filter { previous ->
            previous.kind == AgentActionKind.CALL_NATIVE_TOOL &&
                previous.workspaceId() == action.workspaceId()
        }
        repositoryRecoveryViolation(action, sameWorkspace)?.let { return it }
        publicationOrderViolation(action, sameWorkspace, durablePullRequestEvidence)?.let { return it }
        discoveryStagnationViolation(action, sameWorkspace)?.let { return it }
        if (toolId !in replayGuardedTools) return null
        if (toolId == AgentMobileProjectNativeTools.CLONE &&
            sameWorkspace.any { it.toolId() == AgentMobileProjectNativeTools.CLONE }
        ) {
            return "The requested repository clone already completed in this conversation workspace. " +
                "Use its verified state and choose the next project phase."
        }
        if (toolId == AgentMobileProjectNativeTools.PULL) {
            val previousPull = sameWorkspace.indexOfLast { it.toolId() == AgentMobileProjectNativeTools.PULL }
            if (previousPull >= 0 && sameWorkspace.drop(previousPull + 1).none { previous ->
                    previous.toolId() == AgentMobileProjectNativeTools.CHECKOUT_BRANCH
                }
            ) {
                return "The repository baseline was already synchronized successfully, and no later branch checkout " +
                    "made that baseline stale. Continue to the next project phase instead of pulling again."
            }
        }
        val previousIndex = completed.indexOfLast { previous ->
            previous.kind == AgentActionKind.CALL_NATIVE_TOOL &&
                previous.toolId() == toolId &&
                sameStableInput(previous, action)
        }
        if (previousIndex < 0) return null

        val stateChangedSince = completed.drop(previousIndex + 1).any(::changesProjectState)
        if (stateChangedSince) return null
        return "The same successful $toolId action with equivalent inputs is already in the verified ledger, " +
            "and no project mutation has occurred since it ran. Choose a different next action."
    }

    fun promptBlock(history: List<AgentAction>): String? {
        val observed = history.asSequence()
            .filterNot(AgentAction::isSupervisedProjectConnector)
            .filter { it.status in terminalStatuses }
            .toList()
        if (observed.isEmpty()) return null
        val recent = observed.takeLast(MAX_VISIBLE_LEDGER_ACTIONS)

        return buildString {
            append("Verified project progress ledger. This is SignalASI-owned context and host facts:\n")
            append(lifecycleSnapshot(observed)).append('\n')
            append("Do not replay a successful action with equivalent inputs unless a later verified mutation made its observation stale. ")
            append("The JSON action must perform the immediate next step described by summary. ")
            append("Recent observations follow in chronological order; the newest observation is last.\n")
            recent.forEach { action ->
                append("- status=").append(action.status.name)
                append("; tool=").append(action.toolId().ifBlank { action.kind.name })
                AgentPlannerObservation.from(action, MAX_ACTION_OBSERVATION_CHARACTERS)?.let { result ->
                    append("; observation=")
                        .append(result)
                }
                append('\n')
            }
        }
    }

    private fun lifecycleSnapshot(actions: List<AgentAction>): String {
        val branchIndex = dedicatedBranchStartIndex(actions)
        val branchActions = if (branchIndex >= 0) actions.drop(branchIndex + 1) else emptyList()
        val sourceMutation = branchActions.any(::isVerifiedSourceMutation)
        val commitIndex = branchActions.indexOfLast { it.toolId() == AgentMobileProjectNativeTools.COMMIT }
        val pushIndex = branchActions.indexOfLast { it.toolId() == AgentMobileProjectNativeTools.PUSH }
        val pullRequest = branchActions.any { it.toolId() == AgentMobileProjectNativeTools.CREATE_PULL_REQUEST }
        val discoveries = branchActions.count(::isDiscoveryAction)
        return buildString {
            append("Verified lifecycle snapshot: dedicated_branch=").append(branchIndex >= 0)
            append("; source_mutation=").append(sourceMutation)
            append("; commit=").append(commitIndex >= 0)
            append("; push=").append(pushIndex > commitIndex && commitIndex >= 0)
            append("; pull_request=").append(pullRequest)
            append("; discovery_actions_since_branch=").append(discoveries).append(". ")
            repositoryRecoveryState(actions)?.let { recovery ->
                append("Repository recovery: state=partial; remote_present=true; fetch_complete=true; ")
                append("fetched_base_ref=").append(recovery.baseRef)
                append("; next_required=branch_checkout_from_fetched_base. ")
                append("Do not clone the repository or claim that remote refs are empty. ")
            }
            if (branchIndex >= 0 && !sourceMutation) {
                append("A clean branch created at the baseline contains no implemented change; it is not evidence of a commit. ")
                append("Do not publish it. Inspect only the specific evidence still needed, then make a bounded source or documentation mutation.")
            }
        }
    }

    private fun repositoryRecoveryViolation(
        proposed: AgentAction,
        sameWorkspace: List<AgentAction>
    ): String? {
        val recovery = repositoryRecoveryState(sameWorkspace) ?: return null
        return when (proposed.toolId()) {
            AgentMobileProjectNativeTools.CLONE ->
                "The partial repository already has a valid remote and a successful fetch receipt. " +
                    "Do not clone it. Create a dedicated branch from ${recovery.baseRef}."
            AgentMobileProjectNativeTools.INSPECT ->
                "The partial repository and successful fetch are already verified. Repeating inspection cannot " +
                    "create HEAD. Create a dedicated branch from ${recovery.baseRef}."
            AgentMobileProjectNativeTools.CHECKOUT_BRANCH -> {
                val input = proposed.inputObject()
                val create = input.optBoolean("create", true)
                val baseRef = input.optString("base_ref").trim()
                if (!create || baseRef != recovery.baseRef) {
                    "Repository recovery requires branch checkout with create=true and " +
                        "base_ref=${recovery.baseRef}."
                } else null
            }
            else -> null
        }
    }

    private fun repositoryRecoveryState(actions: List<AgentAction>): RepositoryRecoveryState? {
        val inspectIndex = actions.indexOfLast { action ->
            action.toolId() == AgentMobileProjectNativeTools.INSPECT && action.observesPartialRepositoryWithRemote()
        }
        if (inspectIndex < 0) return null
        val fetchIndex = actions.indexOfLast { action ->
            action.toolId() == AgentMobileProjectNativeTools.FETCH && action.status == AgentActionStatus.COMPLETED
        }
        if (fetchIndex < 0) return null
        val recoveryStartedAt = minOf(inspectIndex, fetchIndex)
        if (actions.drop(recoveryStartedAt + 1).any {
                it.toolId() == AgentMobileProjectNativeTools.CHECKOUT_BRANCH
            }
        ) {
            return null
        }
        val fetch = actions[fetchIndex]
        return RepositoryRecoveryState(fetch.fetchedBaseRef())
    }

    private fun AgentAction.observesPartialRepositoryWithRemote(): Boolean {
        val observation = runCatching { JSONObject(evidence) }.getOrNull() ?: return false
        return observation.optString("repository_state") == "partial" &&
            observation.optString("repository_url").isNotBlank()
    }

    private fun AgentAction.fetchedBaseRef(): String {
        val input = inputObject()
        val remote = input.optString("remote").trim().ifBlank { "origin" }
        val ref = input.optString("ref").trim()
        return when {
            ref.isBlank() -> "FETCH_HEAD"
            ref.startsWith("refs/heads/") -> "refs/remotes/$remote/${ref.removePrefix("refs/heads/")}"
            ref.startsWith("refs/") -> "FETCH_HEAD"
            else -> "refs/remotes/$remote/$ref"
        }
    }

    private fun recoveryBranch(actionId: String): String {
        val suffix = actionId.lowercase()
            .replace(NON_BRANCH_CHARACTER, "-")
            .trim('-')
            .take(36)
            .ifBlank { "recovery" }
        return "signalasi/phone-$suffix"
    }

    private data class RepositoryRecoveryState(val baseRef: String)

    private val NON_BRANCH_CHARACTER = Regex("[^a-z0-9._-]+")

    private fun publicationOrderViolation(
        proposed: AgentAction,
        sameWorkspace: List<AgentAction>,
        durablePullRequestEvidence: Boolean
    ): String? {
        val toolId = proposed.toolId()
        if (toolId !in publicationTools) return null
        if (toolId == AgentMobileProjectNativeTools.CREATE_PULL_REQUEST && durablePullRequestEvidence) {
            return null
        }
        val branchIndex = dedicatedBranchStartIndex(sameWorkspace)
        if (branchIndex < 0) {
            return "Publishing is not valid yet because no verified dedicated feature branch exists. " +
                "Create the branch before changing and publishing the project."
        }
        val phase = sameWorkspace.drop(branchIndex + 1)
        val mutationIndex = phase.indexOfLast(::isVerifiedSourceMutation)
        val commitIndex = phase.indexOfLast { it.toolId() == AgentMobileProjectNativeTools.COMMIT }
        val pushIndex = phase.indexOfLast { it.toolId() == AgentMobileProjectNativeTools.PUSH }
        return when (toolId) {
            AgentMobileProjectNativeTools.COMMIT -> if (mutationIndex < 0) {
                "The dedicated branch has no verified source or documentation mutation. Make and review a bounded " +
                    "change before committing; a clean branch alone is not completed work."
            } else null
            AgentMobileProjectNativeTools.PUSH -> if (commitIndex < mutationIndex || commitIndex < 0) {
                "The dedicated branch has no successful commit after its latest verified mutation. Verify and commit " +
                    "the change before pushing."
            } else null
            AgentMobileProjectNativeTools.CREATE_PULL_REQUEST -> if (pushIndex < commitIndex || pushIndex < 0) {
                "The verified commit has not been pushed successfully. Push the feature branch before creating a pull request."
            } else null
            else -> null
        }
    }

    private fun AgentAction.toolId(): String = parameters["tool_id"].orEmpty().ifBlank { target }

    private fun AgentAction.workspaceId(): String = runCatching {
        JSONObject(parameters["input_json"].orEmpty()).optString("workspace_id")
    }.getOrDefault("").ifBlank { "current" }

    private fun sameStableInput(left: AgentAction, right: AgentAction): Boolean =
        canonicalInput(left.parameters["input_json"]) == canonicalInput(right.parameters["input_json"])

    private fun canonicalInput(raw: String?): String {
        val text = raw.orEmpty().trim()
        if (text.isBlank()) return "{}"
        return runCatching { canonicalJson(JSONObject(text)) }.getOrElse { text }
    }

    private fun canonicalJson(value: JSONObject): String = value.keys().asSequence()
        .sorted()
        .joinToString(prefix = "{", postfix = "}") { key ->
            JSONObject.quote(key) + ":" + canonicalValue(value.opt(key))
        }

    private fun canonicalValue(value: Any?): String = when (value) {
        null, JSONObject.NULL -> "null"
        is JSONObject -> canonicalJson(value)
        is JSONArray -> (0 until value.length()).joinToString(prefix = "[", postfix = "]") { index ->
            canonicalValue(value.opt(index))
        }
        is String -> JSONObject.quote(value)
        else -> value.toString()
    }

    private fun changesProjectState(action: AgentAction): Boolean {
        if (action.kind != AgentActionKind.CALL_NATIVE_TOOL) return false
        val toolId = action.toolId()
        return toolId !in readOnlyTools && toolId != AgentMobileProjectNativeTools.PULL
    }

    private fun discoveryStagnationViolation(
        proposed: AgentAction,
        sameWorkspace: List<AgentAction>
    ): String? {
        val branchIndex = dedicatedBranchStartIndex(sameWorkspace)
        if (branchIndex < 0) return null
        val currentPhase = sameWorkspace.drop(branchIndex + 1)
        if (currentPhase.any(::isVerifiedSourceMutation)) return null
        val discoveries = currentPhase.count(::isDiscoveryAction)
        if (discoveries < MAX_DISCOVERY_ACTIONS_WITHOUT_MUTATION) return null
        if (!isDiscoveryAction(proposed) && proposed.toolId() != AgentMobileProjectNativeTools.PULL) return null
        return "A dedicated branch is already active, but $discoveries successful read-only discovery actions " +
            "have produced no project mutation. Use the collected evidence to make one concrete bounded change " +
            "instead of inspecting or synchronizing the clean workspace again."
    }

    private fun isVerifiedSourceMutation(action: AgentAction): Boolean =
        action.toolId() in sourceMutationTools ||
            action.isVerifiedRuntimeMutation() ||
            action.observesWorkingTreeChanges()

    private fun AgentAction.isVerifiedRuntimeMutation(): Boolean {
        if (status != AgentActionStatus.COMPLETED || toolId() != AgentOnDeviceRuntimeTools.EXECUTE) {
            return false
        }
        val source = inputObject().optString("source").trim().lowercase()
        return source.isNotBlank() && MUTATING_SHELL_MARKERS.any(source::contains)
    }

    private fun isDiscoveryAction(action: AgentAction): Boolean {
        val toolId = action.toolId()
        if (toolId in discoveryTools) return true
        if (toolId != AgentOnDeviceRuntimeTools.EXECUTE) return false
        val source = action.inputObject().optString("source").trim().lowercase()
        if (source.isBlank() || READ_ONLY_SHELL_MARKERS.none(source::contains)) return false
        return MUTATING_SHELL_MARKERS.none(source::contains)
    }

    private fun AgentAction.observesWorkingTreeChanges(): Boolean {
        if (status != AgentActionStatus.COMPLETED ||
            toolId() !in setOf(AgentMobileProjectNativeTools.INSPECT, AgentMobileProjectNativeTools.DIFF)
        ) {
            return false
        }
        return sequenceOf(result, evidence).any { raw ->
            val normalized = raw.lowercase()
            when (toolId()) {
                AgentMobileProjectNativeTools.DIFF ->
                    runCatching { JSONObject(raw).optString("diff") }.getOrDefault("").isNotBlank()
                else ->
                    normalized.contains("\"clean\":false") ||
                        normalized.contains("working_tree_clean=false") ||
                        normalized.contains("changed_files=[") && !normalized.contains("changed_files=[]")
            }
        }
    }

    private fun dedicatedBranchStartIndex(actions: List<AgentAction>): Int =
        actions.indexOfLast { action ->
            action.toolId() == AgentMobileProjectNativeTools.CHECKOUT_BRANCH ||
                action.observesReadyDedicatedBranch()
        }

    private fun AgentAction.observesReadyDedicatedBranch(): Boolean {
        if (toolId() != AgentMobileProjectNativeTools.INSPECT || status != AgentActionStatus.COMPLETED) return false
        val observation = sequenceOf(result, evidence)
            .mapNotNull { raw -> runCatching { JSONObject(raw) }.getOrNull() }
            .firstOrNull { value -> value.optString("branch").isNotBlank() }
            ?: return false
        val branch = observation.optString("branch").trim()
        val ready = observation.optString("repository_state").let { state ->
            state.isBlank() || state == "ready"
        }
        return ready && branch.isNotBlank() && branch !in setOf("main", "master")
    }

    private fun AgentAction.inputObject(): JSONObject =
        runCatching { JSONObject(parameters["input_json"].orEmpty()) }.getOrElse { JSONObject() }

    private val replayGuardedTools = setOf(
        AgentMobileProjectNativeTools.CLONE,
        AgentMobileProjectNativeTools.INSPECT,
        AgentMobileProjectNativeTools.DIFF,
        AgentMobileProjectNativeTools.LOG,
        AgentMobileProjectNativeTools.FETCH,
        AgentMobileProjectNativeTools.CHECKOUT_BRANCH,
        AgentMobileProjectNativeTools.PULL
    )
    private val readOnlyTools = setOf(
        AgentMobileProjectNativeTools.INSPECT,
        AgentMobileProjectNativeTools.DIFF
    )
    private val discoveryTools = setOf(
        AgentMobileProjectNativeTools.INSPECT,
        AgentMobileProjectNativeTools.DIFF,
        AgentPhoneNativeToolCatalog.WORKSPACE_LIST,
        AgentPhoneNativeToolCatalog.WORKSPACE_STAT,
        AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT,
        AgentPhoneNativeToolCatalog.WORKSPACE_READ_BYTES,
        AgentPhoneNativeToolCatalog.WORKSPACE_SEARCH_TEXT,
        AgentPhoneNativeToolCatalog.WORKSPACE_DIFF_SUMMARY,
        AgentPhoneNativeToolCatalog.WORKSPACE_SHA256
    )
    private val sourceMutationTools = setOf(
        AgentPhoneNativeToolCatalog.WORKSPACE_MKDIR,
        AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
        AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT_BATCH,
        AgentPhoneNativeToolCatalog.WORKSPACE_CREATE_TEXT,
        AgentPhoneNativeToolCatalog.WORKSPACE_APPEND_TEXT,
        AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_BYTES,
        AgentPhoneNativeToolCatalog.WORKSPACE_CREATE_BYTES,
        AgentPhoneNativeToolCatalog.WORKSPACE_APPEND_BYTES,
        AgentPhoneNativeToolCatalog.WORKSPACE_MOVE,
        AgentPhoneNativeToolCatalog.WORKSPACE_COPY,
        AgentPhoneNativeToolCatalog.WORKSPACE_DELETE,
        AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH
    )
    private val READ_ONLY_SHELL_MARKERS = listOf(
        "pwd", "ls ", "find ", "cat ", "head ", "tail ", "grep ", "rg ",
        "git status", "git log", "git show", "git branch", "git diff"
    )
    private val MUTATING_SHELL_MARKERS = listOf(
        ">", "tee ", "sed -i", "perl -i", "rm ", "mv ", "cp ", "mkdir ", "touch ",
        "git checkout", "git switch", "git add", "git commit", "git push", "apt ", "apt-get ",
        "npm install", "pnpm install", "yarn install", "gradle", "gradlew",
        ".write_text(", ".write_bytes(", "writefilesync(", "appendfilesync(",
        "renamesync(", "unlinksync("
    )
    private val terminalStatuses = setOf(
        AgentActionStatus.COMPLETED,
        AgentActionStatus.FAILED,
        AgentActionStatus.BLOCKED,
        AgentActionStatus.ROLLED_BACK
    )
    private val publicationTools = setOf(
        AgentMobileProjectNativeTools.COMMIT,
        AgentMobileProjectNativeTools.PUSH,
        AgentMobileProjectNativeTools.CREATE_PULL_REQUEST
    )
    private const val MAX_VISIBLE_LEDGER_ACTIONS = 8
    private const val MAX_ACTION_OBSERVATION_CHARACTERS = 600
    private const val MAX_DISCOVERY_ACTIONS_WITHOUT_MUTATION = 4
}
