package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal interface CollaborationWorkspaceRows {
    fun read(key: String): String?
    /** All values are committed atomically, including any head mutation and its token. */
    fun commit(values: Map<String, String>)
    fun page(prefix: String, after: String, limit: Int): List<String>
    /** Removals and upserts share one transaction. */
    fun mutate(values: Map<String, String>, removeKeys: Collection<String>) {
        require(removeKeys.isEmpty()) { "Workspace row removal is unavailable" }
        commit(values)
    }
}

internal data class CollaborationWorkspaceAccess(
    val groupId: String,
    val runId: String,
    val turnId: String,
    val round: Long,
    val nodeId: String = "",
    val personId: String = "",
    val dependencyNodes: Set<String> = emptySet(),
    val pinnedReads: Set<String> = emptySet()
) {
    fun canRead(revision: JSONObject): Boolean = revision.optString("group_id") == groupId &&
        (revision.optString("turn_id") != turnId || revision.optString("run_id") == runId &&
            (revision.optLong("round") < round || nodeId.isNotBlank() && revision.optString("node_id") == nodeId ||
                revision.optString("node_id") in dependencyNodes ||
                pinnedReads.isNotEmpty() && CollaborationMilestoneDispatch.grant(revision)?.let(pinnedReads::contains) == true))

    companion object {
        fun from(execution: AgentTeamMemberExecutionContext) = CollaborationWorkspaceAccess(
            groupId = execution.member.context["collaboration_group_id"].orEmpty(),
            runId = execution.request.parentRunId, turnId = execution.request.messageId,
            round = execution.request.context[CollaborationGoalLoop.ROUND]?.toString()?.toLongOrNull() ?: 0L,
            nodeId = execution.member.memberId,
            personId = execution.member.context[CollaborationResearchWorkflow.PERSON].orEmpty(),
            dependencyNodes = execution.member.dependsOnAgentIds,
            pinnedReads = CollaborationMilestoneDispatch.strings(execution.member.context[CollaborationMilestoneDispatch.GRANTS]))
    }
}

/** Immutable, host-attributed revisions. A model's report is never promoted to verified evidence here. */
internal class CollaborationResearchWorkspace(
    private val rows: CollaborationWorkspaceRows,
    private val authorized: (String) -> Boolean = { true },
    private val evidence: ((CollaborationWorkspaceAccess, JSONArray) -> JSONArray)? = null,
    private val accessAuthorized: (CollaborationWorkspaceAccess) -> Boolean = { true },
    private val evidenceReadCoverage: ((CollaborationWorkspaceAccess, JSONObject) -> Unit)? = null,
    private val evidenceOriginal: ((CollaborationWorkspaceAccess, JSONObject) -> JSONObject?)? = null,
    private val toolExperience: ((CollaborationWorkspaceAccess, JSONObject, String) -> JSONObject)? = null
) {
    constructor(context: Context) : this(object : CollaborationWorkspaceRows {
        private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)
        override fun read(key: String) = database.readString(key, "").takeIf(String::isNotBlank)
        override fun commit(values: Map<String, String>) = database.mutateStrings(values)
        override fun page(prefix: String, after: String, limit: Int) = database.keysAfter(prefix, after, limit)
        override fun mutate(values: Map<String, String>, removeKeys: Collection<String>) = database.mutateStrings(values, removeKeys)
    }, { group -> CollaborationGroupStore(context.applicationContext).load(group) != null },
        { access, refs -> CollaborationEvidenceLedger(context).references(access, refs) },
        { access ->
            val group = CollaborationGroupStore(context.applicationContext).load(access.groupId)
            access.personId.isNotBlank() && group != null && group.conversationId == access.groupId &&
                group.members.any { it.id == access.personId }
        }, { access, review -> CollaborationEvidenceLedger(context).requireReadCoverage(access, review) },
        { access, ref -> CollaborationEvidenceLedger(context).read(access, ref.getString("evidence_id"), ref.getString("sha256")) },
        { access, ref, cursor -> CollaborationEvidenceLedger(context).toolHistory(access, ref, cursor) })

    data class Page(val revisions: List<JSONObject>, val next: String?)

    internal fun recordConversationDelivery(access: CollaborationWorkspaceAccess, target: JSONObject, text: String, now: Long,
        persist: (String, String, Long) -> Unit,
        observe: (CollaborationWorkspaceAccess, String, JSONObject, Long) -> JSONObject): JSONObject = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        CollaborationConversationDelivery(rows).record(access, target, text, now, persist, observe)
    }

    fun workflowObservation(access: CollaborationWorkspaceAccess, ref: JSONObject): JSONObject = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        require(ref.optString("evidence_id").matches(Regex("[a-f0-9]{64}")) &&
            ref.optString("sha256").matches(Regex("[a-f0-9]{64}"))) { "Workflow observation requires an exact evidence ID and digest" }
        val reads = peerReadAccess(access)
        val original = requireNotNull(evidenceOriginal?.invoke(reads, ref)) { "Workflow observation is missing, changed or isolated" }
        require(original.getString("evidence_id") == ref.getString("evidence_id") && original.getString("sha256") == ref.getString("sha256") &&
            reads.canRead(original)) { "Workflow observation identity or access mismatch" }
        JSONObject(original.toString())
    }

    fun savedToolTests(access: CollaborationWorkspaceAccess, process: String): CollaborationSavedToolTest {
        requirePublicationActive(access)
        // Deleting a group or removing its member must not let a late worker recreate its rows.
        val scoped = object : CollaborationWorkspaceRows {
            override fun read(key: String) = synchronized(LOCK) { checkAcceptanceAccess(access); rows.read(key) }
            override fun commit(values: Map<String, String>) = synchronized(LOCK) { checkAcceptanceAccess(access); rows.commit(values) }
            override fun page(prefix: String, after: String, limit: Int) = synchronized(LOCK) {
                checkAcceptanceAccess(access)
                rows.page(prefix, after, limit)
            }
        }
        return CollaborationSavedToolTest(scoped, access, process)
    }

    fun enrollPublication(access: CollaborationWorkspaceAccess, stage: CollaborationResearchStage,
                          candidateTask: JSONObject? = null) = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        candidateTask?.let { CollaborationCandidateEvolution.checkTask(this, access, it) }
        val enrollment = CollaborationPublicationJournal(rows, access).enrollmentWrites(stage, candidateTask)
        val retirement = CollaborationPublicationRetirement(rows, access).enrollmentWrites(stage, candidateTask)
        if (enrollment.isNotEmpty() || retirement.isNotEmpty()) rows.commit(enrollment + retirement)
    }

    fun publicationContract(access: CollaborationWorkspaceAccess): JSONObject? = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        CollaborationPublicationJournal(rows, access).contract()
    }

    fun publicationCheckpoint(access: CollaborationWorkspaceAccess): JSONObject? = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        CollaborationPublicationJournal(rows, access).checkpoint()
    }

    fun publicationCapability(access: CollaborationWorkspaceAccess): JSONObject = synchronized(LOCK) {
        requirePublicationActive(access)
        val finalKey = prefix(access.groupId) + "publication:" + digest("${access.runId}:${access.nodeId}")
        CollaborationPublicationCapability.describe(publicationContract(access),
            rows.read(finalKey)?.let(::JSONObject)?.getJSONObject("result")?.optString("status") == "recorded")
    }

    fun requirePublicationActive(access: CollaborationWorkspaceAccess) = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        require(!CollaborationPublicationRetirement(rows, access).isRetired()) { "Publication dispatch was retired; do not resume it" }
    }

    fun publicationAssistance(access: CollaborationWorkspaceAccess, request: JSONObject? = null): JSONObject? = synchronized(LOCK) {
        requirePublicationActive(access)
        val journal = CollaborationPublicationJournal(rows, access)
        if (request != null) {
            CollaborationPublicationAssistance.validate(request)
            val writes = journal.assistanceWrites(request, System.currentTimeMillis())
            if (writes.isNotEmpty()) rows.commit(writes)
        }
        journal.assistance()
    }

    fun submitPublication(access: CollaborationWorkspaceAccess, raw: String, revalidate: Boolean = false): JSONObject = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        val contract = requireNotNull(CollaborationPublicationJournal(rows, access).contract()) {
            "Publication repair requires a host-owned contract"
        }
        if (revalidate) require(CollaborationPublicationJournal(rows, access).checkpoint()?.getString("raw") == raw) {
            "Only the saved publication can be revalidated"
        }
        publishInternal(access, raw, System.currentTimeMillis(), contract.optJSONObject("candidate_task"), recoverable = true,
            revalidate = revalidate)
    }

    fun publishMilestone(access: CollaborationWorkspaceAccess, id: String, raw: String,
                         now: Long = System.currentTimeMillis()): JSONObject {
        val result = synchronized(LOCK) {
            requirePublicationActive(access)
            CollaborationMilestoneJournal.validateId(id)
            val contract = requireNotNull(publicationContract(access)) { "A host-enrolled assignment is required" }
            require(!contract.has("candidate_task")) { "Host candidate transitions use final publication, not interim milestones" }
            val finalKey = prefix(access.groupId) + "publication:" + digest("${access.runId}:${access.nodeId}")
            require(rows.read(finalKey)?.let(::JSONObject)?.getJSONObject("result")?.optString("status") != "recorded") {
                "This assignment has already published its final result"
            }
            publishInternal(access, raw, now, null, false, milestoneId = id)
        }
        // Never call a scheduler/store while holding the workspace lock.
        if (result.optString("status") == "recorded" && CollaborationMilestoneCoordination.requestsCoordination(result))
            CollaborationMilestoneSignals.committed(access.runId)
        return result
    }

    fun pendingMilestones(access: CollaborationWorkspaceAccess, covered: Set<String>, producers: Set<String>,
                          coordinationOnly: Boolean = false, recipient: String? = null): List<JSONObject> = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        CollaborationMilestoneJournal.pending(rows, access, covered, producers, coordinationOnly, recipient).map { descriptor ->
            val refs = descriptor.getJSONArray("revisions")
            val grants = linkedSetOf<String>()
            repeat(refs.length()) { index ->
                val ref = refs.getJSONObject(index)
                val original = requireNotNull(readRevision(access.groupId, ref.getString("object_id"), ref.getInt("revision")))
                require(original.getString("run_id") == access.runId && original.getString("turn_id") == access.turnId &&
                    original.getLong("round") == access.round && original.getString("node_id") == descriptor.getString("producer_node") &&
                    original.getString("person_id") == descriptor.getString("person_id") &&
                    CollaborationResearchCandidates.same(original, ref)) { "Milestone original identity changed" }
                grants += requireNotNull(CollaborationMilestoneDispatch.grant(original))
                val observations = original.getJSONArray("host_observations")
                repeat(observations.length()) { at -> grants += requireNotNull(CollaborationMilestoneDispatch.grant(observations.getJSONObject(at))) }
            }
            descriptor.put("grants", JSONArray(grants.sorted()))
        }
    }

    fun milestoneReceipt(access: CollaborationWorkspaceAccess, id: String, artifactSha256: String): JSONObject = synchronized(LOCK) {
        requirePublicationActive(access)
        val result = CollaborationMilestoneJournal(rows, access).receipt(id, artifactSha256)
        if (result.optString("status") == "recorded") {
            val refs = result.getJSONArray("revisions")
            repeat(refs.length()) { index ->
                val ref = refs.getJSONObject(index)
                val original = requireNotNull(readRevision(access.groupId, ref.getString("object_id"), ref.getInt("revision")))
                require(original.getString("run_id") == access.runId && original.getString("turn_id") == access.turnId &&
                    original.getLong("round") == access.round && original.getString("node_id") == access.nodeId &&
                    original.getString("person_id") == access.personId && CollaborationResearchCandidates.same(original, ref)) {
                    "Milestone original identity changed"
                }
            }
        }
        result
    }

    fun milestones(access: CollaborationWorkspaceAccess, cursor: String = ""): JSONObject = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        CollaborationMilestoneJournal(rows, access).page(cursor)
    }

    fun coordinatorUpdates(access: CollaborationWorkspaceAccess, cursor: String, covered: Set<String>,
                           producers: Set<String>): JSONObject = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        CollaborationCoordinatorJournal(rows, access).page(cursor) { offered ->
            pendingMilestones(access, covered + offered, producers, coordinationOnly = true)
        }
    }

    fun coordinatorOffered(access: CollaborationWorkspaceAccess): List<JSONObject> = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        CollaborationCoordinatorJournal(rows, access).offered()
    }

    fun peerUpdates(access: CollaborationWorkspaceAccess, cursor: String, producers: Set<String>): JSONObject = synchronized(LOCK) {
        requirePublicationActive(access)
        CollaborationCoordinatorJournal(rows, access, peer = true).page(cursor) { offered ->
            pendingMilestones(access, offered, producers, recipient = access.personId)
        }
    }

    /** Grants survive task completion for final publication; new offers require an active host binding. */
    fun peerReadAccess(access: CollaborationWorkspaceAccess): CollaborationWorkspaceAccess = synchronized(LOCK) {
        val offered = CollaborationCoordinatorJournal(rows, access, peer = true).offered()
        if (offered.isEmpty()) return@synchronized access
        checkAcceptanceAccess(access)
        CollaborationCoordinatorUpdates.withGrants(access, offered)
    }

    fun publish(access: CollaborationWorkspaceAccess, raw: String, now: Long = System.currentTimeMillis(),
                candidateTask: JSONObject? = null): JSONObject = publishInternal(access, raw, now, candidateTask, false)

    private fun publishInternal(access: CollaborationWorkspaceAccess, raw: String, now: Long,
                                candidateTask: JSONObject?, recoverable: Boolean, revalidate: Boolean = false,
                                milestoneId: String? = null): JSONObject = synchronized(LOCK) {
        require(access.groupId.isNotBlank() && access.runId.isNotBlank() && access.turnId.isNotBlank() &&
            access.personId.isNotBlank() && access.nodeId.isNotBlank()) { "A host-owned research identity is required" }
        if (!authorized(access.groupId)) return@synchronized failure("Group access was removed")
        if (candidateTask != null && !accessAuthorized(access)) return@synchronized failure("Candidate member access was removed")
        val reads = peerReadAccess(access)
        val retirement = CollaborationPublicationRetirement(rows, access)
        if (retirement.isRetired()) {
            checkAcceptanceAccess(access)
            val result = failure("Publication dispatch was retired; late output is retained only for audit").put("retired", true)
            val journal = CollaborationPublicationJournal(rows, access)
            val audit = journal.retiredOutcomeWrites(raw, result, now)
            if (audit.isNotEmpty()) rows.commit(audit)
            return@synchronized result
        }
        val artifact = CollaborationResearchArtifact.decode(raw)
        if (artifact == null && candidateTask == null && !recoverable && milestoneId == null) return@synchronized JSONObject()
        val changes = artifact?.optJSONArray("workspace")
        if (artifact != null && changes == null && candidateTask == null && !recoverable && milestoneId == null && !artifact.has("milestones")) return@synchronized JSONObject()
        val prefix = prefix(access.groupId)
        val milestoneJournal = CollaborationMilestoneJournal(rows, access)
        val publicationKey = if (milestoneId == null) prefix + "publication:" + digest("${access.runId}:${access.nodeId}")
            else milestoneJournal.publicationKey(milestoneId)
        val inputHash = digest(if (candidateTask == null) raw else JSONArray().put(raw).put(candidateTask).toString())
        rows.read(publicationKey)?.let { saved ->
            val prior = JSONObject(saved)
            if ((!recoverable && milestoneId == null) || prior.getJSONObject("result").optString("status") == "recorded") {
                if (prior.getString("input_sha256") != inputHash)
                    return@synchronized failure("A different result already owns this dispatch; create new work for a revision")
                val result = prior.getJSONObject("result")
                if (result.optString("status") == "recorded") {
                    val refs = result.getJSONArray("revisions")
                    repeat(refs.length()) { index ->
                        val ref = refs.getJSONObject(index)
                        if (ref.optString("kind") == CollaborationResearchCandidates.EVENT) {
                            val revision = requireNotNull(read(access, ref.getString("object_id"), ref.getInt("revision")))
                            require(CollaborationResearchCandidates.same(ref, revision)) { "Candidate publication changed" }
                            requireCandidateReviewCoverage(access, revision)
                        }
                    }
                }
                return@synchronized result
            }
        }
        val writes = linkedMapOf<String, String>()
        val result = runCatching {
            retirement.requireOwnership(candidateTask)
            requireNotNull(artifact) { "Return a valid ${CollaborationResearchArtifact.FORMAT} object with a nonblank summary (empty candidates/findings may be omitted): " +
                CollaborationResearchArtifact.validationError(raw) }
            val changes = changes ?: if (candidateTask == null) JSONArray() else
                throw IllegalArgumentException("Candidate task requires a workspace revision/event")
            candidateTask?.let { CollaborationCandidateEvolution.checkTask(this, access, it) }
            require(milestoneId == null || !artifact.has("milestones") || CollaborationMilestoneCoordination.explicitRequest(artifact)) {
                "Only an explicit coordination request or final result may incorporate saved milestones"
            }
            val retained = milestoneJournal.resolve(artifact) { ref ->
                requireNotNull(read(access, ref.getString("object_id"), ref.getInt("revision"))) { "Milestone original missing" }.also {
                    require(CollaborationResearchCandidates.same(it, ref) && it.getString("node_id") == access.nodeId) { "Milestone identity changed" }
                }
            }
            val refs = JSONArray(retained.map(::reference))
            val revisions = retained.toMutableList()
            val changingIds = (0 until changes.length()).map { changes.getJSONObject(it) }
                .map { it.optString("object_id").ifBlank { digest("${access.groupId}:${access.personId}:${it.optString("id")}") } }.toSet()
            val candidates = CollaborationResearchCandidates(reads, { id, version -> read(reads, id, version) },
                { id, version -> isCurrent(reads, id, version) }, changingIds,
                { review -> requireCandidateReviewCoverage(reads, review) })
            val evolution = CollaborationEvolutionContract(reads, { id, version -> read(reads, id, version) },
                { id, version -> isCurrent(reads, id, version) }, changingIds,
                { ref -> evidenceOriginal?.invoke(reads, ref) },
                { review -> requireNotNull(evidenceReadCoverage) { "Original evidence page coverage is unavailable" }.invoke(reads, review) })
            val changedIds = hashSetOf<String>()
            repeat(changes.length()) { index ->
                val item = changes.getJSONObject(index)
                val requestedId = item.optString("object_id")
                val localId = item.optString("id")
                require(requestedId.isNotBlank() || localId.isNotBlank() && localId.length <= 160) { "New objects need a stable local id" }
                val id = requestedId.ifBlank { digest("${access.groupId}:${access.personId}:$localId") }
                require(id.matches(ID) && changedIds.add(id)) { "Invalid or duplicated object ID" }
                val kind = item.getString("kind")
                require(kind in KINDS) { "Unknown workspace object kind: workspace[$index].kind=$kind; allowed=${KINDS.sorted()}" }
                if (kind in CollaborationEvolutionContract.KINDS) require(accessAuthorized(access)) { "Evolution member access was removed" }
                val title = item.getString("title")
                require(title.isNotBlank() && title.length <= 240) { "A concise object title is required" }
                val body = item.getJSONObject("body")
                require(body.length() > 0) { "An empty status message is not a research object" }
                CollaborationReviewContract.validate(kind, body)
                val headKey = prefix + "head:" + id
                val head = rows.read(headKey)?.let(::JSONObject)
                require(requestedId.isBlank() == (head == null)) { "Use a new local id to create, or an existing host object_id to revise" }
                val base = item.optInt("base_revision", 0)
                require(base in 0 until Int.MAX_VALUE) { "Invalid workspace base revision" }
                require(base == (head?.getInt("revision") ?: 0)) { "Version conflict for $id; inspect the current revision before editing" }
                require(head == null || reads.canRead(head)) { "Current independent work cannot be read or overwritten" }
                require(head == null || read(reads, id, base)?.toString() == head.toString()) { "Workspace head integrity check failed" }
                require(head == null || head.getString("kind") == kind) { "An object's kind cannot be changed" }
                if (head != null && kind == CollaborationReviewContract.KIND) {
                    val previous = requireNotNull(read(reads, id, base)) { "Previous review is missing or isolated" }
                    require(previous.toString() == head.toString()) { "Review head integrity check failed" }
                    require(previous.getString("person_id") == access.personId) { "Only the review author may revise their typed review" }
                    require(reviewBinding(previous.getJSONObject("body")) == reviewBinding(body)) {
                        "A typed review revision must retain its review type, exact target and criterion binding"
                    }
                }
                listOf("parents", "resolves").forEach { key ->
                    require(!item.has(key) || item.optJSONArray(key) != null) { "$key must be an array" }
                }
                val parents = item.optJSONArray("parents") ?: JSONArray()
                val resolves = item.optJSONArray("resolves") ?: JSONArray()
                require(!item.has("observations") || item.optJSONArray("observations") != null) { "observations must be an array" }
                val observationRefs = item.optJSONArray("observations") ?: JSONArray()
                val observations = if (observationRefs.length() == 0) JSONArray() else
                    requireNotNull(evidence) { "Host evidence lookup is unavailable" }.invoke(reads, observationRefs)
                (listOf(parents, resolves)).forEach { links -> repeat(links.length()) { linkIndex ->
                    val link = links.getJSONObject(linkIndex)
                    val linked = requireNotNull(read(reads, link.getString("object_id"), link.getInt("revision"))) {
                        "A parent or counterevidence reference is missing or isolated"
                    }
                    require(!link.has("sha256") || link.getString("sha256") == linked.getString("sha256")) { "Workspace reference digest mismatch" }
                    if (links === resolves) require(linked.getString("kind") in setOf("counterexample", "question") ||
                        kind == CollaborationResearchCandidates.CANDIDATE &&
                        linked.optJSONObject("host_candidate_event")?.optString("operation") == "challenge") {
                        "resolves must reference a preserved counterexample or open question"
                    }
                } }
                val revision = JSONObject().put("object_id", id).put("revision", base + 1).put("kind", kind)
                    .put("title", title).put("body", body).put("parents", parents).put("resolves", resolves)
                    .put("host_observations", observations)
                    .put("group_id", access.groupId).put("run_id", access.runId).put("turn_id", access.turnId)
                    .put("round", access.round).put("node_id", access.nodeId).put("person_id", access.personId)
                    .put("recorded_at", now).put("evidence_state", "member_reported_not_verified")
                    .put("previous_sha256", head?.optString("sha256").orEmpty())
                candidates.validate(item, head, revision)
                evolution.validate(head, revision)
                listOf("parents", "resolves").forEach { key ->
                    val links = revision.getJSONArray(key)
                    revision.put(key, JSONArray((0 until links.length()).map { linkIndex ->
                        val link = links.getJSONObject(linkIndex)
                        CollaborationResearchCandidates.reference(requireNotNull(read(reads, link.getString("object_id"), link.getInt("revision"))))
                    }))
                }
                revision.put("sha256", digest(revision.toString()))
                writes[revisionKey(prefix, id, base + 1)] = revision.toString()
                writes[headKey] = revision.toString()
                if (kind in CollaborationEvolutionContract.KINDS) writes[prefix + "evolution:" + id] = id
                refs.put(reference(revision))
                revisions += revision
            }
            candidateTask?.let { CollaborationCandidateEvolution.checkPublication(it, revisions) }
            require(milestoneId == null || revisions.isNotEmpty()) { "An interim milestone needs a versioned workspace object, not only a status message" }
            JSONObject().put("status", "recorded").put("revisions", refs)
                .put("trust", "authorship_and_version_recorded_not_scientifically_verified")
                .also { receipt -> if (milestoneId != null) CollaborationMilestoneCoordination.read(artifact)?.let {
                    receipt.put("coordination", it)
                } }
        }.getOrElse {
            if (recoverable && it !is IllegalArgumentException && it !is org.json.JSONException) throw it
            writes.clear()
            failure(it.message ?: "Invalid workspace update").apply {
                (it as? CollaborationToolFeedback.Invalid)?.let { error -> put(CollaborationRecordValidation.DETAIL, error.problem) }
            }
        }
        // Restarting is not another model attempt when the saved draft still has the same rejection.
        if (revalidate && result.optString("status") == "rejected" &&
            CollaborationPublicationJournal(rows, access).checkpoint()?.getJSONObject("receipt")?.toString() == result.toString())
            return@synchronized result
        // Heads and the fence token must become visible in the same storage transaction.
        if (writes.isNotEmpty()) writes[mutationKey(access.groupId)] = newMutationToken()
        writes[publicationKey] = JSONObject().put("input_sha256", inputHash).put("result", result)
            .apply { candidateTask?.let { put("candidate_task_sha256", digest(it.toString())) } }.toString()
        if (milestoneId != null) writes.putAll(milestoneJournal.outcomeWrites(milestoneId, raw, result, now))
        if (recoverable) writes.putAll(CollaborationPublicationJournal(rows, access).outcomeWrites(raw, result, now))
        rows.commit(writes)
        result
    }

    fun read(access: CollaborationWorkspaceAccess, objectId: String, revision: Int): JSONObject? = synchronized(LOCK) {
        if (!authorized(access.groupId) || !objectId.matches(ID) || revision < 1) return@synchronized null
        readRevision(access.groupId, objectId, revision)?.takeIf(access::canRead)
    }

    private fun readRevision(group: String, objectId: String, revision: Int): JSONObject? =
        rows.read(revisionKey(prefix(group), objectId, revision))?.let(::JSONObject)?.also { saved ->
            val hash = saved.getString("sha256")
            val body = JSONObject(saved.toString()).apply { remove("sha256") }
            check(revision > 0 && digest(body.toString()) == hash && saved.getString("object_id") == objectId &&
                saved.getInt("revision") == revision && saved.getString("group_id") == group) {
                "Research revision integrity check failed"
            }
        }

    /** Resolve host publication receipts, never member-authored result text. */
    fun publicationRevisions(access: CollaborationWorkspaceAccess, nodeId: String): List<JSONObject> = synchronized(LOCK) {
        if (!authorized(access.groupId)) return@synchronized emptyList()
        val publication = rows.read(prefix(access.groupId) + "publication:" + digest("${access.runId}:$nodeId"))
            ?.let(::JSONObject)?.getJSONObject("result") ?: return@synchronized emptyList()
        if (publication.optString("status") != "recorded") return@synchronized emptyList()
        val refs = publication.getJSONArray("revisions")
        (0 until refs.length()).map { index ->
            val ref = refs.getJSONObject(index)
            val saved = requireNotNull(read(access, ref.getString("object_id"), ref.getInt("revision"))) { "Publication revision missing or isolated" }
            check(CollaborationResearchCandidates.same(saved, ref) && saved.getString("run_id") == access.runId &&
                saved.getString("turn_id") == access.turnId && saved.getString("node_id") == nodeId) { "Publication revision identity changed" }
            observationReferences(access, ref)
            requireCandidateReviewCoverage(access, saved)
            saved
        }
    }

    fun observationReferences(access: CollaborationWorkspaceAccess, ref: JSONObject): JSONArray = synchronized(LOCK) {
        val saved = requireNotNull(read(access, ref.getString("object_id"), ref.getInt("revision"))) { "Observation owner is missing or isolated" }
        require(CollaborationResearchCandidates.same(saved, ref)) { "Observation owner digest changed" }
        val refs = saved.getJSONArray("host_observations")
        if (refs.length() == 0) JSONArray() else requireNotNull(evidence) { "Host evidence lookup is unavailable" }.invoke(peerReadAccess(access), refs)
    }

    fun replayCandidateTask(access: CollaborationWorkspaceAccess, task: JSONObject): JSONObject? = synchronized(LOCK) {
        require(authorized(access.groupId) && accessAuthorized(access)) { "Candidate member access was removed" }
        CollaborationCandidateEvolution.checkIdentity(access, task)
        require(!CollaborationPublicationRetirement(rows, access).isRetired()) { "Retired candidate work cannot be replayed" }
        val saved = rows.read(prefix(access.groupId) + "publication:" + digest("${access.runId}:${access.nodeId}"))
            ?.let(::JSONObject) ?: return@synchronized null
        require(saved.optString("candidate_task_sha256") == digest(task.toString())) { "Candidate dispatch task changed" }
        val result = saved.getJSONObject("result")
        if (result.optString("status") == "rejected" && CollaborationPublicationJournal(rows, access).contract() != null)
            return@synchronized null
        if (result.optString("status") == "recorded")
            CollaborationCandidateEvolution.checkPublication(task, publicationRevisions(access, access.nodeId))
        JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
            .put("summary", "Restored durable candidate publication; original revisions and observations remain in scoped workspace recall. No task was repeated.")
            .put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace_receipt", result)
    }

    fun candidateReviewApplies(access: CollaborationWorkspaceAccess, ref: JSONObject): Boolean = synchronized(LOCK) {
        val saved = read(access, ref.optString("object_id"), ref.optInt("revision")) ?: return@synchronized false
        if (!CollaborationResearchCandidates.same(saved, ref) || saved.getString("kind") != CollaborationResearchCandidates.EVENT ||
            !isCurrent(access, saved.getString("object_id"), saved.getInt("revision"))) return@synchronized false
        val event = saved.optJSONObject("host_candidate_event") ?: return@synchronized false
        if (event.optString("operation") != "review") return@synchronized false
        if (runCatching { requireCandidateReviewCoverage(access, saved) }.isFailure) return@synchronized false
        val target = event.getJSONArray("targets").getJSONObject(0)
        val candidate = read(access, target.getString("object_id"), target.getInt("revision")) ?: return@synchronized false
        CollaborationResearchCandidates.same(candidate, target) && CollaborationResearchCandidates.active(candidate) &&
            isCurrent(access, target.getString("object_id"), target.getInt("revision"))
    }

    private fun requireCandidateReviewCoverage(access: CollaborationWorkspaceAccess, revision: JSONObject) {
        if (revision.getString("kind") == CollaborationResearchCandidates.EVENT &&
            revision.getJSONObject("body").getJSONObject(CollaborationResearchCandidates.EVENT).optString("operation") == "review")
            requireNotNull(evidenceReadCoverage) { "Original evidence read validation is unavailable" }.invoke(peerReadAccess(access), revision)
    }

    fun isCurrent(access: CollaborationWorkspaceAccess, objectId: String, revision: Int): Boolean = synchronized(LOCK) {
        if (!authorized(access.groupId) || !objectId.matches(ID)) return@synchronized false
        rows.read(prefix(access.groupId) + "head:" + objectId)?.let(::JSONObject)?.let {
            access.canRead(it) && it.getInt("revision") == revision && read(access, objectId, revision)?.toString() == it.toString()
        } == true
    }

    fun contributorIds(access: CollaborationWorkspaceAccess, ref: JSONObject): Set<String> =
        CollaborationAcceptanceAncestry.contributors(ref) { id, version -> read(access, id, version) }

    fun acceptanceReviewSnapshot(access: CollaborationWorkspaceAccess,
                                 targets: Set<CollaborationAcceptanceReviewSnapshot.Binding>): CollaborationAcceptanceReviewSnapshot {
        val selected = targets.toSet()
        return scanAcceptanceReviews(access) { _, binding -> binding in selected }
    }

    /** Compatibility query; evaluations share one indexed snapshot instead of calling this per target. */
    fun currentAcceptanceReviews(access: CollaborationWorkspaceAccess, target: JSONObject,
                                 relevant: (JSONObject) -> Boolean = { true }): List<JSONObject> {
        val exactTarget = CollaborationAcceptanceReviewSnapshot.Target.of(target)
        val snapshot = scanAcceptanceReviews(access) { saved, binding -> binding.target == exactTarget && relevant(saved) }
        val reviews = snapshot.allReviews()
        return withAcceptanceFence(snapshot) { reviews }
    }

    private fun scanAcceptanceReviews(access: CollaborationWorkspaceAccess,
                                      relevant: (JSONObject, CollaborationAcceptanceReviewSnapshot.Binding) -> Boolean): CollaborationAcceptanceReviewSnapshot {
        val scope = access.copy(dependencyNodes = access.dependencyNodes.toSet())
        val token = synchronized(LOCK) {
            checkAcceptanceAccess(scope)
            mutationToken(scope.groupId)
        }
        val headPrefix = prefix(scope.groupId) + "head:"
        return CollaborationAcceptanceReviewSnapshot.scan(this, scope, token, page = { cursor ->
            synchronized(LOCK) {
                checkAcceptanceFence(scope, token)
                val keys = rows.page(headPrefix, cursor, CollaborationAcceptanceReviewSnapshot.PAGE_SIZE)
                require(keys.size <= CollaborationAcceptanceReviewSnapshot.PAGE_SIZE) { "Acceptance review directory returned an oversized page" }
                var previous = cursor
                val heads = keys.map { key ->
                    require(key > previous && key.startsWith(headPrefix)) {
                        "Acceptance review directory has invalid or non-advancing pagination"
                    }
                    previous = key
                    val id = key.removePrefix(headPrefix)
                    require(id.matches(ID)) { "Invalid acceptance review directory entry" }
                    val head = JSONObject(requireNotNull(rows.read(key)) { "Acceptance review directory entry disappeared" })
                    val saved = requireNotNull(readRevision(scope.groupId, id, head.getInt("revision"))) {
                        "Acceptance review directory revision is missing"
                    }
                    require(saved.toString() == head.toString()) { "Acceptance review head integrity check failed" }
                    CollaborationAcceptanceReviewSnapshot.Head(key, saved)
                }
                checkAcceptanceFence(scope, token)
                heads
            }
        }, read = { id, version ->
            synchronized(LOCK) {
                checkAcceptanceFence(scope, token)
                val saved = requireNotNull(readRevision(scope.groupId, id, version)) { "Acceptance review history is incomplete" }
                checkAcceptanceFence(scope, token)
                saved
            }
        }, relevant = relevant)
    }

    fun <T> withAcceptanceFence(snapshot: CollaborationAcceptanceReviewSnapshot, receipt: () -> T): T = synchronized(LOCK) {
        require(snapshot.owner === this) { "Acceptance snapshot belongs to another workspace" }
        checkAcceptanceFence(snapshot.access, snapshot.mutationToken)
        receipt()
    }

    private fun checkAcceptanceFence(access: CollaborationWorkspaceAccess, token: String?) {
        require(mutationToken(access.groupId) == token) { "Workspace changed during acceptance; evaluate the current review state again" }
        checkAcceptanceAccess(access)
    }

    private fun checkAcceptanceAccess(access: CollaborationWorkspaceAccess) {
        require(authorized(access.groupId)) { "Group access was removed" }
        require(accessAuthorized(access)) { "Acceptance member access was removed" }
    }

    private fun mutationToken(group: String): String? = rows.read(mutationKey(group))?.also {
        require(it.matches(ID)) { "Workspace mutation token is corrupt" }
    }

    internal fun removeGroup(group: String) = synchronized(LOCK) {
        val removed = linkedSetOf<String>()
        // Coordinator journals use the wire digest; preserve that live namespace and remove it explicitly.
        for (prefix in listOf(prefix(group), CollaborationCoordinatorJournal.groupPrefix(group),
            CollaborationCoordinatorJournal.groupPrefix(group, peer = true))) {
            var cursor = ""
            while (true) {
                val keys = rows.page(prefix, cursor, CollaborationAcceptanceReviewSnapshot.PAGE_SIZE)
                require(keys.size <= CollaborationAcceptanceReviewSnapshot.PAGE_SIZE) { "Workspace removal returned an oversized page" }
                if (keys.isEmpty()) break
                keys.forEach { key ->
                    require(key > cursor && key.startsWith(prefix) && removed.add(key)) { "Invalid workspace removal pagination" }
                    cursor = key
                }
            }
        }
        // The token is outside the deleted namespace, including for an empty/legacy group.
        rows.mutate(mapOf(mutationKey(group) to newMutationToken()), removed)
    }

    fun browse(access: CollaborationWorkspaceAccess, cursor: String = "", limit: Int = 20): Page = synchronized(LOCK) {
        browseHeads(access, cursor, limit, "head:")
    }

    fun browseEvolution(access: CollaborationWorkspaceAccess, cursor: String = "", limit: Int = 20): Page = synchronized(LOCK) {
        browseHeads(access, cursor, limit, "evolution:")
    }

    fun recordMethodExperience(record: AgentTeamExecutionRecord, result: AgentSubagentChildResult) = synchronized(LOCK) {
        val member = record.definition.members.singleOrNull { it.memberId == result.childId } ?: return@synchronized
        val group = member.context["collaboration_group_id"].orEmpty()
        val access = CollaborationWorkspaceAccess(group, record.request.runId, record.request.messageId,
            record.request.context[CollaborationGoalLoop.ROUND]?.toString()?.toLongOrNull() ?: 0L,
            member.memberId, member.context[CollaborationResearchWorkflow.PERSON].orEmpty(), member.dependsOnAgentIds)
        if (group.isBlank() || access.personId.isBlank() || !authorized(group) || !accessAuthorized(access)) return@synchronized
        require(group == record.request.conversationId) { "Method-use group changed" }
        for ((task, field) in CollaborationMethodExperience.TASKS) {
            val binding = member.context[task]?.let(::JSONObject) ?: continue
            require(binding.optString("member") == access.personId && binding.optString("assignment") == member.objective &&
                binding.optString("stage") == member.context[CollaborationResearchWorkflow.STAGE]) { "Method-use assignment changed" }
            val ref = binding.getJSONObject(field)
            val method = requireNotNull(read(access, ref.getString("object_id"), ref.getInt("revision"))) { "Method-use source is missing or isolated" }
            require(method.getString("kind") == (if (field == "method") CollaborationWorkflowMethod.KIND else CollaborationProceduralMemory.SKILL) &&
                CollaborationResearchCandidates.same(method, ref)) { "Method-use source changed" }
            CollaborationMethodExperience(rows, group).record(access, CollaborationResearchCandidates.reference(method), binding, record, member, result)
        }
    }

    fun methodHistory(access: CollaborationWorkspaceAccess, ref: JSONObject, cursor: String = ""): JSONObject = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        val method = requireNotNull(read(access, ref.getString("object_id"), ref.getInt("revision"))) { "Method is missing or isolated" }
        require(method.getString("kind") in setOf(CollaborationWorkflowMethod.KIND, CollaborationProceduralMemory.SKILL, CollaborationExecutableTool.RELEASE) &&
            CollaborationResearchCandidates.same(method, ref)) { "Method revision or digest changed" }
        if (method.getString("kind") == CollaborationExecutableTool.RELEASE) {
            return@synchronized requireNotNull(toolExperience) { "Native tool history is unavailable" }
                .invoke(access, CollaborationResearchCandidates.reference(method), cursor)
        }
        CollaborationMethodExperience(rows, access.groupId).browse(access, CollaborationResearchCandidates.reference(method), cursor)
    }

    fun methodHistoryRecord(access: CollaborationWorkspaceAccess, id: String): JSONObject? = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        CollaborationMethodExperience(rows, access.groupId).read(access, id)
    }

    fun searchCapabilities(access: CollaborationWorkspaceAccess, query: String, cursor: String = ""): JSONObject = synchronized(LOCK) {
        checkAcceptanceAccess(access)
        val search = CollaborationCapabilityRecall.query(query)
        val scope = digest(JSONArray().put(access.groupId).put(access.runId).put(access.turnId).put(access.round)
            .put(access.nodeId).put(access.personId).put(JSONArray(access.dependencyNodes.sorted()))
            .put(JSONArray(access.pinnedReads.sorted())).put(query).toString())
        val prefix = prefix(access.groupId) + "evolution:"
        require(cursor.length <= 512) { "Capability cursor is too long" }
        val after = if (cursor.isBlank()) "" else {
            val saved = runCatching { JSONObject(cursor).also { value ->
                listOf("scope", "after").forEach { require(value.opt(it) is String) }
            } }.getOrElse { throw IllegalArgumentException("Invalid capability cursor; restart without a cursor") }
            require(saved.getString("scope") == scope) {
                "Capability query or assignment changed; restart without a cursor"
            }
            saved.getString("after").also {
                require(it.startsWith(prefix) && it.removePrefix(prefix).matches(ID)) { "Invalid capability cursor" }
            }
        }
        val keys = rows.page(prefix, after, CollaborationCapabilityRecall.SCAN_PAGE + 1)
        val found = mutableListOf<JSONObject>()
        val linked = mutableMapOf<String, JSONObject?>()
        var processed = 0
        for (key in keys.take(CollaborationCapabilityRecall.SCAN_PAGE)) {
            processed++
            var saved = rows.read(prefix(access.groupId) + "head:" + key.removePrefix(prefix))?.let(::JSONObject)
            while (saved != null && !access.canRead(saved)) {
                val previous = saved.getInt("revision") - 1
                saved = if (previous > 0) readRevision(access.groupId, saved.getString("object_id"), previous) else null
            }
            if (saved != null && saved.getString("kind") in CollaborationCapabilityRecall.KINDS) {
                val original = requireNotNull(read(access, saved.getString("object_id"), saved.getInt("revision")))
                require(original.toString() == saved.toString()) { "Capability head integrity check failed" }
                CollaborationCapabilityRecall.match(original, search) { ref ->
                    val id = "${ref.getString("object_id")}:${ref.getInt("revision")}:${ref.getString("sha256")}"
                    if (!linked.containsKey(id)) linked[id] = read(access, ref.getString("object_id"), ref.getInt("revision"))
                    linked[id]
                }?.let { match ->
                    if (original.getString("kind") in setOf(CollaborationWorkflowMethod.KIND, CollaborationProceduralMemory.SKILL, CollaborationExecutableTool.RELEASE))
                        match.put("usage_recall", JSONObject().put("mode", "method_history").put("object_id", original.getString("object_id"))
                            .put("revision", original.getInt("revision")).put("sha256", original.getString("sha256")))
                    found.add(match)
                }
            }
            if (found.size == CollaborationCapabilityRecall.RESULT_PAGE) break
        }
        val next = if (processed < keys.size) JSONObject().put("scope", scope)
            .put("after", keys[processed - 1]).toString() else null
        CollaborationCapabilityRecall.page(search, found, next)
    }

    private fun browseHeads(access: CollaborationWorkspaceAccess, cursor: String, limit: Int, namespace: String): Page {
        if (!authorized(access.groupId)) return Page(emptyList(), null)
        val prefix = prefix(access.groupId) + namespace
        require(cursor.isBlank() || cursor.startsWith(prefix) && cursor.removePrefix(prefix).matches(ID)) { "Invalid workspace cursor" }
        val keys = rows.page(prefix, cursor, limit.coerceIn(1, 100) + 1)
        val selected = keys.take(limit.coerceIn(1, 100))
        val revisions = selected.mapNotNull { key ->
            var candidate = rows.read(prefix(access.groupId) + "head:" + key.removePrefix(prefix))?.let(::JSONObject)
            while (candidate != null && !access.canRead(candidate)) {
                val previous = candidate.getInt("revision") - 1
                candidate = if (previous > 0) rows.read(revisionKey(prefix(access.groupId), candidate.getString("object_id"), previous))?.let(::JSONObject) else null
            }
            candidate?.let { visible ->
                read(access, visible.getString("object_id"), visible.getInt("revision"))?.let { saved ->
                    reference(saved).apply {
                        if (saved.optJSONObject("host_candidate_event")?.optString("operation") == "review")
                            put("review_applicability", if (candidateReviewApplies(access, this)) "current" else "stale_or_isolated")
                        saved.optJSONObject(CollaborationEvolutionContract.HOST)?.let { evolution ->
                            val lineage = if (saved.getString("kind") == CollaborationToolComparison.KIND)
                                CollaborationToolComparison.lineageReferences(evolution).map { it.second }
                            else listOf("innovation", "baseline", "plan", "result", "rollback", "gap", "diagnosis", "lesson", "transfer_study", "source")
                                .mapNotNull(evolution::optJSONObject)
                            val current = lineage.all { ref ->
                                val target = read(access, ref.getString("object_id"), ref.getInt("revision"))
                                target != null && CollaborationResearchCandidates.same(target, ref) &&
                                    isCurrent(access, target.getString("object_id"), target.getInt("revision"))
                            } && evolution.optJSONArray("gaps")?.let { gaps -> (0 until gaps.length()).all { index ->
                                val ref = gaps.getJSONObject(index)
                                val target = read(access, ref.getString("object_id"), ref.getInt("revision"))
                                target != null && CollaborationResearchCandidates.same(target, ref) &&
                                    isCurrent(access, target.getString("object_id"), target.getInt("revision"))
                            } } != false && runCatching {
                                CollaborationTransferStudy.checkRecord(saved) { ref, kinds ->
                                    val target = requireNotNull(read(access, ref.getString("object_id"), ref.getInt("revision")))
                                    require(target.getString("kind") in kinds && CollaborationResearchCandidates.same(target, ref) &&
                                        isCurrent(access, ref.getString("object_id"), ref.getInt("revision")))
                                    target
                                }
                                CollaborationInnovationValidation.checkRecord(saved) { ref, kinds ->
                                    val target = requireNotNull(read(access, ref.getString("object_id"), ref.getInt("revision")))
                                    require(target.getString("kind") in kinds && CollaborationResearchCandidates.same(target, ref) &&
                                        isCurrent(access, ref.getString("object_id"), ref.getInt("revision")))
                                    target
                                }
                            }.isSuccess
                            put("evolution_applicability", if (current) "inspect_scope_before_reuse" else "historical_requires_revalidation")
                        }
                    }
                }
            }
        }
        return Page(revisions, selected.lastOrNull()?.takeIf { keys.size > selected.size })
    }

    companion object {
        private val LOCK = Any()
        private const val DATABASE = "galaxyssi_collaboration_workspace_v1"
        private val ID = Regex("[a-f0-9]{64}")
        val KINDS = setOf("hypothesis", "evidence", "counterexample", "proposal", "experiment", "artifact", "decision", "question",
            CollaborationReviewContract.KIND, CollaborationResearchCandidates.CANDIDATE, CollaborationResearchCandidates.EVENT) +
            CollaborationEvolutionContract.KINDS
        private fun digest(value: String) = AgentNativeJsonCodec.sha256(value)
        private fun prefix(group: String) = "group:${digest(group)}:"
        private fun mutationKey(group: String) = "mutation:${digest(group)}"
        private fun newMutationToken() = digest(UUID.randomUUID().toString())
        private fun revisionKey(prefix: String, id: String, revision: Int) = "${prefix}revision:$id:$revision"
        private fun failure(message: String) = JSONObject().put("status", "rejected").put("reason", message)
        private fun reviewBinding(body: JSONObject) = CollaborationAcceptanceReviewSnapshot.Binding.fromBody(body)
        private fun reference(revision: JSONObject) = JSONObject().apply {
            listOf("object_id", "revision", "kind", "title", "person_id", "node_id", "sha256", "evidence_state", "recorded_at")
                .forEach { key -> put(key, revision.get(key)) }
            CollaborationRecordValidation.notice(revision)?.let { put("registration_notice", it) }
            listOf("host_candidate", "host_candidate_event").forEach { key -> revision.optJSONObject(key)?.let { put(key, it) } }
            revision.optJSONObject(CollaborationEvolutionContract.HOST)?.let { host ->
                put(CollaborationEvolutionContract.HOST, (if (revision.getString("kind") == CollaborationNumericModelTrial.KIND)
                    CollaborationNumericFeedback.summary(host) else JSONObject(host.toString())).apply {
                    optJSONArray("cases")?.let { put("case_count", it.length()); remove("cases") }
                    optJSONArray("checks")?.let { put("check_count", it.length()); remove("checks") }
                    optJSONArray("anchors")?.let { put("protected_case_count", it.length()); remove("anchors") }
                })
            }
        }

        fun remove(context: Context, group: String) = CollaborationResearchWorkspace(context).removeGroup(group)
    }
}
