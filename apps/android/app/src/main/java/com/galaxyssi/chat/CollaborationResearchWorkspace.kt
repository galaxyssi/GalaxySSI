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
    val dependencyNodes: Set<String> = emptySet()
) {
    fun canRead(revision: JSONObject): Boolean = revision.optString("group_id") == groupId &&
        (revision.optString("turn_id") != turnId || revision.optString("run_id") == runId &&
            (revision.optLong("round") < round || nodeId.isNotBlank() && revision.optString("node_id") == nodeId ||
                revision.optString("node_id") in dependencyNodes))

    companion object {
        fun from(execution: AgentTeamMemberExecutionContext) = CollaborationWorkspaceAccess(
            groupId = execution.member.context["collaboration_group_id"].orEmpty(),
            runId = execution.request.parentRunId, turnId = execution.request.messageId,
            round = execution.request.context[CollaborationGoalLoop.ROUND]?.toString()?.toLongOrNull() ?: 0L,
            nodeId = execution.member.memberId,
            personId = execution.member.context[CollaborationResearchWorkflow.PERSON].orEmpty(),
            dependencyNodes = execution.member.dependsOnAgentIds)
    }
}

/** Immutable, host-attributed revisions. A model's report is never promoted to verified evidence here. */
internal class CollaborationResearchWorkspace(
    private val rows: CollaborationWorkspaceRows,
    private val authorized: (String) -> Boolean = { true },
    private val evidence: ((CollaborationWorkspaceAccess, JSONArray) -> JSONArray)? = null,
    private val accessAuthorized: (CollaborationWorkspaceAccess) -> Boolean = { true },
    private val evidenceReadCoverage: ((CollaborationWorkspaceAccess, JSONObject) -> Unit)? = null
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
        }, { access, review -> CollaborationEvidenceLedger(context).requireReadCoverage(access, review) })

    data class Page(val revisions: List<JSONObject>, val next: String?)

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

    fun publish(access: CollaborationWorkspaceAccess, raw: String, now: Long = System.currentTimeMillis(),
                candidateTask: JSONObject? = null): JSONObject = publishInternal(access, raw, now, candidateTask, false)

    private fun publishInternal(access: CollaborationWorkspaceAccess, raw: String, now: Long,
                                candidateTask: JSONObject?, recoverable: Boolean, revalidate: Boolean = false): JSONObject = synchronized(LOCK) {
        require(access.groupId.isNotBlank() && access.runId.isNotBlank() && access.turnId.isNotBlank() &&
            access.personId.isNotBlank() && access.nodeId.isNotBlank()) { "A host-owned research identity is required" }
        if (!authorized(access.groupId)) return@synchronized failure("Group access was removed")
        if (candidateTask != null && !accessAuthorized(access)) return@synchronized failure("Candidate member access was removed")
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
        if (artifact == null && candidateTask == null && !recoverable) return@synchronized JSONObject()
        val changes = artifact?.optJSONArray("workspace")
        if (artifact != null && changes == null && candidateTask == null && !recoverable) return@synchronized JSONObject()
        val prefix = prefix(access.groupId)
        val publicationKey = prefix + "publication:" + digest("${access.runId}:${access.nodeId}")
        val inputHash = digest(if (candidateTask == null) raw else JSONArray().put(raw).put(candidateTask).toString())
        rows.read(publicationKey)?.let { saved ->
            val prior = JSONObject(saved)
            if (!recoverable || prior.getJSONObject("result").optString("status") == "recorded") {
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
            requireNotNull(artifact) { "Return a valid ${CollaborationResearchArtifact.FORMAT} object with summary, candidates and findings: " +
                CollaborationResearchArtifact.validationError(raw) }
            val changes = changes ?: if (candidateTask == null) JSONArray() else
                throw IllegalArgumentException("Candidate task requires a workspace revision/event")
            candidateTask?.let { CollaborationCandidateEvolution.checkTask(this, access, it) }
            val refs = JSONArray()
            val revisions = mutableListOf<JSONObject>()
            val changingIds = (0 until changes.length()).map { changes.getJSONObject(it) }
                .map { it.optString("object_id").ifBlank { digest("${access.groupId}:${access.personId}:${it.optString("id")}") } }.toSet()
            val candidates = CollaborationResearchCandidates(access, { id, version -> read(access, id, version) },
                { id, version -> isCurrent(access, id, version) }, changingIds,
                { review -> requireCandidateReviewCoverage(access, review) })
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
                require(head == null || access.canRead(head)) { "Current independent work cannot be read or overwritten" }
                require(head == null || read(access, id, base)?.toString() == head.toString()) { "Workspace head integrity check failed" }
                require(head == null || head.getString("kind") == kind) { "An object's kind cannot be changed" }
                if (head != null && kind == CollaborationReviewContract.KIND) {
                    val previous = requireNotNull(read(access, id, base)) { "Previous review is missing or isolated" }
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
                    requireNotNull(evidence) { "Host evidence lookup is unavailable" }.invoke(access, observationRefs)
                (listOf(parents, resolves)).forEach { links -> repeat(links.length()) { linkIndex ->
                    val link = links.getJSONObject(linkIndex)
                    val linked = requireNotNull(read(access, link.getString("object_id"), link.getInt("revision"))) {
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
                listOf("parents", "resolves").forEach { key ->
                    val links = revision.getJSONArray(key)
                    revision.put(key, JSONArray((0 until links.length()).map { linkIndex ->
                        val link = links.getJSONObject(linkIndex)
                        CollaborationResearchCandidates.reference(requireNotNull(read(access, link.getString("object_id"), link.getInt("revision"))))
                    }))
                }
                revision.put("sha256", digest(revision.toString()))
                writes[revisionKey(prefix, id, base + 1)] = revision.toString()
                writes[headKey] = revision.toString()
                refs.put(reference(revision))
                revisions += revision
            }
            candidateTask?.let { CollaborationCandidateEvolution.checkPublication(it, revisions) }
            JSONObject().put("status", "recorded").put("revisions", refs)
                .put("trust", "authorship_and_version_recorded_not_scientifically_verified")
        }.getOrElse {
            if (recoverable && it !is IllegalArgumentException && it !is org.json.JSONException) throw it
            writes.clear()
            failure(it.message ?: "Invalid workspace update")
        }
        // Restarting is not another model attempt when the saved draft still has the same rejection.
        if (revalidate && result.optString("status") == "rejected" &&
            CollaborationPublicationJournal(rows, access).checkpoint()?.getJSONObject("receipt")?.toString() == result.toString())
            return@synchronized result
        // Heads and the fence token must become visible in the same storage transaction.
        if (writes.isNotEmpty()) writes[mutationKey(access.groupId)] = newMutationToken()
        writes[publicationKey] = JSONObject().put("input_sha256", inputHash).put("result", result)
            .apply { candidateTask?.let { put("candidate_task_sha256", digest(it.toString())) } }.toString()
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
        if (refs.length() == 0) JSONArray() else requireNotNull(evidence) { "Host evidence lookup is unavailable" }.invoke(access, refs)
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
            requireNotNull(evidenceReadCoverage) { "Original evidence read validation is unavailable" }.invoke(access, revision)
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
        val prefix = prefix(group)
        val removed = linkedSetOf<String>()
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
        // The token is outside the deleted namespace, including for an empty/legacy group.
        rows.mutate(mapOf(mutationKey(group) to newMutationToken()), removed)
    }

    fun browse(access: CollaborationWorkspaceAccess, cursor: String = "", limit: Int = 20): Page = synchronized(LOCK) {
        if (!authorized(access.groupId)) return@synchronized Page(emptyList(), null)
        val prefix = prefix(access.groupId) + "head:"
        require(cursor.isBlank() || cursor.startsWith(prefix) && cursor.removePrefix(prefix).matches(ID)) { "Invalid workspace cursor" }
        val keys = rows.page(prefix, cursor, limit.coerceIn(1, 100) + 1)
        val selected = keys.take(limit.coerceIn(1, 100))
        val revisions = selected.mapNotNull { key ->
            var candidate = rows.read(key)?.let(::JSONObject)
            while (candidate != null && !access.canRead(candidate)) {
                val previous = candidate.getInt("revision") - 1
                candidate = if (previous > 0) rows.read(revisionKey(prefix(access.groupId), candidate.getString("object_id"), previous))?.let(::JSONObject) else null
            }
            candidate?.let { visible ->
                read(access, visible.getString("object_id"), visible.getInt("revision"))?.let { saved ->
                    reference(saved).apply {
                        if (saved.optJSONObject("host_candidate_event")?.optString("operation") == "review")
                            put("review_applicability", if (candidateReviewApplies(access, this)) "current" else "stale_or_isolated")
                    }
                }
            }
        }
        Page(revisions, selected.lastOrNull()?.takeIf { keys.size > selected.size })
    }

    companion object {
        private val LOCK = Any()
        private const val DATABASE = "galaxyssi_collaboration_workspace_v1"
        private val ID = Regex("[a-f0-9]{64}")
        val KINDS = setOf("hypothesis", "evidence", "counterexample", "proposal", "experiment", "artifact", "decision", "question",
            CollaborationReviewContract.KIND, CollaborationResearchCandidates.CANDIDATE, CollaborationResearchCandidates.EVENT)
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
            listOf("host_candidate", "host_candidate_event").forEach { key -> revision.optJSONObject(key)?.let { put(key, it) } }
        }

        fun remove(context: Context, group: String) = CollaborationResearchWorkspace(context).removeGroup(group)
    }
}
