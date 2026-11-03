package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationActionPrediction.FORECAST
import com.galaxyssi.chat.CollaborationActionPrediction.MODEL
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Immutable forecast-to-work admission in the existing scheduler; no extra executor or retries. */
internal object CollaborationPredictionWork {
    const val TASK = "collaboration_prediction_task"
    const val CLAIMS = "collaboration_prediction_claims"
    const val OUTCOMES = "collaboration_prediction_outcomes"
    private const val BINDING = "host_prediction_work"
    data class Plan(val work: List<JSONObject>, val claims: String)

    fun plan(record: AgentTeamExecutionRecord, requested: List<JSONObject>, provider: (() -> CollaborationResearchWorkspace)?,
             access: CollaborationWorkspaceAccess, criteria: JSONArray? = null, now: Long = System.currentTimeMillis()): Plan {
        val prior = record.request.context[CLAIMS]?.toString() ?: "{}"
        if (prior == "{}" && requested.none { it.has("prediction_work") || it.has(BINDING) }) return Plan(requested, prior)
        val claims = JSONObject(prior)
        val workspace by lazy { requireNotNull(provider?.invoke()) { "Prediction workspace unavailable; preserve work for recovery" } }
        val cache = hashMapOf<String, JSONObject>()
        fun exact(ref: JSONObject, kinds: Set<String>): JSONObject {
            require(ref.opt("revision") is Int && ref.getInt("revision") > 0) { "Prediction revision must be an exact integer" }
            val key = "${ref.getString("object_id")}:${ref.getInt("revision")}:${ref.getString("sha256")}"
            val saved = cache.getOrPut(key) { requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))) { "Prediction source unavailable or isolated" } }
            require(saved.getString("kind") in kinds && CollaborationResearchCandidates.same(saved, ref) &&
                workspace.isCurrent(access, ref.getString("object_id"), ref.getInt("revision"))) { "Prediction source changed; refresh the forecast before dispatch" }
            return saved
        }
        val work = requested.map { original ->
            require(!original.has(BINDING)) { "Prediction binding is host-owned" }
            val item = JSONObject(original.toString())
            val id = CollaborationWorkGraph.id(item)
            val old = claims.optJSONObject(id)
            if (!item.has("prediction_work")) {
                require(old == null) { "Cannot remove an admitted prediction binding" }
                return@map item
            }
            val forecast = exact(item.getJSONObject("prediction_work").getJSONObject("forecast"), setOf(FORECAST))
            CollaborationInnovationValidation.checkRecord(forecast, ::exact)
            val spec = forecast.getJSONObject("body").getJSONObject(FORECAST)
            val model = exact(spec.getJSONObject(MODEL), setOf(MODEL))
            val environment = model.getJSONObject("body").getJSONObject(MODEL)
            require(forecast.getString("run_id") == record.request.runId && forecast.getString("turn_id") == record.request.messageId &&
                spec.getString("work_id") == id && spec.getString("executor") == text(item, "member")) { "Forecast is bound to another run/turn/work/member" }
            require(old != null || now <= spec.getLong("valid_until")) { "Forecast environment validity expired; refresh assumptions instead of dispatching stale work" }
            require(environment.getString("goal_sha256") == CollaborationSemanticGoalCoverage.source(record.request.goal).getString("goal_sha256")) { "Forecast model belongs to another goal" }
            val contract = criteria ?: JSONArray(record.request.context[CollaborationGoalLoop.CRITERIA]?.toString() ?: "[]")
            val criterion = (0 until contract.length()).map(contract::getJSONObject).singleOrNull {
                it.getString("id") == environment.getString("criterion_id") && it.getString("requirement") == environment.getString("requirement")
            }
            requireNotNull(criterion) { "Prediction work must preserve the original goal criterion" }
            val requirement = JSONObject(criterion.toString()).apply { remove("status"); remove("evidence") }
            val binding = JSONObject().put("forecast", CollaborationResearchCandidates.reference(forecast)).put("model", CollaborationResearchCandidates.reference(model))
                .put("selected_action", spec.getString("selected_action")).put("action", CollaborationEvolutionContract.objects(environment, "actions")
                    .single { it.getString("id") == spec.getString("selected_action") })
                .put("comparisons", forecast.getJSONObject("host_evolution").getJSONArray("comparisons"))
                .put("valid_until", spec.getLong("valid_until")).put("revalidate_before_action", spec.getString("revalidate_before_action"))
                .put("valid_when", environment.getString("valid_when")).put("refresh_when", environment.getString("refresh_when"))
                .put("work_id", id).put("member", item.getString("member")).put("stage", text(item, "stage")).put("assignment", text(item, "assignment"))
                .put("criterion", requirement).put("grants_permissions", false).put("outcome_verified", false)
            if (CollaborationQualitativePrediction.enabled(spec)) binding.put(CollaborationQualitativePrediction.MODE, CollaborationQualitativePrediction.QUALITATIVE)
            forecast.getJSONObject("host_evolution").optJSONObject(CollaborationHypothesisTest.FIELD)?.let {
                binding.put(CollaborationHypothesisTest.FIELD, JSONObject(it.toString()))
            }
            val digest = AgentNativeJsonCodec.sha256(canonical(binding))
            require(old == null || old.getString("sha256") == digest) { "Cannot rewrite admitted prediction work; preserve it and plan a new forecast/work ID" }
            claims.put(id, JSONObject().put("sha256", digest).put("forecast", CollaborationResearchCandidates.reference(forecast)))
            item.put(BINDING, binding)
        }
        return Plan(work, claims.toString())
    }

    fun context(item: JSONObject): Map<String, String> = item.optJSONObject(BINDING)?.let { mapOf(TASK to it.toString()) } ?: emptyMap()
    private fun canonical(value: Any?): Any? = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { canonical(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { canonical(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }

    fun capture(record: AgentTeamExecutionRecord, results: Collection<AgentSubagentChildResult>): String {
        val prior = record.request.context[OUTCOMES]?.toString() ?: "{}"
        val members = record.definition.members.filter { TASK in it.context }.associateBy { it.memberId }
        if (members.isEmpty()) return prior
        val outcomes = JSONObject(prior)
        results.filter { it.childId in members && it.supervisorId == record.request.runId && it.status.isTerminal }.forEach { result ->
            if (outcomes.has(result.childId)) return@forEach
            outcomes.put(result.childId, JSONObject().put("node_id", result.childId).put("binding", JSONObject(members.getValue(result.childId).context.getValue(TASK)))
                .put("status", result.status.name.lowercase()).put("completed_at", result.completedAtMillis)
                .put("output_sha256", AgentNativeJsonCodec.sha256(result.output)).put("output_truncated", result.outputTruncated)
                .put("prediction_verified", false))
        }
        return outcomes.toString()
    }
}
