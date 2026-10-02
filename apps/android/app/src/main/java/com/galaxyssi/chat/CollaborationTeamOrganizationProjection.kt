package com.galaxyssi.chat

import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject

/** Pure host projection. Generation and authority inputs must come from durable host state, never model JSON. */
internal object CollaborationTeamOrganizationProjection {
    const val COMPLETIONS = "collaboration_research_organization_completion_owners"
    const val OWNERSHIP = "collaboration_research_organization_ownership"
    data class Scope(val runId: String, val teamId: String, val groupId: String, val conversationId: String, val turnId: String)
    data class OwnerKey(val runId: String, val dispatchId: String, val generation: Long)
    data class Authority(val scopeId: String, val revision: Long, val permissionsDigest: String)
    data class Binding(val member: AgentTeamMember, val generation: Long, val authority: Authority? = null,
                       val independentReview: Boolean? = null) {
        val workId: String get() = member.context[CollaborationGoalLoop.WORK_ID].orEmpty()
        val personId: String get() = CollaborationTeamOrganization.person(member)
        fun key(scope: Scope) = OwnerKey(scope.runId, member.memberId, generation)
    }
    data class Ownership(val generation: Long, val bindings: List<Binding>, val retired: Set<OwnerKey> = emptySet())
    data class HostEvent(val generation: Long, val event: AgentSubagentEvent)
    data class Receipt(val owner: OwnerKey, val personId: String, val sequence: Long, val resultDigest: String)
    data class Ledger(val finishedWork: Set<String> = emptySet(), val finishedAuthors: Map<String, String> = emptyMap(),
                      val receipts: Map<String, Receipt> = emptyMap())
    data class Projection(
        val scope: Scope, val ownership: Ownership, val ledger: Ledger,
        val active: List<Binding>, val verifiedResults: Map<String, AgentSubagentChildResult>,
        val latestResults: Map<String, AgentSubagentChildResult>, val terminal: AgentSubagentRunStatus?,
        val conflicts: Set<String>
    ) {
        val safeToApply: Boolean get() = conflicts.isEmpty()
        val settled: Boolean get() = safeToApply && terminal != null && terminal != AgentSubagentRunStatus.CANCELLED && active.isEmpty()
        val finishedWork: Set<String> get() = ledger.finishedWork
        val finishedAuthors: Map<String, String> get() = ledger.finishedAuthors
    }

    fun scope(record: AgentTeamExecutionRecord): Scope {
        val groups = record.definition.members.map { it.context["collaboration_group_id"].orEmpty() }.toSet()
        require(groups.size == 1 && groups.single().isNotBlank()) { "Organization observations require one collaboration group on every member" }
        return Scope(record.request.runId, record.definition.teamId, groups.single(), record.request.conversationId, record.request.messageId)
    }

    /** Compatibility only for immutable pre-generation dispatch IDs; never use after an ownership replacement. */
    fun legacy(record: AgentTeamExecutionRecord): Projection {
        require(!record.request.context.containsKey(OWNERSHIP)) { "Restore explicit host ownership; generation-aware records cannot use the legacy adapter" }
        val scope = scope(record)
        val ledger = readLedger(record)
        require(ledger.receipts.values.all { it.owner.generation == 0L }) { "Restore explicit host ownership before projecting generation-aware history" }
        return project(scope, Ownership(0, record.definition.members.filter { it.deliveryMode != AgentDeliveryMode.IGNORE }.map { Binding(it, 0) }),
            record.events.map { HostEvent(0, it) }, ledger)
    }

    fun current(record: AgentTeamExecutionRecord): Projection = legacy(record)

    fun project(scope: Scope, ownership: Ownership, events: List<HostEvent>, saved: Ledger = Ledger()): Projection {
        require(scope.runId.isNotBlank() && scope.teamId.isNotBlank() && scope.groupId.isNotBlank())
        require(ownership.generation >= 0 && ownership.bindings.all { it.generation in 0..ownership.generation &&
            it.member.memberId.isNotBlank() && it.personId.isNotBlank() && it.member.deliveryMode != AgentDeliveryMode.IGNORE &&
            it.member.context["collaboration_group_id"] == scope.groupId && it.key(scope) !in ownership.retired })
        require(ownership.retired.all { it.runId == scope.runId && it.dispatchId.isNotBlank() && it.generation in 0..ownership.generation })
        require(ownership.bindings.map { it.member.memberId }.distinct().size == ownership.bindings.size) { "One current binding per dispatch" }
        val workIds = ownership.bindings.map { it.workId }.filter(String::isNotBlank)
        require(workIds.distinct().size == workIds.size) { "One current owner per work ID" }
        require(saved.finishedWork.all(String::isNotBlank) && saved.finishedAuthors.keys.all { it in saved.finishedWork } &&
            saved.finishedAuthors.values.all(String::isNotBlank) && saved.receipts.keys.all { it in saved.finishedWork })
        require(saved.receipts.all { (work, receipt) -> receipt.owner.runId == scope.runId && receipt.owner.dispatchId.isNotBlank() &&
            receipt.owner.generation >= 0 && receipt.sequence > 0 && receipt.resultDigest.matches(Regex("[0-9a-f]{64}")) &&
            saved.finishedAuthors[work] == receipt.personId }) { "Invalid host completion receipt" }
        val finished = saved.finishedWork.toMutableSet()
        val authors = saved.finishedAuthors.toMutableMap()
        val receipts = saved.receipts.toMutableMap()
        val active = mutableListOf<Binding>()
        val verified = linkedMapOf<String, AgentSubagentChildResult>()
        val latestResults = linkedMapOf<String, AgentSubagentChildResult>()
        val conflicts = linkedSetOf<String>()
        val scoped = events.filter { it.event.supervisorId == scope.runId && it.event.sequence > 0 }
        val byDispatch = scoped.groupBy { it.event.childId }
        ownership.bindings.forEach { binding ->
            val id = binding.member.memberId
            val rows = byDispatch[id].orEmpty().filter { it.generation == binding.generation &&
                (it.event.childStatus != null || it.event.result != null) }.map { it.event }.distinct()
            val sequence = rows.maxOfOrNull { it.sequence }
            val newest = rows.filter { it.sequence == sequence }
            val event = newest.firstOrNull()
            val receipt = saved.receipts[binding.workId]
            // Conflicting replay is uncertainty, not a new worker, success, failure or replacement signal.
            var conflict = newest.map { it.childStatus to it.result }.distinct().size > 1 ||
                rows.mapNotNull { envelopeResult(scope, binding, it)?.takeIf { result -> result.status.isTerminal &&
                    hasHostProvenance(scope, binding.member, result) } }.map(::resultDigest).distinct().size > 1
            val result = event?.let { envelopeResult(scope, binding, it) }
            val trusted = result?.takeIf { it.status.isTerminal && hasHostProvenance(scope, binding.member, it) }
            if (receipt != null) {
                conflict = conflict || receipt.owner != binding.key(scope) || receipt.personId != binding.personId ||
                    trusted?.let { it.status != AgentSubagentStatus.SUCCEEDED || resultDigest(it) != receipt.resultDigest } == true ||
                    (event != null && event.sequence > receipt.sequence && trusted == null)
            }
            if (conflict) conflicts += id
            if (!conflict && result != null) latestResults[id] = result
            if (!conflict && trusted != null) {
                verified[id] = trusted
                if (trusted.status == AgentSubagentStatus.SUCCEEDED && binding.workId.isNotBlank() && binding.workId !in finished) {
                    finished += binding.workId
                    authors[binding.workId] = binding.personId
                    receipts[binding.workId] = Receipt(binding.key(scope), binding.personId, requireNotNull(event).sequence, resultDigest(trusted))
                }
            }
            val savedTerminal = receipt != null && receipt.owner == binding.key(scope) && (sequence == null || sequence <= receipt.sequence)
            if (conflict || trusted == null && !savedTerminal) active += binding
        }
        val markers = byDispatch[""].orEmpty().filter { it.generation == ownership.generation &&
            it.event.runStatus != null && it.event.result == null }.map { it.event }
        val markerSequence = markers.maxOfOrNull { it.sequence }
        val newestMarkers = markers.filter { it.sequence == markerSequence }
        val statuses = newestMarkers.mapNotNull { it.runStatus }.distinct()
        if (statuses.size > 1) conflicts += "supervisor"
        return Projection(scope, ownership, Ledger(finished, authors, receipts), active, verified, latestResults,
            statuses.singleOrNull(), conflicts)
    }

    private fun envelopeResult(scope: Scope, binding: Binding, event: AgentSubagentEvent): AgentSubagentChildResult? =
        event.result?.takeIf { it.supervisorId == scope.runId && it.childId == binding.member.memberId &&
            it.childId == event.childId && it.parentId == scope.runId && it.depth == 1 &&
            (event.childStatus == null || event.childStatus == it.status) }

    fun hasHostProvenance(scope: Scope, member: AgentTeamMember, result: AgentSubagentChildResult): Boolean {
        val provenance = result.provenance
        if (provenance.traceId != scope.runId) return false
        return when (provenance.source) {
            "agent-team" -> provenance.sourceId == scope.teamId && provenance.metadata["instance_id"] == member.memberId &&
                provenance.metadata["agent_id"] == member.agentId
            "late-managed-response" -> provenance.metadata["owner_run_id"] == stableAgentTeamMemberRunId(scope.runId, member.memberId) &&
                provenance.metadata["conversation_id"] == scope.conversationId && provenance.metadata["turn_id"] == scope.turnId
            else -> false
        }
    }

    private fun resultDigest(result: AgentSubagentChildResult): String {
        val values = JSONArray().put(result.supervisorId).put(result.childId).put(result.parentId).put(result.depth)
            .put(result.status.name).put(result.output).put(result.outputTruncated).put(result.errorMessage)
            .put(result.startedAtMillis).put(result.completedAtMillis).put(result.provenance.source).put(result.provenance.sourceId)
            .put(result.provenance.traceId).put(JSONArray(result.provenance.metadata.toSortedMap().map { (key, value) -> JSONArray().put(key).put(value) }))
        return MessageDigest.getInstance("SHA-256").digest(values.toString().toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }

    /** Host-owned completion pointers only. This records dispatch success, never semantic goal acceptance. */
    fun finishedContext(projection: Projection): Map<String, String> {
        require(projection.safeToApply) { "Conflicting host lifecycle must be reconciled before persistence or planning" }
        val rows = JSONObject().apply { projection.ledger.receipts.toSortedMap().forEach { (work, receipt) ->
            put(work, JSONObject().put("run_id", receipt.owner.runId).put("dispatch_id", receipt.owner.dispatchId)
                .put("generation", receipt.owner.generation).put("person_id", receipt.personId)
                .put("sequence", receipt.sequence).put("result_sha256", receipt.resultDigest))
        } }
        return mapOf(CollaborationGoalLoop.FINISHED_WORK to JSONArray(projection.finishedWork.sorted()).toString(),
            CollaborationGoalLoop.FINISHED_AUTHORS to JSONObject(projection.finishedAuthors.toSortedMap()).toString(),
            COMPLETIONS to JSONObject().put("version", 1).put("run_id", projection.scope.runId).put("group_id", projection.scope.groupId)
                .put("receipts", rows).toString())
    }

    fun readLedger(record: AgentTeamExecutionRecord): Ledger {
        val scope = scope(record)
        val work = JSONArray(record.request.context[CollaborationGoalLoop.FINISHED_WORK]?.toString() ?: "[]")
        val authors = JSONObject(record.request.context[CollaborationGoalLoop.FINISHED_AUTHORS]?.toString() ?: "{}")
        val saved = record.request.context[COMPLETIONS]?.toString()?.let(::JSONObject)
        if (saved != null) require(saved.getInt("version") == 1 && saved.getString("run_id") == scope.runId &&
            saved.getString("group_id") == scope.groupId) { "Completion ledger scope mismatch" }
        val rows = saved?.getJSONObject("receipts") ?: JSONObject()
        fun exactLong(row: JSONObject, key: String): Long = requireNotNull((row.get(key) as? Number)?.toString()?.toLongOrNull())
        return Ledger((0 until work.length()).mapTo(linkedSetOf()) { work.getString(it) },
            authors.keys().asSequence().associateWith { authors.getString(it) }, rows.keys().asSequence().associateWith { key ->
                val row = rows.getJSONObject(key)
                Receipt(OwnerKey(row.getString("run_id"), row.getString("dispatch_id"), exactLong(row, "generation")),
                    row.getString("person_id"), exactLong(row, "sequence"), row.getString("result_sha256"))
            })
    }

    fun ownershipContext(scope: Scope, ownership: Ownership): Map<String, String> {
        fun key(key: OwnerKey) = JSONObject().put("run_id", key.runId).put("dispatch_id", key.dispatchId).put("generation", key.generation)
        val json = JSONObject().put("version", 1).put("run_id", scope.runId).put("group_id", scope.groupId).put("team_id", scope.teamId)
            .put("generation", ownership.generation).put("bindings", JSONArray(ownership.bindings.map { binding ->
                key(binding.key(scope)).put("member_sha256", memberDigest(binding.member))
                    .put("independent_review", binding.independentReview ?: JSONObject.NULL).apply { binding.authority?.let { authority ->
                    put("authority", JSONObject().put("scope_id", authority.scopeId).put("revision", authority.revision)
                        .put("permissions_digest", authority.permissionsDigest))
                } }
            })).put("retired", JSONArray(ownership.retired.sortedWith(compareBy({ it.runId }, { it.dispatchId }, { it.generation })).map(::key)))
        return mapOf(OWNERSHIP to json.toString())
    }

    fun readOwnership(record: AgentTeamExecutionRecord): Ownership {
        val scope = scope(record)
        val json = JSONObject(requireNotNull(record.request.context[OWNERSHIP]).toString())
        require(json.getInt("version") == 1 && json.getString("run_id") == scope.runId && json.getString("group_id") == scope.groupId &&
            json.getString("team_id") == scope.teamId) { "Ownership scope mismatch" }
        fun number(row: JSONObject, key: String): Long = requireNotNull((row.get(key) as? Number)?.toString()?.toLongOrNull())
        fun key(row: JSONObject) = OwnerKey(row.getString("run_id"), row.getString("dispatch_id"), number(row, "generation")).also {
            require(it.runId == scope.runId && it.dispatchId.isNotBlank() && it.generation >= 0)
        }
        val rows = json.getJSONArray("bindings")
        val retired = json.getJSONArray("retired")
        val ownership = Ownership(number(json, "generation"), (0 until rows.length()).map { index ->
            val row = rows.getJSONObject(index)
            val owner = key(row)
            val member = record.definition.members.single { it.memberId == owner.dispatchId }
            require(memberDigest(member) == row.getString("member_sha256")) { "Dispatch contract changed; reauthorize before restoring ownership" }
            val authority = row.optJSONObject("authority")?.let { Authority(it.getString("scope_id"), number(it, "revision"), it.getString("permissions_digest")) }
            require(row.isNull("independent_review") || row.get("independent_review") is Boolean)
            Binding(member, owner.generation, authority, row.opt("independent_review") as? Boolean)
        }, (0 until retired.length()).mapTo(linkedSetOf()) { key(retired.getJSONObject(it)) })
        require(project(scope, ownership, emptyList(), readLedger(record)).safeToApply) { "Restore requires reconciliation of owner and completion ledger" }
        return ownership
    }

    private fun memberDigest(member: AgentTeamMember): String {
        val fields = JSONArray().put(member.memberId).put(member.agentId).put(member.deliveryMode.name).put(member.role).put(member.objective)
            .put(JSONArray(member.requiredCapabilities.map { it.name }.sorted())).put(JSONArray(member.dependsOnAgentIds.sorted()))
            .put(JSONArray(member.context.toSortedMap().map { (key, value) -> JSONArray().put(key).put(value) }))
        return MessageDigest.getInstance("SHA-256").digest(fields.toString().toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}
