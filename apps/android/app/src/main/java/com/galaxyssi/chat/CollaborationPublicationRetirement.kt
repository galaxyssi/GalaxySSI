package com.galaxyssi.chat

import org.json.JSONObject

/** Host-only publication fencing. Enrollment and retirement commit under the workspace lock together. */
internal class CollaborationPublicationRetirement(
    private val rows: CollaborationWorkspaceRows,
    private val access: CollaborationWorkspaceAccess
) {
    fun isRetired(): Boolean {
        val record = read(access.nodeId) ?: return false
        require(record.getString("predecessor_identity") == CollaborationPublicationJournal.identityOf(access)) {
            "Retired publication identity changed"
        }
        return true
    }

    fun enrollmentWrites(stage: CollaborationResearchStage, task: JSONObject?): Map<String, String> {
        require(!isRetired()) { "Publication dispatch was retired; use its recorded successor" }
        val retry = task?.optJSONObject("review_reassignment") ?: return emptyMap()
        require(stage == CollaborationResearchStage.VERIFY && task.getString("operation") == "review" &&
            retry.keys().asSequence().toSet() == setOf("node_id", "reason") && retry.getString("reason").isNotBlank()) {
            "Only a host-assigned replacement review may retire its predecessor"
        }
        val oldNode = retry.getString("node_id")
        require(oldNode != access.nodeId) { "A different predecessor dispatch is required" }
        val old = CollaborationPublicationJournal(rows, access).scopedCandidateContract(oldNode)
        require(JSONObject(old.getString("identity")).getLong("round") <= access.round) { "Predecessor round is in the future" }
        val oldTask = old.getJSONObject("candidate_task")
        val originalCriterion = oldTask.getJSONObject("criterion")
        val criterion = task.getJSONObject("criterion")
        require(old.getString("stage") == CollaborationResearchStage.VERIFY.name && oldTask.getString("operation") == "review" &&
            CollaborationResearchCandidates.same(oldTask.getJSONObject("target"), task.getJSONObject("target")) &&
            listOf("id", "requirement", "verification").all { originalCriterion.getString(it) == criterion.getString(it) } &&
            CollaborationEvidenceRequirements.required(originalCriterion) == CollaborationEvidenceRequirements.required(criterion)) {
            "Review handoff must retain the exact target and original criterion contract"
        }
        val publication = rows.read(prefix() + "publication:" + hash("${access.runId}:$oldNode"))?.let(::JSONObject)
        require(publication?.getJSONObject("result")?.optString("status") != "recorded") {
            "The predecessor published first; reconcile its result instead of repeating it"
        }
        val record = JSONObject().put("predecessor_identity", old.getString("identity"))
            .put("predecessor_contract_sha256", hash(old.toString()))
            .put("successor_identity", CollaborationPublicationJournal.identityOf(access))
            .put("successor_task_sha256", hash(task.toString())).put("reason", retry.getString("reason"))
        val previous = read(oldNode)
        require(previous == null || previous.toString() == record.toString()) { "Another successor already owns this review handoff" }
        return if (previous == null) mapOf(key(oldNode) to envelope(record)) else emptyMap()
    }

    fun requireOwnership(task: JSONObject?) {
        require(!isRetired()) { "Publication dispatch was retired; use its recorded successor" }
        val retry = task?.optJSONObject("review_reassignment") ?: return
        val record = requireNotNull(read(retry.getString("node_id"))) { "Review handoff must be durably enrolled before publication" }
        require(record.getString("successor_identity") == CollaborationPublicationJournal.identityOf(access) &&
            record.getString("successor_task_sha256") == hash(task.toString())) { "Candidate review handoff owner changed" }
        require(CollaborationPublicationJournal(rows, access).contract()?.getJSONObject("candidate_task")?.toString() == task.toString()) {
            "Review handoff contract is missing or changed"
        }
    }

    private fun read(node: String): JSONObject? = rows.read(key(node))?.let { encoded ->
        val envelope = JSONObject(encoded)
        val raw = envelope.getString("payload")
        check(hash(raw) == envelope.getString("sha256")) { "Publication retirement integrity check failed" }
        JSONObject(raw).also { record ->
            val old = JSONObject(record.getString("predecessor_identity"))
            val next = JSONObject(record.getString("successor_identity"))
            require(old.getString("group") == access.groupId && old.getString("run") == access.runId &&
                old.getString("node") == node && old.getString("turn") == access.turnId &&
                next.getString("group") == access.groupId && next.getString("run") == access.runId &&
                next.getString("turn") == access.turnId && next.getString("node") != node) { "Publication retirement scope changed" }
            val journal = CollaborationPublicationJournal(rows, access)
            val oldContract = journal.scopedCandidateContract(node)
            val nextContract = journal.scopedCandidateContract(next.getString("node"))
            require(oldContract.getString("identity") == record.getString("predecessor_identity") &&
                hash(oldContract.toString()) == record.getString("predecessor_contract_sha256") &&
                nextContract.getString("identity") == record.getString("successor_identity") &&
                hash(nextContract.getJSONObject("candidate_task").toString()) == record.getString("successor_task_sha256")) {
                "Publication retirement contract changed"
            }
        }
    }

    private fun prefix() = "group:${hash(access.groupId)}:"
    private fun key(node: String) = prefix() + "retirement:" + hash("${access.runId}:$node")
    private fun hash(value: String) = AgentNativeJsonCodec.sha256(value)
    private fun envelope(value: JSONObject) = value.toString().let { JSONObject().put("payload", it).put("sha256", hash(it)).toString() }
}
