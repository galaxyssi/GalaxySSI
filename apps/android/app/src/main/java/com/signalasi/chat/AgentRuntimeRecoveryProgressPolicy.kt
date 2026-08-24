package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Prevents a missing runtime dependency from turning into an unchanged command loop. */
internal object AgentRuntimeRecoveryProgressPolicy {
    fun violation(action: AgentAction, history: List<AgentAction>): String? {
        if (action.kind != AgentActionKind.CALL_NATIVE_TOOL ||
            action.toolId() != AgentOnDeviceRuntimeTools.EXECUTE
        ) {
            return null
        }
        val workspaceHistory = history.filter { previous ->
            previous.kind == AgentActionKind.CALL_NATIVE_TOOL &&
                previous.workspaceId() == action.workspaceId()
        }
        val failedIndex = workspaceHistory.indexOfLast { previous ->
            previous.status in unsuccessfulStatuses &&
                previous.toolId() == AgentOnDeviceRuntimeTools.EXECUTE &&
                previous.hasEquivalentInput(action) &&
                previous.missingExecutableFailure() != null
        }
        if (failedIndex < 0) return null

        val failure = requireNotNull(workspaceHistory[failedIndex].missingExecutableFailure())
        if (workspaceHistory.drop(failedIndex + 1).any { it.makesRecoveryProgress(failure) }) {
            return null
        }
        val missing = failure.missingExecutables.joinToString().ifBlank { "the required executable" }
        val actions = failure.recoveryToolIds.joinToString().ifBlank {
            listOf(
                AgentLinuxSoftwareNativeTools.INSTALL,
                AgentLinuxSoftwareNativeTools.SEARCH,
                AgentOnDeviceRuntimeTools.INSTALL_PACK
            ).joinToString()
        }
        return "The equivalent phone Linux command already failed because $missing is unavailable. " +
            "Do not run it unchanged yet. Use a supplied recovery action ($actions), observe the result, " +
            "then retry the blocked command."
    }

    private fun AgentAction.makesRecoveryProgress(failure: MissingExecutableFailure): Boolean {
        if (status != AgentActionStatus.COMPLETED) return false
        val id = toolId()
        if (id in failure.installToolIds || id in knownInstallTools) return true
        if (id != AgentOnDeviceRuntimeTools.EXECUTE) return false
        val source = inputObject().optString("source").trim().lowercase()
        return runtimeInstallMarkers.any(source::contains)
    }

    private fun AgentAction.missingExecutableFailure(): MissingExecutableFailure? {
        val diagnosis = sequenceOf(evidence, result)
            .mapNotNull(::parseObject)
            .mapNotNull(::findFailureDiagnosis)
            .firstOrNull { it.optString("kind") == "missing_executable" }
            ?: return null
        val missing = diagnosis.optJSONArray("missing_executables").stringValues()
        val recovery = diagnosis.optJSONArray("recovery_candidates")
        val recoveryTools = linkedSetOf<String>()
        val installTools = linkedSetOf<String>()
        if (recovery != null) {
            for (index in 0 until recovery.length()) {
                val candidate = recovery.optJSONObject(index) ?: continue
                candidate.keys().forEach { key ->
                    val action = candidate.optJSONObject(key) ?: return@forEach
                    val toolId = action.optString("tool_id").trim()
                    if (toolId.isNotBlank()) {
                        recoveryTools += toolId
                        if ("install" in key.lowercase()) installTools += toolId
                    }
                }
            }
        }
        return MissingExecutableFailure(missing, recoveryTools, installTools)
    }

    private fun findFailureDiagnosis(root: JSONObject): JSONObject? {
        root.optJSONObject("failure_diagnosis")?.let { return it }
        root.optJSONObject("output")?.optJSONObject("failure_diagnosis")?.let { return it }
        root.optJSONObject("native_result")?.let(::findFailureDiagnosis)?.let { return it }
        root.optJSONObject("error")?.optJSONObject("details")
            ?.optJSONObject("failure_diagnosis")?.let { return it }
        return null
    }

    private fun parseObject(raw: String): JSONObject? =
        raw.trim().takeIf(String::isNotBlank)?.let { runCatching { JSONObject(it) }.getOrNull() }

    private fun JSONArray?.stringValues(): List<String> = if (this == null) {
        emptyList()
    } else {
        (0 until length()).mapNotNull { index ->
            optString(index).trim().takeIf(String::isNotBlank)
        }
    }

    private fun AgentAction.toolId(): String = parameters["tool_id"].orEmpty().ifBlank { target }

    private fun AgentAction.workspaceId(): String =
        inputObject().optString("workspace_id").trim().ifBlank { "current" }

    private fun AgentAction.inputObject(): JSONObject =
        parseObject(parameters["input_json"].orEmpty()) ?: JSONObject()

    private fun AgentAction.hasEquivalentInput(other: AgentAction): Boolean =
        canonicalJson(inputObject()) == canonicalJson(other.inputObject())

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

    private data class MissingExecutableFailure(
        val missingExecutables: List<String>,
        val recoveryToolIds: Set<String>,
        val installToolIds: Set<String>
    )

    private val unsuccessfulStatuses = setOf(
        AgentActionStatus.FAILED,
        AgentActionStatus.BLOCKED,
        AgentActionStatus.ROLLED_BACK
    )
    private val knownInstallTools = setOf(
        AgentOnDeviceRuntimeTools.INSTALL_PACK,
        AgentLinuxSoftwareNativeTools.INSTALL
    )
    private val runtimeInstallMarkers = listOf(
        "apt install", "apt-get install", "apk add", "dnf install", "yum install",
        "pacman -s", "pip install", "pip3 install", "uv tool install", "uv pip install",
        "npm install", "pnpm install", "yarn add", "cargo install", "go install"
    )
}
