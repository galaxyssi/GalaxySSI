package com.galaxyssi.chat

import org.json.JSONObject

internal data class AgentVerifiedProjectCompletion(
    val message: String,
    val evidence: String,
    val terminalToolId: String
)

internal object AgentSupervisedProjectCompletionPolicy {
    const val MODEL_TERMINAL_OUTCOME_PARAMETER = "model_terminal_outcome"

    fun missingEvidence(requirements: AgentCompletionRequirements?, history: List<AgentAction>): List<String> {
        if (requirements == null) return listOf("model-declared completion_requirements (publication and phone_linux)")
        val completedTools = history.asSequence()
            .filter(::hasVerifiedCompletionReceipt)
            .map(::toolId)
            .toSet()
        return buildList {
            if (requirements.phoneLinux && AgentOnDeviceRuntimeTools.EXECUTE !in completedTools) {
                add("a successful galaxyssi.runtime.execute receipt from the phone Linux guest")
            }
            if (requirements.publication == AgentPublicationRequirement.PULL_REQUEST && completedTools.none(PULL_REQUEST_COMPLETION_TOOLS::contains)) {
                add("a successfully created pull request with its URL")
            } else if (requirements.publication == AgentPublicationRequirement.PUSH && AgentMobileProjectNativeTools.PUSH !in completedTools) {
                add("a successful push of the verified project branch")
            } else if (requirements.publication == AgentPublicationRequirement.COMMIT && AgentMobileProjectNativeTools.COMMIT !in completedTools) {
                add("a successful commit of the verified phone project")
            }
        }
    }

    /**
     * Closes only an outcome the supervising model already chose and a phone-native
     * tool proved. This avoids another model turn whose sole purpose is to repeat an
     * authoritative commit, push, or pull-request receipt.
     */
    fun verifiedTerminalOutcome(
        goal: String,
        history: List<AgentAction>,
        completedAction: AgentAction,
        result: AgentActionResult,
        requirements: AgentCompletionRequirements? = null
    ): AgentVerifiedProjectCompletion? {
        if (!result.success || result.metadata["awaiting_response"] == "true") return null
        if (completedAction.kind != AgentActionKind.CALL_NATIVE_TOOL) return null
        if (completedAction.parameters[MODEL_TERMINAL_OUTCOME_PARAMETER] != "true") return null
        val toolId = completedAction.parameters["tool_id"].orEmpty().ifBlank { completedAction.target }
        if (result.metadata["native_tool_id"] != toolId ||
            result.metadata["native_tool_status"] != "succeeded" ||
            result.metadata["invocation_id"].isNullOrBlank()
        ) {
            return null
        }
        if (missingEvidence(requirements, history).isNotEmpty()) return null
        val outputText = result.metadata["native_tool_output"].orEmpty()
        val output = runCatching { JSONObject(outputText) }.getOrNull() ?: return null
        val chinese = goal.any { character -> character in '\u3400'..'\u9fff' }
        val publication = requirements?.publication
        return when (toolId) {
            AgentMobileProjectNativeTools.CREATE_PULL_REQUEST,
            AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST,
            AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST -> {
                if (publication != AgentPublicationRequirement.PULL_REQUEST) return null
                val atomicPublish = toolId != AgentMobileProjectNativeTools.CREATE_PULL_REQUEST
                if (toolId == AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST &&
                    !GIT_COMMIT.matches(output.optString("commit").trim())
                ) {
                    return null
                }
                val number = output.optLong(if (atomicPublish) "pull_request_number" else "number")
                    .takeIf { it > 0L } ?: return null
                val url = output.optString(if (atomicPublish) "pull_request_url" else "url").trim()
                if (!GITHUB_PULL_REQUEST_URL.matches(url)) return null
                val state = output.optString(if (atomicPublish) "pull_request_state" else "state")
                    .trim()
                    .ifBlank { "open" }
                AgentVerifiedProjectCompletion(
                    message = if (chinese) {
                        "GitHub PR #$number \u5df2\u521b\u5efa\u5e76\u5904\u4e8e $state \u72b6\u6001\uff1a$url"
                    } else {
                        "GitHub PR #$number was created and is $state: $url"
                    },
                    evidence = outputText,
                    terminalToolId = toolId
                )
            }
            AgentMobileProjectNativeTools.PUSH -> {
                if (publication != AgentPublicationRequirement.PUSH) return null
                val branch = output.optString("branch").trim()
                if (branch.isBlank()) return null
                AgentVerifiedProjectCompletion(
                    message = if (chinese) {
                        "\u5df2\u63a8\u9001\u5e76\u9a8c\u8bc1\u5206\u652f $branch\u3002"
                    } else {
                        "Branch $branch was pushed and verified."
                    },
                    evidence = outputText,
                    terminalToolId = toolId
                )
            }
            AgentMobileProjectNativeTools.COMMIT -> {
                if (publication != AgentPublicationRequirement.COMMIT) return null
                val commit = output.optString("commit").trim()
                if (!GIT_COMMIT.matches(commit)) return null
                AgentVerifiedProjectCompletion(
                    message = if (chinese) {
                        "\u5df2\u521b\u5efa\u5e76\u9a8c\u8bc1\u63d0\u4ea4 $commit\u3002"
                    } else {
                        "Commit $commit was created and verified."
                    },
                    evidence = outputText,
                    terminalToolId = toolId
                )
            }
            // Generic receipts are observations, not model-authored final answers.
            else -> null
        }
    }

    private fun hasVerifiedCompletionReceipt(action: AgentAction): Boolean {
        if (action.status != AgentActionStatus.COMPLETED) return false
        val toolId = toolId(action)
        if (toolId !in TERMINAL_EVIDENCE_TOOLS) return true
        val output = runCatching { JSONObject(action.evidence) }.getOrNull() ?: return false
        return when (toolId) {
            AgentOnDeviceRuntimeTools.EXECUTE ->
                output.has("exit_code") && output.optInt("exit_code", Int.MIN_VALUE) == 0
            AgentMobileProjectNativeTools.COMMIT ->
                GIT_COMMIT.matches(output.optString("commit").trim())
            AgentMobileProjectNativeTools.PUSH ->
                output.optString("branch").isNotBlank()
            AgentMobileProjectNativeTools.CREATE_PULL_REQUEST -> validPullRequestEvidence(
                output,
                numberKey = "number",
                urlKey = "url"
            )
            AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST -> validPullRequestEvidence(
                output,
                numberKey = "pull_request_number",
                urlKey = "pull_request_url"
            )
            AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST ->
                GIT_COMMIT.matches(output.optString("commit").trim()) && validPullRequestEvidence(
                    output,
                    numberKey = "pull_request_number",
                    urlKey = "pull_request_url"
                )
            else -> true
        }
    }

    private fun validPullRequestEvidence(output: JSONObject, numberKey: String, urlKey: String): Boolean =
        output.optLong(numberKey) > 0L && GITHUB_PULL_REQUEST_URL.matches(output.optString(urlKey).trim())

    private fun toolId(action: AgentAction): String =
        action.parameters["tool_id"].orEmpty().ifBlank { action.target }

    private val GITHUB_PULL_REQUEST_URL = Regex("https://github\\.com/[^/\\s]+/[^/\\s]+/pull/[1-9][0-9]*")
    private val GIT_COMMIT = Regex("[0-9a-fA-F]{7,64}")
    private val TERMINAL_EVIDENCE_TOOLS = setOf(
        AgentOnDeviceRuntimeTools.EXECUTE,
        AgentMobileProjectNativeTools.COMMIT,
        AgentMobileProjectNativeTools.PUSH,
        AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST,
        AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST,
        AgentMobileProjectNativeTools.CREATE_PULL_REQUEST
    )
    private val PULL_REQUEST_COMPLETION_TOOLS = setOf(
        AgentMobileProjectNativeTools.FINALIZE_PULL_REQUEST,
        AgentMobileProjectNativeTools.PUBLISH_PULL_REQUEST,
        AgentMobileProjectNativeTools.CREATE_PULL_REQUEST
    )
}
