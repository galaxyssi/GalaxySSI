package com.galaxyssi.collaboration

import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Projects a validated method into work. Hosts still admit identities, dependencies and permissions. */
object WorkflowMaterializer {
    data class Step(val sourceId: String, val work: JSONObject)

    fun expand(execution: String, steps: List<JSONObject>, roles: JSONObject): List<Step> = steps.map { step ->
        val stepId = step.getString("id")
        Step(stepId, JSONObject(step.toString()).apply {
            remove("role")
            put("id", workId(execution, stepId))
            put("member", roles.getString(step.getString("role")))
            put("depends_on", remap(step.optJSONArray("depends_on") ?: JSONArray(), execution))
            if (step.has("review_targets")) put("review_targets", remap(step.getJSONArray("review_targets"), execution))
        })
    }

    fun workId(execution: String, step: String): String = "workflow:" + UUID.nameUUIDFromBytes(
        JSONArray().put(execution).put(step).toString().toByteArray(Charsets.UTF_8))

    private fun remap(values: JSONArray, execution: String): JSONArray = JSONArray(
        (0 until values.length()).map { values.getString(it).also { id ->
            require(id.isNotBlank()) { "Empty dependency ID" }
        } }.distinct().map { workId(execution, it) })
}
