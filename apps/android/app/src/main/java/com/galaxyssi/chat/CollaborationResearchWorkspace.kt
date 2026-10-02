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
    private val accessAuthorized: (CollaborationWorkspaceAccess) -> Boolean = { true }
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
        })

    data class Page(val revisions: List<JSONObject>, val next: String?)

    fun publish(access: CollaborationWorkspaceAccess, raw: String, now: Long = System.currentTimeMillis()): JSONObject = synchronized(LOCK) {
        require(access.groupId.isNotBlank() && access.runId.isNotBlank() && access.turnId.isNotBlank() &&
            access.personId.isNotBlank() && access.nodeId.isNotBlank()) { "A host-owned research identity is required" }
        if (!authorized(access.groupId)) return@synchronized failure("Group access was removed")
        val artifact = CollaborationResearchArtifact.decode(raw) ?: return@synchronized JSONObject()
        val changes = artifact.optJSONArray("workspace") ?: return@synchronized JSONObject()
        val prefix = prefix(access.groupId)
        val publicationKey = prefix + "publication:" + digest("${access.runId}:${access.nodeId}")
        val inputHash = digest(raw)
        rows.read(publicationKey)?.let { saved ->
            val prior = JSONObject(saved)
            return@synchronized if (prior.getString("input_sha256") == inputHash) prior.getJSONObject("result") else
                failure("A different result already owns this dispatch; create new work for a revision")
        }
        val writes = linkedMapOf<String, String>()
        val result = runCatching {
            val refs = JSONArray()
            val changedIds = hashSetOf<String>()
            repeat(changes.length()) { index ->
                val item = changes.getJSONObject(index)
                val requestedId = item.optString("object_id")
                val localId = item.optString("id")
                require(requestedId.isNotBlank() || localId.isNotBlank() && localId.length <= 160) { "New objects need a stable local id" }
                val id = requestedId.ifBlank { digest("${access.groupId}:${access.personId}:$localId") }
                require(id.matches(ID) && changedIds.add(id)) { "Invalid or duplicated object ID" }
                val kind = item.getString("kind")
                require(kind in KINDS) { "Unknown workspace object kind" }
                val title = item.getString("title")
                require(title.isNotBlank() && title.length <= 240) { "A concise object title is required" }
                val body = item.getJSONObject("body")
                require(body.length() > 0) { "An empty status message is not a research object" }
                CollaborationReviewContract.validate(kind, body)
                val headKey = prefix + "head:" + id
                val head = rows.read(headKey)?.let(::JSONObject)
                require(requestedId.isBlank() == (head == null)) { "Use a new local id to create, or an existing host object_id to revise" }
                val base = item.optInt("base_revision", 0)
                require(base == (head?.getInt("revision") ?: 0)) { "Version conflict for $id; inspect the current revision before editing" }
                require(head == null || access.canRead(head)) { "Current independent work cannot be read or overwritten" }
                require(head == null || head.getString("kind") == kind) { "An object's kind cannot be changed" }
                if (head != null && kind == CollaborationReviewContract.KIND) {
                    val previous = requireNotNull(read(access, id, base)) { "Previous review is missing or isolated" }
                    require(previous.toString() == head.toString()) { "Review head integrity check failed" }
                    require(previous.getString("person_id") == access.personId) { "Only the review author may revise their typed review" }
                    require(reviewBinding(previous.getJSONObject("body")) == reviewBinding(body)) {
                        "A typed review revision must retain its review type, exact target and criterion binding"
                    }
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
                    if (links === resolves) require(linked.getString("kind") in setOf("counterexample", "question")) {
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
                revision.put("sha256", digest(revision.toString()))
                writes[revisionKey(prefix, id, base + 1)] = revision.toString()
                writes[headKey] = revision.toString()
                refs.put(reference(revision))
            }
            JSONObject().put("status", "recorded").put("revisions", refs)
                .put("trust", "authorship_and_version_recorded_not_scientifically_verified")
        }.getOrElse { writes.clear(); failure(it.message ?: "Invalid workspace update") }
        // Heads and the fence token must become visible in the same storage transaction.
        if (writes.isNotEmpty()) writes[mutationKey(access.groupId)] = newMutationToken()
        writes[publicationKey] = JSONObject().put("input_sha256", inputHash).put("result", result).toString()
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
            candidate?.let(::reference)
        }
        Page(revisions, selected.lastOrNull()?.takeIf { keys.size > selected.size })
    }

    companion object {
        private val LOCK = Any()
        private const val DATABASE = "galaxyssi_collaboration_workspace_v1"
        private val ID = Regex("[a-f0-9]{64}")
        val KINDS = setOf("hypothesis", "evidence", "counterexample", "proposal", "experiment", "artifact", "decision", "question", CollaborationReviewContract.KIND)
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
        }

        fun remove(context: Context, group: String) = CollaborationResearchWorkspace(context).removeGroup(group)
    }
}
