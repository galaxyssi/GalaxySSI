package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** An agent chooses the curriculum; the host verifies identity, scope and explicit uncertainty. */
internal object CollaborationLearningAgenda {
    const val KIND = "learning_agenda"

    fun validate(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        listOf("goal_alignment", "resource_reasoning", "selection_reason", "reconsider_when").forEach { text(value, it) }
        val options = objects(value, "options")
        require(options.map { text(it, "id") }.distinct().size == options.size) { "Learning option IDs must be unique" }
        val gaps = linkedMapOf<String, JSONObject>()
        val choicesByGap = hashMapOf<String, Pair<JSONObject, Set<String>>>()
        val alternatives = hashSetOf<String>()
        val ranks = hashSetOf<Int>()
        options.forEach { option ->
            val requested = option.getJSONObject("gap")
            require(requested.opt("revision") is Int && requested.getInt("revision") > 0) { "Gap revision must be an exact integer" }
            val (ref, choices) = choicesByGap.getOrPut("${requested.getString("object_id")}:${requested.get("revision")}:${requested.getString("sha256")}") {
                val gap = exact(requested, setOf(CollaborationEvolutionContract.GAP))
                CollaborationResearchCandidates.reference(gap) to objects(gap.getJSONObject("body")
                    .getJSONObject(CollaborationEvolutionContract.GAP), "learning_options").mapTo(hashSetOf()) { it.getString("id") }
            }
            gaps[ref.getString("object_id")] = ref
            val choice = text(option, "gap_option")
            require(choice in choices) { "gap_option must exist in the exact capability gap" }
            require(alternatives.add("${ref.getString("sha256")}:$choice")) { "Compare each gap option once, not under multiple names" }
            require(option.opt("priority") is Int && option.getInt("priority") > 0 && ranks.add(option.getInt("priority"))) {
                "Learning priorities must be distinct positive integer ranks; lower ranks are considered first when ready"
            }
            require(text(option, "decision") in setOf("select", "defer")) { "Learning decision must be select or defer" }
            listOf("current_goal_value", "future_transfer_value", "information_gain", "uncertainty", "tradeoff",
                "verification", "reconsider_when", "member", "assignment").forEach { text(option, it) }
            require(option.getString("assignment").length <= 8000) { "Learning assignment exceeds the existing dispatch context size" }
            require(text(option, "stage") in setOf("EXECUTE", "EXPLORE", "CHALLENGE", "VERIFY", "REVISE")) { "Invalid learning stage" }
            val resources = objects(option, "resource_estimates")
            require(resources.map { text(it, "unit") }.distinct().size == resources.size) { "Duplicate resource estimate units" }
            resources.forEach { estimate ->
                require(text(estimate, "unit") in setOf("elapsed_ms", "tokens", "cost_micros", "network_bytes", "tool_calls")) {
                    "Use explicit resource units"
                }
                val status = text(estimate, "status")
                require(status in setOf("estimated", "unknown")) { "Resource estimates are not host measurements" }
                text(estimate, "basis")
                if (status == "unknown") require(!estimate.has("value") || estimate.isNull("value")) { "Unknown cost is not zero" }
                else require(estimate.opt("value") is Number && estimate.getDouble("value").let { it.isFinite() && it >= 0 }) {
                    "Estimated resource value must be finite and nonnegative"
                }
            }
        }
        return JSONObject().put("state", "learning_selection_proposed").put("gaps", JSONArray(gaps.values.toList()))
            .put("selected", options.count { it.getString("decision") == "select" }).put("deferred", options.count { it.getString("decision") == "defer" })
            .put("values_are_agent_estimates", true).put("grants_resources", false).put("capability_verified", false)
    }

    fun instructions() = """
        Choose learning only when it helps this authorized goal or a concrete reusable capability. Compare multiple available paths,
        including doing no learning now. Publish an immutable learning_agenda with current-goal value, transfer value, information gain,
        uncertainty and cost estimates; unknown cost is not zero. Explain selection and deferral, do not optimize an invented score.
        Use the host resource snapshot and prior learning outcomes. A terminal execution is not evidence that a capability improved.
        After publication, attach learning:{agenda:{object_id,revision,sha256},option_id} to ordinary work items. Copy the selected
        option's member, stage and assignment exactly. Deferred options cannot execute. Lower priority ranks are considered first
        among ready learning work in the same agenda; dependencies, existing resource limits and user controls remain authoritative.
        Use the same stable work ID on recovery. A different learning strategy needs a new linked agenda, not renamed duplicate work.
        Revise choices after actual evidence, changed resources or priorities; do not automatically retry unchanged failures or stop a goal.
    """.trimIndent()

    fun rules() = """
        learning_agenda: {goal_alignment,resource_reasoning,selection_reason,reconsider_when,options:[{id,
          gap:<exact capability_gap ref>,gap_option:"actual gap learning_options id",priority:<positive unique integer>,
          decision:"select|defer",member:"authorized person UUID",stage:"EXECUTE|EXPLORE|CHALLENGE|VERIFY|REVISE",assignment,
          current_goal_value,future_transfer_value,information_gain,uncertainty,tradeoff,verification,reconsider_when,
          resource_estimates:[{unit:"elapsed_ms|tokens|cost_micros|network_bytes|tool_calls",status:"estimated|unknown",
            value:<nonnegative number only when estimated>,basis}]}]}.
        Keep the full compared alternatives, including deferred ones. Rank is chosen by the agent, not a host score.
        All-deferred is valid; it neither creates work nor ends the user's goal. A selected option becomes executable only through
        the existing authorized work graph. Reprioritize by publishing a new agenda linked to the old one in parents.
        Running work is not cancelled or duplicated by a new agenda. Keep actual learning results as probes/experiments/lessons;
        successful execution alone cannot certify improvement. Estimates grant no money, tools, private data or new permissions.
    """.trimIndent()
}
