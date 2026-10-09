package com.galaxyssi.chat

import java.util.Locale
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Checkpoint policy only: identities, authority, running dispatches and goal lifetime are not mutated. */
internal object CollaborationTeamOrganization {
    const val ENABLED = "collaboration_research_organization"
    const val STATE = "collaboration_research_organization_state"
    const val SUBGROUPS = "collaboration_research_organization_subgroups"
    const val SIGNATURES = "collaboration_research_organization_work_signatures"

    fun enabled(record: AgentTeamExecutionRecord) = record.definition.members.any { it.context[ENABLED] == "1" }

    enum class Outcome { SUCCEEDED, FAILED, UNKNOWN }
    data class Observation(
        val dispatchId: String,
        val personId: String,
        val agentId: String,
        val modelId: String,
        val role: String,
        val stage: String,
        val workId: String,
        val signature: String = "",
        val outcome: Outcome = Outcome.UNKNOWN,
        val elapsedMillis: Long? = null,
        val costUsdMicros: Long? = null,
        val provenanceSource: String = ""
    )
    data class InFlight(val personId: String, val workId: String, val signature: String = "")
    data class Checkpoint(
        val coordinatorId: String = "",
        val settled: Boolean = false,
        val inFlight: List<InFlight> = emptyList(),
        val observations: List<Observation> = emptyList(),
        val finishedWork: Set<String> = emptySet(),
        val finishedAuthors: Map<String, String> = emptyMap()
    )
    data class Subgroup(val id: String, val workIds: List<String>, val people: Set<String>)
    data class Decision(
        val people: List<AgentTeamMember>,
        val subgroups: List<Subgroup>,
        val activePeople: Set<String>,
        val standbyPeople: Set<String>,
        val contractionApplied: Boolean
    )

    fun person(member: AgentTeamMember): String = member.context.getValue(CollaborationResearchWorkflow.PERSON)
    private fun role(value: String) = value.trim().lowercase(Locale.ROOT)
    private fun review(item: JSONObject) = item.optBoolean("independent_review") ||
        item.optString("stage") in setOf("VERIFY", "CHALLENGE")

    /** Preserve case and internal whitespace: assignments may contain case-sensitive commands or code. */
    fun signature(item: JSONObject, member: String = item.optString("member")): String =
        UUID.nameUUIDFromBytes(JSONArray().put(item.optString("stage")).put(item.optString("assignment").trim())
            .put(JSONArray(CollaborationWorkGraph.dependencies(item).sorted()))
            .put(item.optString("dependency_policy", "success")).put(item.optBoolean("independent_review"))
            .put(if (review(item)) member else "").apply {
                if (item.has(CollaborationDataDependencies.FIELD))
                    put(JSONObject().put(CollaborationDataDependencies.FIELD,
                        CollaborationDataDependencies.array(CollaborationDataDependencies.read(item))))
                // Preserve existing signatures when all dependencies remain review targets.
                if (item.has(CollaborationReviewTargets.FIELD) &&
                    CollaborationReviewTargets.read(item) != CollaborationWorkGraph.dependencies(item))
                    put(JSONArray(CollaborationReviewTargets.read(item).sorted()))
                val uses = CollaborationMilestoneDispatch.uses(item)
                if (item.has(CollaborationReviewTargets.MILESTONES) && CollaborationReviewTargets.milestones(item) != uses) {
                    put(JSONObject().put(CollaborationMilestoneDispatch.USES, JSONArray(uses.sorted()))
                        .put(CollaborationReviewTargets.MILESTONES, JSONArray(CollaborationReviewTargets.milestones(item).sorted())))
                }
            }.toString().toByteArray(Charsets.UTF_8)).toString()

    fun validateWork(work: List<JSONObject>, checkpoint: Checkpoint) {
        val seen = linkedMapOf<String, String>()
        work.forEach { item ->
            val id = CollaborationWorkGraph.id(item)
            val key = signature(item)
            // In-flight ownership wins even if a stale finished-work ledger also contains this ID.
            val running = checkpoint.inFlight.firstOrNull { it.workId == id || it.signature == key }
            require(running == null) { "Work $id overlaps in-flight work ${running?.workId}; wait for its checkpoint" }
            if (id in checkpoint.finishedWork) return@forEach
            val replication = item.optJSONObject("replication")
            require(!item.has("replication") || replication != null &&
                replication.optString("reason").isNotBlank() && replication.optString("difference").isNotBlank()) {
                "Intentional replication needs a reason and a distinct method, input or evidence source"
            }
            if (replication == null) {
                val duplicate = seen.putIfAbsent(key, id)
                require(duplicate == null) {
                    "Duplicate work $id and $duplicate: reuse one stable work ID and its dependencies, or describe intentional replication"
                }
                val prior = checkpoint.observations.lastOrNull {
                    it.signature == key && it.outcome == Outcome.SUCCEEDED && it.workId != id
                }
                require(prior == null) {
                    "Work $id repeats successful dispatch ${prior?.dispatchId} (work ${prior?.workId}); recall its original, " +
                        "reuse its stable work ID, or describe intentional replication. Dispatch success is not goal acceptance. " +
                        "If preserved criteria changed, that alone does not prove this job has new material inputs. " +
                        "For a mapping-only revision, recall saved artifacts and use work.replication={reason,difference} " +
                        "to identify the old/new host criteria bindings and changed criterion IDs; copy bindings from host context, never invent them. " +
                        "Give only that material revision a new stable work ID and schedule its independent review with target dependencies. " +
                        "Status/evidence updates or cosmetic renaming are not material inputs. " +
                        "Do not rerun completed tool calls or side effects; a replication rationale grants no execution authority."
                }
            }
        }
    }

    fun availableForReuse(member: AgentTeamMember, work: List<JSONObject>, occupied: Set<String>, checkpoint: Checkpoint): Boolean {
        val id = person(member)
        val targetAuthors = work.filter(::review).flatMap { CollaborationWorkGraph.dependencies(it) }
            .mapNotNullTo(hashSetOf()) { checkpoint.finishedAuthors[it] }
        return id !in occupied && id !in targetAuthors && id != checkpoint.coordinatorId &&
            member.deliveryMode != AgentDeliveryMode.RESPOND && checkpoint.inFlight.none { it.personId == id }
    }

    fun reusable(
        people: List<AgentTeamMember>, template: AgentTeamMember, requestedRole: String,
        work: List<JSONObject>, occupied: Set<String>, checkpoint: Checkpoint
    ): AgentTeamMember? {
        val candidates = people.filter {
            availableForReuse(it, work, occupied, checkpoint) &&
                it.context[CollaborationGoalRecruitment.PUBLISHED] != "false" &&
                it.agentId == template.agentId && it.requiredCapabilities == template.requiredCapabilities &&
                it.context["collaboration_group_id"] == template.context["collaboration_group_id"] &&
                it.context["collaboration_model_id"].orEmpty() == template.context["collaboration_model_id"].orEmpty() &&
                role(it.role) == role(requestedRole)
        }
        if (candidates.size < 2) return candidates.firstOrNull()
        val stages = work.map { it.optString("stage") }.toSet()
        if (stages.size != 1) return candidates.first()
        val samples = candidates.associateWith { candidate -> checkpoint.observations.filter {
            it.personId == person(candidate) && it.agentId == candidate.agentId &&
                it.modelId == candidate.context["collaboration_model_id"].orEmpty() && role(it.role) == role(candidate.role) &&
                it.stage in stages
        }.distinctBy { it.dispatchId } }
        // Only comparable, completely observed dimensions can dominate another candidate.
        val outcomesKnown = samples.values.all { it.isNotEmpty() && it.all { sample -> sample.outcome != Outcome.UNKNOWN } }
        val elapsedKnown = samples.values.all { it.isNotEmpty() && it.all { sample -> sample.elapsedMillis?.let { ms -> ms >= 0 } == true } }
        val costsKnown = samples.values.all { it.isNotEmpty() && it.all { sample -> sample.costUsdMicros?.let { cost -> cost >= 0 } == true } }
        fun metrics(member: AgentTeamMember): List<Double> {
            val rows = samples.getValue(member)
            return buildList {
                if (outcomesKnown) add(rows.count { it.outcome == Outcome.FAILED }.toDouble() / rows.size)
                if (elapsedKnown) add(rows.map { it.elapsedMillis!!.toDouble() }.average())
                if (costsKnown) add(rows.map { it.costUsdMicros!!.toDouble() }.average())
            }
        }
        val measured = candidates.associateWith(::metrics)
        return candidates.first { candidate -> candidates.none { alternative ->
            val pairs = measured.getValue(alternative).zip(measured.getValue(candidate))
            pairs.all { (a, b) -> a <= b } && pairs.any { (a, b) -> a < b }
        } }
    }

    fun allocate(people: List<AgentTeamMember>, work: List<JSONObject>, checkpoint: Checkpoint): Decision {
        val pending = work.filter { CollaborationWorkGraph.id(it) !in checkpoint.finishedWork }
        val byId = pending.associateBy(CollaborationWorkGraph::id)
        val neighbors = byId.keys.associateWith { linkedSetOf<String>() }
        pending.forEach { item -> CollaborationWorkGraph.dependencies(item).filter { it in byId }.forEach { dependency ->
            neighbors.getValue(CollaborationWorkGraph.id(item)).add(dependency)
            neighbors.getValue(dependency).add(CollaborationWorkGraph.id(item))
        } }
        val unseen = byId.keys.toMutableSet()
        val groups = mutableListOf<Subgroup>()
        while (unseen.isNotEmpty()) {
            val queue = java.util.ArrayDeque<String>()
            queue.add(unseen.first())
            val ids = linkedSetOf<String>()
            while (queue.isNotEmpty()) {
                val id = queue.removeFirst()
                if (!unseen.remove(id)) continue
                ids.add(id)
                neighbors.getValue(id).forEach(queue::addLast)
            }
            val sorted = ids.sorted()
            groups += Subgroup(UUID.nameUUIDFromBytes(JSONArray(sorted).toString().toByteArray(Charsets.UTF_8)).toString(),
                sorted, ids.mapTo(linkedSetOf()) { byId.getValue(it).getString("member") })
        }
        val active = pending.mapTo(linkedSetOf()) { it.getString("member") }
        checkpoint.inFlight.mapTo(active) { it.personId }
        checkpoint.coordinatorId.takeIf(String::isNotBlank)?.let(active::add)
        people.filter { it.deliveryMode == AgentDeliveryMode.RESPOND }.mapTo(active, ::person)
        val canContract = checkpoint.settled && checkpoint.inFlight.isEmpty() && checkpoint.coordinatorId.isNotBlank() &&
            people.any { person(it) == checkpoint.coordinatorId }
        val standby = if (canContract) people.mapTo(linkedSetOf(), ::person) - active else emptySet()
        val annotated = people.map { member ->
            val id = person(member)
            val assigned = pending.filter { it.optString("member") == id }
            val signatures = JSONObject().apply { assigned.forEach { put(CollaborationWorkGraph.id(it), signature(it)) } }
            val state = when {
                id in active -> "active"
                id in standby -> "standby"
                else -> member.context[STATE] ?: "retained"
            }
            member.copy(context = member.context + mapOf(STATE to state,
                SUBGROUPS to JSONArray(groups.filter { id in it.people }.map { it.id }).toString(),
                SIGNATURES to signatures.toString()))
        }
        return Decision(annotated, groups, active, standby, canContract)
    }
}
