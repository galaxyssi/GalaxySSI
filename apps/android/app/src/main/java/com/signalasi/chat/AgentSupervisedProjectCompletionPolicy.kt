package com.signalasi.chat

import org.json.JSONObject

internal data class AgentVerifiedProjectCompletion(
    val message: String,
    val evidence: String,
    val terminalToolId: String
)

internal object AgentSupervisedProjectCompletionPolicy {
    const val MODEL_TERMINAL_OUTCOME_PARAMETER = "model_terminal_outcome"

    fun missingEvidence(goal: String, history: List<AgentAction>): List<String> {
        val completedTools = history.asSequence()
            .filter(::hasVerifiedCompletionReceipt)
            .map(::toolId)
            .toSet()
        val intent = publicationIntent(goal)
        return buildList {
            if (requiresPhoneLinuxExecution(goal) && AgentOnDeviceRuntimeTools.EXECUTE !in completedTools) {
                add("a successful signalasi.runtime.execute receipt from the phone Linux guest")
            }
            if (intent.pullRequest && AgentMobileProjectNativeTools.CREATE_PULL_REQUEST !in completedTools) {
                add("a successfully created pull request with its URL")
            } else if (intent.push && AgentMobileProjectNativeTools.PUSH !in completedTools) {
                add("a successful push of the verified project branch")
            } else if (intent.commit && AgentMobileProjectNativeTools.COMMIT !in completedTools) {
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
        result: AgentActionResult
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
        if (missingEvidence(goal, history).isNotEmpty()) return null
        val outputText = result.metadata["native_tool_output"].orEmpty()
        val output = runCatching { JSONObject(outputText) }.getOrNull() ?: return null
        val chinese = goal.any { character -> character in '\u3400'..'\u9fff' }
        return when (toolId) {
            AgentMobileProjectNativeTools.CREATE_PULL_REQUEST -> {
                val number = output.optLong("number").takeIf { it > 0L } ?: return null
                val url = output.optString("url").trim()
                if (!GITHUB_PULL_REQUEST_URL.matches(url)) return null
                val state = output.optString("state").trim().ifBlank { "open" }
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
            else -> result.message.trim().take(6_000).takeIf(String::isNotBlank)?.let { message ->
                AgentVerifiedProjectCompletion(
                    message = message,
                    evidence = outputText,
                    terminalToolId = toolId
                )
            }
        }
    }

    private fun requiresPhoneLinuxExecution(goal: String): Boolean {
        val normalized = goal.trim().lowercase()
        return PHONE_LINUX_PATTERNS.any { pattern -> pattern.containsMatchIn(normalized) }
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
            AgentMobileProjectNativeTools.CREATE_PULL_REQUEST ->
                output.optLong("number") > 0L &&
                    GITHUB_PULL_REQUEST_URL.matches(output.optString("url").trim())
            else -> true
        }
    }

    private fun toolId(action: AgentAction): String =
        action.parameters["tool_id"].orEmpty().ifBlank { action.target }

    private fun publicationIntent(goal: String): PublicationIntent {
        val normalized = goal.trim().lowercase()
        if (LOCAL_ONLY_PATTERNS.any { pattern -> pattern.containsMatchIn(normalized) }) {
            return PublicationIntent(commit = false, push = false, pullRequest = false)
        }
        val pullRequest = PULL_REQUEST_PATTERNS.any { pattern -> pattern.containsMatchIn(normalized) } ||
            requiresPublishedProjectChange(normalized)
        val push = !pullRequest && PUSH_PATTERNS.any { pattern -> pattern.containsMatchIn(normalized) }
        val commit = !pullRequest && !push && COMMIT_PATTERNS.any { pattern -> pattern.containsMatchIn(normalized) }
        return PublicationIntent(commit = commit, push = push, pullRequest = pullRequest)
    }

    private fun requiresPublishedProjectChange(normalizedGoal: String): Boolean =
        AgentSupervisedRepositoryPolicy.repositoryUrl(normalizedGoal) != null &&
            PROJECT_CHANGE_PATTERNS.any { pattern -> pattern.containsMatchIn(normalizedGoal) } &&
            LOCAL_ONLY_PATTERNS.none { pattern -> pattern.containsMatchIn(normalizedGoal) }

    private data class PublicationIntent(
        val commit: Boolean,
        val push: Boolean,
        val pullRequest: Boolean
    )

    private val PULL_REQUEST_PATTERNS = listOf(
        Regex("\\bpull\\s+request\\b"),
        Regex("\\bpr\\b"),
        Regex("merge\\s+request"),
        Regex("(?:\u63d0\u4ea4|\u521b\u5efa|\u65b0\u5efa|\u53d1\u8d77)\\s*(?:github\\s*)?(?:pr|\u62c9\u53d6\u8bf7\u6c42|\u5408\u5e76\u8bf7\u6c42)")
    )
    private val PUSH_PATTERNS = listOf(
        Regex("\\bgit\\s+push\\b"),
        Regex("\\bpush\\b"),
        Regex("\u63a8\u9001.{0,12}(?:\u5206\u652f|\u4ee3\u7801|\u6539\u52a8|\u4ed3\u5e93|github)")
    )
    private val COMMIT_PATTERNS = listOf(
        Regex("\\bgit\\s+commit\\b"),
        Regex("\\bcommit\\s+(?:the\\s+)?(?:change|changes|code|work|files?|project)\\b"),
        Regex("\\b(?:create|make|record|save)\\s+(?:a\\s+)?commit\\b"),
        Regex("\u63d0\u4ea4.{0,8}(?:\u4ee3\u7801|\u6539\u52a8|\u4fee\u6539|\u53d8\u66f4|\u63d0\u4ea4\u8bb0\u5f55)")
    )
    private val PROJECT_CHANGE_PATTERNS = listOf(
        Regex("\\b(?:fix|change|modify|update|improve|improvement|implement|refactor|develop|upgrade)\\b"),
        Regex("(?:\u4fee\u590d|\u4fee\u6539|\u6539\u52a8|\u66f4\u65b0|\u6539\u8fdb|\u5b9e\u73b0|\u5f00\u53d1|\u91cd\u6784|\u5347\u7ea7)")
    )
    private val LOCAL_ONLY_PATTERNS = listOf(
        Regex("\\blocal[- ]only\\b"),
        Regex("\\bdo not (?:push|publish|open (?:a )?pull request)\\b"),
        Regex("(?:\u4ec5\u672c\u5730|\u53ea\u5728\u672c\u5730|\u4e0d\u8981\u63a8\u9001|\u4e0d\u8981\u53d1\u5e03|\u4e0d\u8981\u63d0\u4ea4\\s*pr)")
    )
    private val PHONE_LINUX_PATTERNS = listOf(
        Regex("\\b(?:phone|on-device|local|android)[ -]?linux\\b"),
        Regex("\\blinux (?:guest|runtime|workspace|system)\\b"),
        Regex("(?:\u624b\u673a|\u672c\u673a|\u672c\u4f53|\u7aef\u4fa7).{0,8}linux"),
        Regex("linux.{0,8}(?:\u5de5\u4f5c\u533a|\u7cfb\u7edf|\u73af\u5883|\u865a\u62df\u673a)")
    )
    private val GITHUB_PULL_REQUEST_URL = Regex("https://github\\.com/[^/\\s]+/[^/\\s]+/pull/[1-9][0-9]*")
    private val GIT_COMMIT = Regex("[0-9a-fA-F]{7,64}")
    private val TERMINAL_EVIDENCE_TOOLS = setOf(
        AgentOnDeviceRuntimeTools.EXECUTE,
        AgentMobileProjectNativeTools.COMMIT,
        AgentMobileProjectNativeTools.PUSH,
        AgentMobileProjectNativeTools.CREATE_PULL_REQUEST
    )
}
