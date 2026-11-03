package com.galaxyssi.chat

import org.json.JSONObject

/** Admission is committed with the existing DAG. It does not run models or maintain another queue. */
internal object CollaborationLearningWork {
    const val TASK = "collaboration_research_learning_task"
    const val CLAIMS = "collaboration_research_learning_claims"
    private const val HOST = "host_learning"
    data class Plan(val work: List<JSONObject>, val claims: String)
    private data class Saved(val record: JSONObject, val options: Map<String, JSONObject>)

    fun plan(record: AgentTeamExecutionRecord, requested: List<JSONObject>,
             workspaceProvider: (() -> CollaborationResearchWorkspace)?, access: CollaborationWorkspaceAccess): Plan {
        val prior = record.request.context[CLAIMS]?.toString() ?: "{}"
        if (requested.none { it.has("learning") || it.has(HOST) } && prior == "{}") return Plan(requested, prior)
        val claims = JSONObject(prior)
        val bindings = claims.keys().asSequence().associateBy { claims.getJSONObject(it).getString("key") }.toMutableMap()
        val workspace by lazy { requireNotNull(workspaceProvider?.invoke()) { "Learning workspace unavailable; preserve selection and repair later" } }
        val agendas = hashMapOf<String, Saved>()
        val checkedGaps = hashSetOf<String>()
        val work = requested.map { original ->
            require(!original.has(HOST)) { "Learning admission metadata is host-owned" }
            val item = JSONObject(original.toString())
            val id = CollaborationWorkGraph.id(item)
            val old = claims.optJSONObject(id)
            if (!item.has("learning")) {
                require(old == null) { "Cannot remove an existing learning binding from work $id" }
                return@map item
            }
            val learning = item.getJSONObject("learning")
            val ref = learning.getJSONObject("agenda")
            require(ref.opt("revision") is Int && ref.getInt("revision") > 0) { "Learning agenda revision must be an exact integer" }
            val objectId = ref.getString("object_id")
            val hash = ref.getString("sha256")
            val saved = agendas.getOrPut("$objectId:${ref.getInt("revision")}:$hash") {
                val record = requireNotNull(workspace.read(access, objectId, ref.getInt("revision"))) { "Learning agenda missing or isolated" }.also {
                    require(it.getString("kind") == CollaborationLearningAgenda.KIND && CollaborationResearchCandidates.same(it, ref)) {
                        "Learning agenda kind or digest mismatch"
                    }
                    require(workspace.isCurrent(access, objectId, ref.getInt("revision"))) { "Learning agenda changed" }
                }
                Saved(record, CollaborationEvolutionContract.objects(record.getJSONObject("body")
                    .getJSONObject(CollaborationLearningAgenda.KIND), "options").associateBy { it.getString("id") })
            }
            val agenda = saved.record
            val optionId = learning.getString("option_id")
            val option = requireNotNull(saved.options[optionId]) {
                "Unknown learning option"
            }
            require(option.getString("decision") == "select") { "Deferred learning cannot be dispatched" }
            require(listOf("member", "stage", "assignment").all { item.getString(it) == option.getString(it) }) {
                "Learning work must match the saved member, stage and assignment"
            }
            val gapRef = option.getJSONObject("gap")
            if (checkedGaps.add("${gapRef.getString("object_id")}:${gapRef.getInt("revision")}:${gapRef.getString("sha256")}")) {
                val gap = requireNotNull(workspace.read(access, gapRef.getString("object_id"), gapRef.getInt("revision"))) {
                    "Selected learning gap is unavailable"
                }
                require(CollaborationResearchCandidates.same(gap, gapRef) && workspace.isCurrent(access, gapRef.getString("object_id"), gapRef.getInt("revision"))) {
                    "Learning gap changed; reconsider the selection against its current evidence"
                }
            }
            val key = "$hash:$optionId"
            require(bindings[key]?.let { it == id } != false) { "Learning selection already assigned to work ${bindings[key]}; do not rename it" }
            require(old?.getString("key")?.let { it == key } != false) { "Cannot rewrite an admitted learning selection" }
            val binding = JSONObject().put("key", key).put("agenda", CollaborationResearchCandidates.reference(agenda))
                .put("option_id", optionId).put("priority", option.getInt("priority")).put("member", option.getString("member"))
                .put("gap", gapRef).put("verification", option.getString("verification"))
                .put("resource_estimates", option.getJSONArray("resource_estimates"))
                .put("capability_verified", false)
            claims.put(id, binding)
            bindings[key] = id
            item.put(HOST, binding)
        }
        return Plan(work, claims.toString())
    }

    fun context(item: JSONObject): Map<String, String> = item.optJSONObject(HOST)?.let { mapOf(TASK to it.toString()) } ?: emptyMap()

    /** Sort only slots occupied by one agenda; unrelated work and dependency scheduling retain their order. */
    fun ordered(members: List<AgentTeamMember>): List<AgentTeamMember> {
        if (members.none { TASK in it.context }) return members
        val indexed = members.mapIndexedNotNull { index, member -> member.context[TASK]?.let { raw ->
            Triple(index, member, JSONObject(raw))
        } }.groupBy { it.third.getJSONObject("agenda").getString("sha256") }
        val result = members.toMutableList()
        indexed.values.forEach { group ->
            val sorted = group.sortedBy { it.third.getInt("priority") }
            group.forEachIndexed { i, value -> result[value.first] = sorted[i].second }
        }
        return result
    }
}
