package com.signalasi.chat

internal object AgentSupervisedProjectCompletionPolicy {
    fun missingEvidence(goal: String, history: List<AgentAction>): List<String> {
        val completedTools = history.asSequence()
            .filter { action -> action.status == AgentActionStatus.COMPLETED }
            .map { action -> action.parameters["tool_id"].orEmpty().ifBlank { action.target } }
            .toSet()
        val intent = publicationIntent(goal)
        return buildList {
            if (intent.pullRequest && AgentMobileProjectNativeTools.CREATE_PULL_REQUEST !in completedTools) {
                add("a successfully created pull request with its URL")
            } else if (intent.push && AgentMobileProjectNativeTools.PUSH !in completedTools) {
                add("a successful push of the verified project branch")
            } else if (intent.commit && AgentMobileProjectNativeTools.COMMIT !in completedTools) {
                add("a successful commit of the verified phone project")
            }
        }
    }

    private fun publicationIntent(goal: String): PublicationIntent {
        val normalized = goal.trim().lowercase()
        val pullRequest = PULL_REQUEST_PATTERNS.any { pattern -> pattern.containsMatchIn(normalized) }
        val push = !pullRequest && PUSH_PATTERNS.any { pattern -> pattern.containsMatchIn(normalized) }
        val commit = !pullRequest && !push && COMMIT_PATTERNS.any { pattern -> pattern.containsMatchIn(normalized) }
        return PublicationIntent(commit = commit, push = push, pullRequest = pullRequest)
    }

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
        Regex("\\bcommit\\b"),
        Regex("\u63d0\u4ea4.{0,8}(?:\u4ee3\u7801|\u6539\u52a8|\u4fee\u6539|\u53d8\u66f4|\u63d0\u4ea4\u8bb0\u5f55)")
    )
}
