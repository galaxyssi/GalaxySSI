package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Append-only candidate planning over a host snapshot. Does not commit, grant access or dispatch. */
internal object CollaborationCandidateLiveGraph {
    const val PRODUCERS = "producer_work_ids"
    private const val SAVED_PRODUCERS = "candidate_live_producers"

    enum class Status {
        UNKNOWN, QUEUED, RUNNING, SUCCEEDED, FAILED, CANCELLED, SKIPPED;
        val terminal get() = this in setOf(SUCCEEDED, FAILED, CANCELLED, SKIPPED)
    }
    enum class Control { RUN, PAUSE, STOP }

    data class Node<T>(val workId: String, val dispatchId: String, val personId: String, val status: Status, val original: T)
    data class Snapshot<T>(val groupId: String, val runId: String, val turnId: String, val generation: Long,
        val nodes: List<Node<T>>, val visibleWorkIds: Set<String>, val completedOutputs: Map<String, String>,
        val control: Control, val maxNewDispatches: Int)
    data class Addition(val work: JSONObject, val dispatchId: String, val dependencyDispatchIds: Set<String>)
    data class Plan<T>(val retained: Snapshot<T>, val additions: List<Addition>, val state: String,
        val deferredRequests: List<JSONObject> = emptyList(), val feedback: String = "", val error: Boolean = false)

    fun <T> plan(workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess, people: Set<String>,
        criteria: JSONArray, requests: JSONArray, previous: String, snapshot: Snapshot<T>,
        dispatchId: (String) -> String): Plan<T> = runCatching {
        require(snapshot.groupId == access.groupId && snapshot.runId == access.runId && snapshot.turnId == access.turnId &&
            snapshot.generation >= 0 && snapshot.maxNewDispatches >= 0) { "Live candidate snapshot scope or host admission budget is invalid" }
        val byWork = snapshot.nodes.associateBy { it.workId }
        val byDispatch = snapshot.nodes.associateBy { it.dispatchId }
        require(byWork.size == snapshot.nodes.size && byDispatch.size == snapshot.nodes.size && snapshot.nodes.all {
            it.workId.isNotBlank() && it.dispatchId.isNotBlank() && it.personId.isNotBlank()
        }) { "Live candidate graph contains invalid or duplicate identities" }
        require(snapshot.visibleWorkIds.all { it in byWork }) { "Visible work must belong to the current graph" }
        val checkpoint = CollaborationCandidateVerificationState.checkpoint(previous)
        val saved = checkpoint.cycles
        val cycles = (0 until saved.length()).map { saved.getJSONObject(it) }.toMutableList()
        val indexes = cycles.mapIndexed { index, cycle -> cycle.getString("object_id") to index }.toMap().toMutableMap()
        cycles.forEach { cycle ->
            require(cycle.getString("id") == AgentNativeJsonCodec.sha256(JSONArray(listOf(access.runId, access.turnId,
                cycle.getString("object_id"))).toString())) { "Saved candidate cycle belongs to another goal scope" }
            producers(cycle, SAVED_PRODUCERS)
        }
        val pending = CollaborationCandidateVerificationState.requests(checkpoint.pendingRequests, requests).filter { request ->
            val target = request.optJSONObject("target")
            val existing = target?.optString("object_id")?.let { indexes[it] }?.let(cycles::get)
            CollaborationCandidateReviewRetry.relevant(existing, request)
        }
        if (snapshot.control != Control.RUN) return@runCatching Plan(snapshot, emptyList(),
            CollaborationCandidateVerificationState.encode(JSONArray(cycles), pending), pending,
            "Candidate planning held by durable ${snapshot.control}")
        val additions = mutableListOf<Addition>()
        val deferred = mutableListOf<JSONObject>()
        val feedback = mutableListOf<String>()
        val workIds = byWork.keys.toMutableSet()
        val dispatchIds = byDispatch.keys.toMutableSet()

        fun scoped(producerIds: Set<String>): CollaborationWorkspaceAccess {
            val nodes = producerIds.map { id ->
                require(id in snapshot.visibleWorkIds) { "Producer $id is not current visible work" }
                byWork.getValue(id).also {
                    require(it.status == Status.SUCCEEDED) { "Producer $id has not succeeded; keep the request pending" }
                    require(it.dispatchId in access.dependencyNodes) { "Producer $id has no host-granted read dependency" }
                }
            }
            // Never inherit broad coordinator dependency access or its own-node exception into a worker.
            return access.copy(nodeId = "", dependencyNodes = nodes.mapTo(linkedSetOf()) { it.dispatchId })
        }

        fun append(result: CollaborationCandidateEvolution.Plan, producerIds: Set<String>): JSONObject {
            require(!result.error) { result.feedback }
            val next = CollaborationCandidateVerificationState.read(result.state).getJSONObject(0)
            require(result.work.size <= 1) { "A candidate transition may append only one dispatch" }
            result.work.forEach { item ->
                val workId = item.getString("id")
                val node = next.getString("node_id")
                check(workIds.add(workId) && node.isNotBlank() && dispatchIds.add(node)) {
                    "Candidate append collides with an existing work or dispatch identity; reconcile the host snapshot"
                }
                item.put("depends_on", JSONArray(producerIds.toList())).put("dependency_policy", "success")
                additions += Addition(item, node, producerIds.mapTo(linkedSetOf()) { byWork.getValue(it).dispatchId })
            }
            next.put(SAVED_PRODUCERS, JSONArray(producerIds.toList()))
            if (result.feedback.isNotBlank()) feedback += result.feedback
            return next
        }

        cycles.indices.forEach { index ->
            val cycle = cycles[index]
            if (cycle.getString("phase") == "done") return@forEach
            val node = byDispatch[cycle.getString("node_id")]
            if (node == null) {
                feedback += "${cycle.getString("object_id")}: dispatch state is unavailable; retain it without retry or failure"
                return@forEach
            }
            val member = cycle.getString(if (cycle.getString("phase") == "repair") "editor" else "reviewer")
            require(node.workId == CollaborationCandidateEvolution.workId(cycle) && node.personId == member) {
                "Candidate dispatch no longer matches its saved work/member identity"
            }
            if (!node.status.terminal) return@forEach
            val producerIds = producers(cycle, SAVED_PRODUCERS) + if (node.status == Status.SUCCEEDED) setOf(node.workId) else emptySet()
            val view = runCatching { scoped(producerIds) }.getOrElse {
                feedback += "${cycle.getString("object_id")}: ${it.message}"
                return@forEach
            }
            val result = CollaborationCandidateEvolution.plan(workspace, view, people, criteria, JSONArray(),
                JSONArray().put(cycle).toString(), if (node.status == Status.SUCCEEDED) setOf(node.dispatchId) else emptySet(), dispatchId)
            if (result.error) feedback += result.feedback
            else if (result.work.size > snapshot.maxNewDispatches - additions.size)
                feedback += "${cycle.getString("object_id")}: next transition remains pending for host admission capacity"
            else cycles[index] = append(result, producerIds)
        }

        pending.forEach { request ->
            if (additions.size >= snapshot.maxNewDispatches) { deferred += request; return@forEach }
            val objectId = request.optJSONObject("target")?.optString("object_id").orEmpty()
            val existingIndex = indexes[objectId]
            val existing = existingIndex?.let(cycles::get)
            if (existing != null && existing.getString("phase") != "done") { deferred += request; return@forEach }
            val admission = runCatching {
                val producerIds = producers(request, PRODUCERS)
                val view = scoped(producerIds)
                val result = CollaborationCandidateEvolution.plan(workspace, view, people, criteria,
                    JSONArray().put(request), existing?.let { JSONArray().put(it).toString() } ?: "[]", emptySet(), dispatchId)
                require(!result.error && CollaborationCandidateVerificationState.checkpoint(result.state).pendingRequests.length() == 0 &&
                    CollaborationCandidateVerificationState.read(result.state).length() == 1) { result.feedback }
                // Explicit producers must include the original target producer, not just unrelated visible work.
                if (producerIds.isNotEmpty()) {
                    val target = request.getJSONObject("target")
                    val original = requireNotNull(workspace.read(view, objectId, target.getInt("revision")))
                    require(original.getString("node_id") in view.dependencyNodes) { "Explicit producers do not include the exact candidate producer" }
                    require(byDispatch.getValue(original.getString("node_id")).personId == original.getString("person_id")) {
                        "Candidate producer author does not match the saved original"
                    }
                }
                result to producerIds
            }
            val admitted = admission.getOrElse {
                deferred += request
                feedback += "$objectId: ${it.message}"
                return@forEach
            }
            val next = append(admitted.first, admitted.second)
            if (existingIndex != null) cycles[existingIndex] = next else {
                indexes[objectId] = cycles.size
                cycles += next
            }
        }
        val state = CollaborationCandidateVerificationState.encode(JSONArray(cycles), deferred)
        CollaborationCandidateVerificationState.read(state)
        Plan(snapshot, additions, if (state == CollaborationCandidateVerificationState.encode(saved,
            (0 until checkpoint.pendingRequests.length()).map { checkpoint.pendingRequests.getJSONObject(it) })) previous else state,
            deferred, feedback.joinToString("\n"))
    }.getOrElse { Plan(snapshot, emptyList(), previous,
        (0 until requests.length()).mapNotNull { requests.optJSONObject(it)?.let { request -> JSONObject(request.toString()) } },
        it.message ?: "Invalid candidate live graph", error = true) }

    private fun producers(value: JSONObject, key: String): Set<String> {
        if (!value.has(key)) return emptySet()
        val refs = value.getJSONArray(key)
        return (0 until refs.length()).map { refs.getString(it).also { id -> require(id.isNotBlank()) { "Empty producer work ID" } } }
            .also { require(it.distinct().size == it.size) { "Duplicate producer work IDs" } }.toCollection(linkedSetOf())
    }
}
