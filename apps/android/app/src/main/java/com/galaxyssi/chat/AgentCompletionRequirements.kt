package com.galaxyssi.chat

import org.json.JSONObject
import org.json.JSONArray

data class AgentArtifactRequirement(val path: String, val sourceSha256: String = "") {
    fun toJson(): JSONObject = JSONObject().put("path", path).put("source_sha256", sourceSha256)

    companion object {
        fun parse(value: JSONObject): AgentArtifactRequirement? {
            val path = value.opt("path") as? String ?: return null
            val source = if (value.has("source_sha256")) value.opt("source_sha256") as? String ?: return null else ""
            if (path.isBlank() || path.length > 4096 || path.startsWith('/') || '\\' in path || ':' in path ||
                path.split('/').any { it == ".." || it == "." } || path.any { it.code < 32 }) return null
            if (source.isNotEmpty() && !source.matches(Regex("[a-fA-F0-9]{64}"))) return null
            return AgentArtifactRequirement(path, source.lowercase(java.util.Locale.ROOT))
        }
    }
}

enum class AgentPublicationRequirement(val wireValue: String) {
    NONE("none"), COMMIT("commit"), PUSH("push"), PULL_REQUEST("pull_request")
}

/** Model-declared goal requirements, not inferred from words in the user's message. */
data class AgentCompletionRequirements(
    val publication: AgentPublicationRequirement,
    val phoneLinux: Boolean,
    val reason: String = "",
    val artifacts: List<AgentArtifactRequirement> = emptyList(),
    val outcomes: List<AgentObservedOutcome> = emptyList()
) {
    fun toJson(): JSONObject = JSONObject()
        .put("publication", publication.wireValue)
        .put("phone_linux", phoneLinux)
        .put("reason", reason)
        .put("artifacts", JSONArray(artifacts.map(AgentArtifactRequirement::toJson)))
        .put("outcomes", JSONArray(outcomes.map(AgentObservedOutcome::toJson)))

    fun changesOutcome(previous: AgentCompletionRequirements): Boolean =
        publication != previous.publication || phoneLinux != previous.phoneLinux || artifacts != previous.artifacts || outcomes != previous.outcomes

    fun canReplace(previous: AgentCompletionRequirements?): Boolean =
        previous == null || outcomes.map { it.id }.containsAll(previous.outcomes.map { it.id }) &&
            (!changesOutcome(previous) || reason.isNotBlank())

    companion object {
        fun parse(json: JSONObject?): AgentCompletionRequirements? {
            if (json == null) return null
            val publication = AgentPublicationRequirement.entries.firstOrNull {
                it.wireValue == json.opt("publication")
            } ?: return null
            val phoneLinux = json.opt("phone_linux") as? Boolean ?: return null
            val reason = if (json.has("reason")) json.opt("reason") as? String ?: return null else ""
            if (reason.length > 1_000) return null
            val artifacts = mutableListOf<AgentArtifactRequirement>()
            if (json.has("artifacts")) {
                val array = json.optJSONArray("artifacts") ?: return null
                for (index in 0 until array.length()) {
                    artifacts += AgentArtifactRequirement.parse(array.optJSONObject(index) ?: return null) ?: return null
                }
                if (artifacts.map { it.path }.distinct().size != artifacts.size) return null
            }
            val outcomes = mutableListOf<AgentObservedOutcome>()
            if (json.has("outcomes")) {
                val array = json.optJSONArray("outcomes") ?: return null
                for (index in 0 until array.length()) outcomes += AgentObservedOutcome.parse(array.optJSONObject(index) ?: return null) ?: return null
                if (outcomes.map { it.id }.distinct().size != outcomes.size) return null
            }
            return AgentCompletionRequirements(publication, phoneLinux, reason.trim(), artifacts, outcomes)
        }
    }
}
