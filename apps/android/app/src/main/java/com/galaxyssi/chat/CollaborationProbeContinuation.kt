package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationActionPrediction.FORECAST
import com.galaxyssi.chat.CollaborationActionPrediction.MODEL
import com.galaxyssi.chat.CollaborationActionPrediction.OUTCOME
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Prospective result-to-team branches reuse immutable workflows and ordinary task admission. */
internal object CollaborationProbeContinuation {
    const val FIELD = "probe_continuation"
    const val BRANCHES = "continuations"
    const val ORIGIN = "probe_origin"
    const val METHODS = "continuation_methods"

    fun validate(forecast: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONArray? {
        val choices = objects(forecast, "choices")
        if (choices.none { it.has(BRANCHES) }) return null
        val events = objects(forecast, "events").mapTo(hashSetOf()) { it.getString("id") }
        val methods = linkedMapOf<String, JSONObject>()
        choices.filter { it.has(BRANCHES) }.forEach { choice ->
            val branches = objects(choice, BRANCHES)
            require(branches.isNotEmpty() && branches.map { text(it, "id") }.distinct().size == branches.size) {
                "continuations need distinct nonempty branch IDs for each action"
            }
            branches.forEach { branch ->
                require(branch.keys().asSequence().toSet() == setOf("id", "rationale", "when_events", "method", "roles", "inputs", "observed_inputs")) {
                    "A continuation requires id, rationale, when_events, method, roles, inputs and observed_inputs only"
                }
                text(branch, "rationale")
                require(branch.getString("id").length <= 160) { "Continuation branch ID exceeds work ID size" }
                val conditions = branch.getJSONObject("when_events")
                require(conditions.length() > 0 && conditions.keys().asSequence().all { it in events && conditions.opt(it) is Boolean }) {
                    "when_events needs registered event IDs mapped to Boolean occurrence, not predicted confidence"
                }
                val method = exact(branch.getJSONObject("method"), setOf(CollaborationWorkflowMethod.KIND))
                CollaborationInnovationValidation.checkRecord(method, exact)
                methods[method.getString("sha256")] = CollaborationResearchCandidates.reference(method)
                val spec = method.getJSONObject("body").getJSONObject(CollaborationWorkflowMethod.KIND)
                val roles = branch.getJSONObject("roles")
                require(roles.keys().asSequence().toSet() == names(spec, "roles") && roles.keys().asSequence().all {
                    roles.opt(it) is String && roles.getString(it).isNotBlank() && !roles.getString(it).startsWith("recruit:")
                }) { "Continuation roles must bind every saved role to an existing member, not a recruitment alias" }
                val inputs = branch.getJSONObject("inputs")
                val observed = branch.getJSONObject("observed_inputs")
                val declaredNames = inputs.keys().asSequence().toSet()
                val observedNames = observed.keys().asSequence().toSet()
                require(declaredNames.intersect(observedNames).isEmpty() && declaredNames + observedNames == names(spec, "inputs") &&
                    declaredNames.none(inputs::isNull)) { "Continuation inputs must exactly cover the method without overriding observed fields" }
                observedNames.forEach { name ->
                    require(observed.opt(name) is String) { "Continuation observed_inputs.$name must be a pointer in the registered report" }
                    val pointer = observed.getString(name)
                    require((pointer.isEmpty() || pointer.startsWith('/')) && !Regex("~(?![01])").containsMatchIn(pointer)) {
                        "Invalid continuation observed_inputs.$name pointer"
                    }
                }
            }
        }
        return JSONArray(methods.values.toList())
    }

    fun expand(item: JSONObject, workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess,
               milestones: Map<String, JSONObject>): List<JSONObject> {
        require(item.keys().asSequence().toSet() == setOf(FIELD)) { "probe_continuation cannot override executable work" }
        val use = item.getJSONObject(FIELD)
        require(use.keys().asSequence().toSet() == setOf("outcome") + (if (use.has("milestone")) setOf("milestone") else emptySet())) {
            "probe_continuation requires outcome and optional original-observation milestone only"
        }
        val resolution = resolve(use.getJSONObject("outcome"), workspace, access)
        requireSourceAccess(resolution, use, access, milestones)
        require(resolution.matched.isNotEmpty()) {
            "No measured continuation matches; preserve the outcome and replan ordinary work or a new forecast. Branch states: ${decisionSummary(resolution)}. Read the saved forecast and outcome for complete conditions."
        }
        return resolution.matched.map { branch ->
            val binding = origin(resolution, branch, use.opt("milestone"))
            JSONObject().put(CollaborationWorkflowInstantiation.FIELD, instance(resolution, branch, binding))
        }
    }

    class Bindings(private val workspace: CollaborationResearchWorkspace, private val access: CollaborationWorkspaceAccess,
                   private val record: AgentTeamExecutionRecord, private val milestones: Map<String, JSONObject>) {
        private val resolved = hashMapOf<String, Resolution>()
        private val lineageChecked = hashSetOf<String>()
        fun bind(use: JSONObject, method: JSONObject, observed: CollaborationWorkflowObservations.Resolved?, replay: Boolean) =
            binding(use, method, workspace, access, record, observed, milestones, replay, resolved, lineageChecked)
    }

    private fun binding(use: JSONObject, method: JSONObject, workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess,
                record: AgentTeamExecutionRecord, observed: CollaborationWorkflowObservations.Resolved?,
                milestones: Map<String, JSONObject>, replay: Boolean, cache: MutableMap<String, Resolution>, lineageChecked: MutableSet<String>): JSONObject? {
        if (!use.has(ORIGIN)) return null
        val origin = use.getJSONObject(ORIGIN)
        require(origin.keys().asSequence().toSet() == setOf("forecast", "outcome", "branch_id") +
            (if (origin.has("milestone")) setOf("milestone") else emptySet())) { "Unexpected probe_origin field" }
        val outcomeRef = origin.getJSONObject("outcome")
        val key = "${outcomeRef.getString("object_id")}:${outcomeRef.getInt("revision")}:${outcomeRef.getString("sha256")}"
        val result = cache.getOrPut(key) { resolve(outcomeRef, workspace, access) }
        requireSourceAccess(result, origin, access, milestones)
        if (!replay && lineageChecked.add(result.forecast.getString("sha256")))
            CollaborationCapabilityChannel.requireCurrentLineage(result.forecast, workspace, access)
        require(CollaborationResearchCandidates.same(result.forecast, origin.getJSONObject("forecast"))) { "Continuation forecast changed" }
        val spec = result.forecast.getJSONObject("body").getJSONObject(FORECAST)
        val model = read(spec.getJSONObject(MODEL), MODEL, workspace, access).getJSONObject("body").getJSONObject(MODEL)
        require(result.forecast.getString("run_id") == record.request.runId && result.forecast.getString("turn_id") == record.request.messageId &&
            model.getString("goal_sha256") == CollaborationSemanticGoalCoverage.source(record.request.goal).getString("goal_sha256")) {
            "Continuation belongs to another run, turn or goal"
        }
        val criteria = JSONArray(record.request.context[CollaborationGoalLoop.CRITERIA]?.toString() ?: "[]")
        require((0 until criteria.length()).any { criteria.getJSONObject(it).let { criterion ->
            criterion.getString("id") == model.getString("criterion_id") && criterion.getString("requirement") == model.getString("requirement")
        } }) { "Continuation must preserve its original goal criterion" }
        val branch = requireNotNull(result.matchedById[origin.getString("branch_id")]) {
            "Continuation branch is not supported by the original measured outcome"
        }
        val expected = instance(result, branch, origin)
        val expectedInputs = if (observed == null) expected.getJSONObject("inputs") else
            CollaborationWorkflowObservations.combine(expected.getJSONObject("inputs"), observed)
        require(CollaborationResearchCandidates.same(method, expected.getJSONObject("method")) &&
            use.getString("execution_id") == expected.getString("execution_id") &&
            digest(use.getJSONObject("inputs")) == digest(expectedInputs) &&
            digest(use.opt(CollaborationWorkflowObservations.FIELD)) == digest(expected.opt(CollaborationWorkflowObservations.FIELD)) &&
            !use.has(CollaborationWorkflowSelection.FIELD) && !use.has(CollaborationCapabilityChannel.FIELD)) {
            "Continuation must preserve its prospective method, inputs and observation selectors"
        }
        return JSONObject(origin.toString()).put("roles", branch.getJSONObject("roles"))
            .put("conditions", result.statesById.getValue(branch.getString("id")).getJSONArray("conditions"))
            .put("matched_branch_count", result.matched.size)
            .put("selection", "all_matching_measured_branches").put("quality_improved", false)
    }

    private data class Resolution(val forecast: JSONObject, val outcome: JSONObject, val observation: JSONObject, val original: JSONObject,
                                  val matched: List<JSONObject>, val states: JSONArray) {
        val matchedById = matched.associateBy { it.getString("id") }
        val statesById = (0 until states.length()).map(states::getJSONObject).associateBy { it.getString("branch_id") }
    }

    private fun resolve(ref: JSONObject, workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess): Resolution {
        val outcome = read(ref, OUTCOME, workspace, access)
        val host = outcome.getJSONObject(HOST)
        val forecast = read(host.getJSONObject(FORECAST), FORECAST, workspace, access)
        val spec = forecast.getJSONObject("body").getJSONObject(FORECAST)
        val selected = objects(spec, "choices").single { it.getString("action_id") == spec.getString("selected_action") }
        val branches = objects(selected, BRANCHES)
        val checks = objects(host, "checks").associateBy { it.getString("event_id") }
        val refs = checks.values.mapNotNull { it.optJSONObject("observation") }
        require(refs.isNotEmpty() && refs.all { sameObservation(it, refs.first()) }) {
            "Continuation needs one original probe receipt, not missing or spliced experiments"
        }
        val original = workspace.workflowObservation(access, refs.first())
        require(original.getLong("started_at") >= forecast.getLong("recorded_at")) { "Probe observation predates its continuation plan" }
        val states = JSONArray()
        val matched = branches.filter { branch ->
            val conditions = branch.getJSONObject("when_events")
            val rows = conditions.keys().asSequence().map { id ->
                val check = checks[id]
                val state = when {
                    check == null || check.optString("state") != "observed" || !check.optBoolean("within_declared_validity") -> "unknown"
                    check.getBoolean("event_occurred") == conditions.getBoolean(id) -> "matched"
                    else -> "not_matched"
                }
                JSONObject().put("event_id", id).put("state", state)
            }.toList()
            val state = when {
                rows.any { it.getString("state") == "unknown" } -> "unknown"
                rows.all { it.getString("state") == "matched" } -> "matched"
                else -> "not_matched"
            }
            states.put(JSONObject().put("branch_id", branch.getString("id")).put("state", state).put("conditions", JSONArray(rows)))
            state == "matched"
        }
        return Resolution(forecast, outcome, refs.first(), original, matched, states)
    }

    private fun requireSourceAccess(result: Resolution, use: JSONObject, access: CollaborationWorkspaceAccess,
                                    milestones: Map<String, JSONObject>) {
        val neutral = access.copy(nodeId = "", dependencyNodes = emptySet(), pinnedReads = emptySet())
        if (use.has("milestone")) {
            require(use.opt("milestone") is String) { "Continuation milestone must be a host token" }
            val milestone = requireNotNull(milestones[use.getString("milestone")]) { "Continuation milestone is unavailable" }
            require(CollaborationMilestoneDispatch.grant(result.observation) in
                CollaborationMilestoneDispatch.strings(milestone.getJSONArray("grants").toString())) {
                "Continuation milestone must grant its exact original observation"
            }
        } else require(neutral.canRead(result.original)) { "Same-round probe continuation needs an original-observation milestone" }
    }

    private fun instance(result: Resolution, branch: JSONObject, origin: JSONObject): JSONObject {
        val spec = result.forecast.getJSONObject("body").getJSONObject(FORECAST)
        val selectors = JSONObject()
        val pointers = branch.getJSONObject("observed_inputs")
        pointers.keys().forEach { name -> selectors.put(name, JSONObject().put("observation", result.observation)
            .put("report_pointer", spec.getString("report_pointer")).put("pointer", pointers.getString(name))
            .apply { if (origin.has("milestone")) put("milestone", origin.getString("milestone")) }) }
        return JSONObject().put("execution_id", "probe-${AgentNativeJsonCodec.sha256(listOf(result.forecast.getString("sha256"), branch.getString("id")))}")
            .put("method", branch.getJSONObject("method")).put("inputs", branch.getJSONObject("inputs"))
            .put("roles", branch.getJSONObject("roles")).put(ORIGIN, origin)
            .apply { if (selectors.length() > 0) put(CollaborationWorkflowObservations.FIELD, selectors) }
    }

    private fun origin(result: Resolution, branch: JSONObject, milestone: Any?) = JSONObject()
        .put("forecast", CollaborationResearchCandidates.reference(result.forecast))
        .put("outcome", CollaborationResearchCandidates.reference(result.outcome)).put("branch_id", branch.getString("id"))
        .apply { if (milestone != null) { require(milestone is String) { "Continuation milestone must be a host token" }; put("milestone", milestone) } }

    private fun read(ref: JSONObject, kind: String, workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess): JSONObject {
        require(ref.opt("revision") is Int && ref.getInt("revision") > 0) { "Continuation needs an exact revision" }
        val saved = requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))) { "Continuation record unavailable or isolated" }
        require(saved.getString("kind") == kind && CollaborationResearchCandidates.same(saved, ref)) { "Continuation record kind or digest mismatch" }
        return saved
    }

    private fun sameObservation(a: JSONObject, b: JSONObject) = a.getString("evidence_id") == b.getString("evidence_id") && a.getString("sha256") == b.getString("sha256")
    private fun decisionSummary(result: Resolution): JSONObject {
        val rows = result.statesById.values
        val conditions = rows.flatMap { row -> row.getJSONArray("conditions").let { a -> (0 until a.length()).map(a::getJSONObject) } }
        return JSONObject().put("matched", result.matched.size).put("unknown", rows.count { it.getString("state") == "unknown" })
            .put("not_matched", rows.count { it.getString("state") == "not_matched" })
            .put("unresolved_event_ids", JSONArray(conditions.filter { it.getString("state") == "unknown" }.map { it.getString("event_id") }.distinct().sorted()))
            .put("nonmatching_event_ids", JSONArray(conditions.filter { it.getString("state") == "not_matched" }.map { it.getString("event_id") }.distinct().sorted()))
    }
    private fun names(spec: JSONObject, field: String) = spec.getJSONArray(field).let { a -> (0 until a.length()).mapTo(hashSetOf()) { a.getString(it) } }
    private fun digest(value: Any?): String = AgentNativeJsonCodec.sha256(canonical(value))
    private fun canonical(value: Any?): Any? = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { canonical(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { canonical(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }
}
