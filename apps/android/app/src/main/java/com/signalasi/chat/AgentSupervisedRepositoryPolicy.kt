package com.signalasi.chat

/** Keeps project work on a real phone-Linux Git checkout without choosing actions for the model. */
internal object AgentSupervisedRepositoryPolicy {
    fun repositoryUrl(goal: String): String? = githubRepositoryPattern.find(goal)
        ?.value
        ?.trimEnd('.', ',', ';', ':', ')', ']', '}')

    fun violatesProjectGitBoundary(raw: String): Boolean {
        val json = AgentExecutionSiteDecisionCodec.extractJsonObject(raw) ?: return false
        val actions = json.optJSONArray("actions") ?: return false
        for (index in 0 until actions.length()) {
            val action = actions.optJSONObject(index) ?: continue
            val parameters = action.optJSONObject("parameters") ?: continue
            if (parameters.optString("tool_id") != AgentOnDeviceRuntimeTools.EXECUTE) continue
            val arguments = parameters.optJSONObject("arguments") ?: continue
            val source = arguments.optString("source")
            if (GIT_COMMAND.containsMatchIn(source)) return true
        }
        return false
    }

    val githubRepositoryPattern = Regex(
        "https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\\.git)?",
        RegexOption.IGNORE_CASE
    )
    private val GIT_COMMAND = Regex(
        "(?:^|[\\r\\n;&|()]\\s*|\\b(?:if|then|do|while|exec|command|sudo|env|timeout)\\s+(?:\\d+[smh]?\\s+)?)" +
            "(?:[A-Za-z_][A-Za-z0-9_]*=\\S+\\s+)*git(?:\\s|$)",
        setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE)
    )
}
