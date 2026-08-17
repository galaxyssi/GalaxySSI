package com.signalasi.chat

internal object AgentSupervisedProjectCompletionPolicy {
    fun missingEvidence(goal: String, history: List<AgentAction>): List<String> {
        val completedTools = history.asSequence()
            .filter { action -> action.status == AgentActionStatus.COMPLETED }
            .map { action -> action.parameters["tool_id"].orEmpty().ifBlank { action.target } }
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

    private fun requiresPhoneLinuxExecution(goal: String): Boolean {
        val normalized = goal.trim().lowercase()
        return PHONE_LINUX_PATTERNS.any { pattern -> pattern.containsMatchIn(normalized) }
    }

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
}
