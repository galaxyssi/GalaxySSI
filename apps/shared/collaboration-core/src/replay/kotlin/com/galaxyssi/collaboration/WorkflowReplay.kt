package com.galaxyssi.collaboration

import org.json.JSONArray
import org.json.JSONObject

/** Local fixture adapter, never a workspace authorization or scientific validation service. */
object WorkflowReplay {
    fun evaluate(request: JSONObject): JSONObject {
        val rule = request.getJSONObject("rule")
        val inputs = JSONObject(request.getJSONObject("inputs").toString())
        request.optJSONObject("observed_inputs")?.let { selectors ->
            selectors.keys().forEach { name ->
                require(!inputs.has(name)) { "Input $name is both declared and observed" }
                val selector = selectors.getJSONObject(name)
                val ref = selector.getJSONObject("observation")
                val fixture = request.getJSONObject("observations").getJSONObject(ref.getString("evidence_id"))
                require(fixture.getString("sha256") == ref.getString("sha256")) { "Fixture observation digest differs" }
                inputs.put(name, ObservationProjection.select(JSONObject(fixture.getString("output_json")),
                    selector.optString("report_pointer"), selector.getString("pointer")))
            }
        }
        val decision = ConditionalWorkflow.choose(rule.getJSONArray("when_all"), rule.getJSONArray("unless_any"), inputs)
        val method = request.getJSONObject("methods").getJSONObject(decision.variant)
        val steps = method.getJSONArray("steps")
        val work = WorkflowMaterializer.expand(request.getString("execution_id"),
            (0 until steps.length()).map(steps::getJSONObject), request.getJSONObject("roles"))
        fun rows(values: List<ConditionalWorkflow.ConditionResult>) = JSONArray(values.map {
            JSONObject().put("condition_id", it.id).put("state", it.state)
        })
        return JSONObject().put("schema", "galaxyssi.workflow-replay.v1")
            .put("variant", decision.variant).put("reason", decision.reason)
            .put("when_all", rows(decision.whenAll)).put("unless_any", rows(decision.unlessAny))
            .put("work", JSONArray(work.map { it.work }))
            .put("execution_performed", false).put("host_admission_performed", false)
            .put("observation_ledger_verified", false)
            .put("quality_effect", JSONObject.NULL).put("causality_proven", false)
    }
}

fun main() {
    val request = JSONObject(System.`in`.bufferedReader(Charsets.UTF_8).readText())
    println(WorkflowReplay.evaluate(request).toString())
}
