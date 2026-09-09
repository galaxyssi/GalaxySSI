package com.galaxyssi.chat

import org.json.JSONObject

enum class AgentPublicationRequirement(val wireValue: String) {
    NONE("none"), COMMIT("commit"), PUSH("push"), PULL_REQUEST("pull_request")
}

/** Model-declared goal requirements, not inferred from words in the user's message. */
data class AgentCompletionRequirements(
    val publication: AgentPublicationRequirement,
    val phoneLinux: Boolean,
    val reason: String = ""
) {
    fun toJson(): JSONObject = JSONObject()
        .put("publication", publication.wireValue)
        .put("phone_linux", phoneLinux)
        .put("reason", reason)

    fun changesOutcome(previous: AgentCompletionRequirements): Boolean =
        publication != previous.publication || phoneLinux != previous.phoneLinux

    fun canReplace(previous: AgentCompletionRequirements?): Boolean =
        previous == null || !changesOutcome(previous) || reason.isNotBlank()

    companion object {
        fun parse(json: JSONObject?): AgentCompletionRequirements? {
            if (json == null) return null
            val publication = AgentPublicationRequirement.entries.firstOrNull {
                it.wireValue == json.opt("publication")
            } ?: return null
            val phoneLinux = json.opt("phone_linux") as? Boolean ?: return null
            val reason = if (json.has("reason")) json.opt("reason") as? String ?: return null else ""
            if (reason.length > 1_000) return null
            return AgentCompletionRequirements(publication, phoneLinux, reason.trim())
        }
    }
}
