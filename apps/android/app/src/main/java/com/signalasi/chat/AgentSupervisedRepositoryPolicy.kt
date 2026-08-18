package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Keeps remote project work on the phone on a real, reproducible Git checkout. */
internal object AgentSupervisedRepositoryPolicy {
    fun repositoryUrl(goal: String): String? = GITHUB_REPOSITORY.find(goal)
        ?.value
        ?.trimEnd('.', ',', ';', ':', ')', ']', '}')

    fun enforceBootstrap(
        raw: String,
        goal: String,
        history: List<AgentAction>
    ): String {
        val repositoryUrl = repositoryUrl(goal) ?: return raw
        val json = AgentExecutionSiteDecisionCodec.extractJsonObject(raw) ?: return raw
        if (!json.optString("execution_location").equals("phone", ignoreCase = true)) return raw
        val actions = json.optJSONArray("actions") ?: return raw
        if (hasSuccessfulClone(history) || containsClone(actions)) return raw

        json.put(
            "summary",
            "The phone project does not have the requested repository yet. SignalASI will prepare Git if needed and clone it before editing the real codebase."
        )
        json.put("actions", JSONArray().put(cloneAction(repositoryUrl)))
        return json.toString()
    }

    private fun cloneAction(repositoryUrl: String): JSONObject = JSONObject()
        .put("ref", "bootstrap_repository")
        .put("kind", AgentActionKind.CALL_NATIVE_TOOL.name)
        .put("target", AgentMobileProjectNativeTools.CLONE)
        .put(
            "description",
            "Prepare Git and clone the project repository in phone Linux"
        )
        .put("depends_on", JSONArray())
        .put("use_outputs_from", JSONArray())
        .put(
            "parameters",
            JSONObject()
                .put("tool_id", AgentMobileProjectNativeTools.CLONE)
                .put(
                    "arguments",
                    JSONObject()
                        .put("workspace_id", "current")
                        .put("repository_url", repositoryUrl)
                        .put("depth", 1)
                        .put("replace_existing", false)
                )
        )

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

    private fun hasSuccessfulClone(history: List<AgentAction>): Boolean = history.any { action ->
        action.status == AgentActionStatus.COMPLETED &&
            action.parameters["tool_id"] == AgentMobileProjectNativeTools.CLONE
    }

    private fun containsClone(actions: JSONArray): Boolean {
        for (index in 0 until actions.length()) {
            val toolId = actions.optJSONObject(index)
                ?.optJSONObject("parameters")
                ?.optString("tool_id")
            if (toolId == AgentMobileProjectNativeTools.CLONE) return true
        }
        return false
    }

    private val GITHUB_REPOSITORY = Regex(
        "https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\\.git)?",
        RegexOption.IGNORE_CASE
    )
    private val GIT_COMMAND = Regex(
        "(?:^|[;&|()]\\s*|\\b(?:if|then|do|while|exec|command|sudo|env)\\s+)git(?:\\s|$)",
        setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE)
    )
}
