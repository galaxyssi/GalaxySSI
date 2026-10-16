package com.galaxyssi.chat

import org.json.JSONObject

/** Checks exported tool receipts, never a model's claim that a file exists. */
internal object AgentArtifactCompletionEvidence {
    fun missing(requirements: List<AgentArtifactRequirement>, history: List<AgentAction>): List<String> {
        if (requirements.isEmpty()) return emptyList()
        val exported = linkedMapOf<String, JSONObject>()
        history.filter { it.kind == AgentActionKind.CALL_NATIVE_TOOL && it.status == AgentActionStatus.COMPLETED }
            .forEach { action ->
                val receipt = runCatching { JSONObject(action.evidence) }.getOrNull() ?: return@forEach
                if (receipt.has("exit_code") && receipt.optInt("exit_code", -1) != 0) return@forEach
                val artifacts = receipt.optJSONArray("artifacts") ?: return@forEach
                for (index in 0 until artifacts.length()) {
                    val artifact = artifacts.optJSONObject(index) ?: continue
                    exported[artifact.optString("relative_path")] = artifact
                }
            }
        return requirements.mapNotNull { requirement ->
            val artifact = exported[requirement.path]
            val digest = artifact?.optString("sha256").orEmpty()
            val inspection = artifact?.optJSONObject("openability")
            when {
                artifact == null || !digest.matches(Regex("[a-fA-F0-9]{64}")) || artifact.optLong("size_bytes", -1) < 0 ->
                    "an exported, hash-verified artifact receipt for ${requirement.path}; export this file individually if it was bundled in an archive"
                requirement.sourceSha256.isNotBlank() && digest.equals(requirement.sourceSha256, ignoreCase = true) ->
                    "${requirement.path} is unchanged from the declared pre-edit source; copying the original does not satisfy a requested transformation. " +
                        "source_sha256 is not an output checksum. If the user requested a new file or unchanged download and you mistakenly declared its output hash as the source, " +
                        "correct source_sha256 to empty with an explicit completion_requirements.reason. Otherwise perform and verify the requested edit. Never change correct content just to produce a different hash."
                inspection?.optString("status") != "verified" || !digest.equals(inspection?.optString("sha256"), ignoreCase = true) ->
                    "a host-owned, hash-bound openability check for ${requirement.path}; inspect or repair the file and export again. " +
                        "Current observation: ${inspection?.optString("detail").orEmpty().take(240)}"
                else -> null
            }
        }
    }
}
