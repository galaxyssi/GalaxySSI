package com.galaxyssi.chat

import org.json.JSONObject

/** Saving evidence and requesting a team decision are separate member-selected actions. */
internal object CollaborationMilestoneCoordination {
    const val INSTRUCTIONS = "For interim publications, set coordination:{\"mode\":\"record_only\"} to preserve logs/data without waking the coordinator. " +
        "When peer input or a team decision is useful now, use coordination:{\"mode\":\"request\",\"decision\":\"specific pending decision\",\"why_now\":\"why coordination can change the next action\"}. " +
        "A request may include milestones:[your previously saved IDs] to share their exact versions without copying or republishing them. " +
        "Choose requests for evidence that affects a decision, a concrete uncertainty or a useful independent check, not every saved file. " +
        "Continue independent work; recording or requesting coordination does not pause your assignment or require approval for each action. " +
        "Final artifacts may request coordination too. Recorded completion follows its pending downstream assignment; " +
        "explicitly request decisions that cannot wait for that assignment. Intermediate publications without coordination still notify. "

    fun read(envelope: JSONObject): JSONObject? {
        if (!envelope.has("coordination")) return null
        val value = requireNotNull(envelope.optJSONObject("coordination")) { "coordination must be an object" }
        val mode = value.opt("mode")
        val keys = value.keys().asSequence().toSet()
        require(mode == "record_only" || mode == "request") { "coordination.mode must be record_only or request" }
        require(keys == if (mode == "record_only") setOf("mode") else setOf("mode", "decision", "why_now")) {
            "coordination record_only accepts only mode; request requires exactly mode, decision and why_now"
        }
        return JSONObject().put("mode", mode).also { normalized ->
            if (mode == "request") listOf("decision", "why_now").forEach { field ->
                val text = value.opt(field) as? String
                require(!text.isNullOrBlank()) { "coordination.$field must be a nonblank string" }
                normalized.put(field, text)
            }
        }
    }

    fun requestsCoordination(envelope: JSONObject) = read(envelope)?.getString("mode") != "record_only"
    fun explicitRequest(envelope: JSONObject) = read(envelope)?.getString("mode") == "request"
}
