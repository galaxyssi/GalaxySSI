package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Observer-only archive. Reading originals here is not a model/peer read or verification. */
internal class CollaborationAdaptivePilotMilestones(
    private val groupId: String,
    private val runId: String,
    private val turnId: String,
    private val workspace: CollaborationResearchWorkspace,
    private val readEvidence: (CollaborationWorkspaceAccess, JSONObject) -> JSONObject?
) {
    private val records = linkedMapOf<String, JSONObject>()

    fun capture(checkpoint: AgentTeamExecutionCheckpoint): JSONObject {
        require(checkpoint.request.conversationId == groupId && checkpoint.request.runId == runId &&
            checkpoint.request.messageId == turnId) { "Archive checkpoint belongs to another trial" }
        val members = checkpoint.definition.members
        require(members.all { it.context["collaboration_group_id"] == groupId }) { "Mixed archive group" }
        val record = AgentTeamExecutionRecord(checkpoint.definition, checkpoint.request)
        val access = CollaborationMilestoneDispatch.access(record, members.single { it.memberId == checkpoint.definition.primaryMemberId })
        val producers = members.filter { it.context[CollaborationGoalLoop.ROSTER] != "true" }.associateBy { it.memberId }
        val pending = linkedMapOf<String, JSONObject>()
        val seen = records.keys.toMutableSet()
        while (true) {
            val page = workspace.pendingMilestones(access, seen, producers.keys)
            if (page.isEmpty()) break
            page.forEach { milestone ->
                val token = milestone.getString("token")
                check(seen.add(token)) { "Archive pagination repeated a milestone" }
                val producer = producers.getValue(milestone.getString("producer_node"))
                require(producer.context[CollaborationResearchWorkflow.PERSON] == milestone.getString("person_id")) {
                    "Archive producer attribution changed"
                }
                val scope = CollaborationMilestoneDispatch.access(record, producer).copy(
                    pinnedReads = CollaborationMilestoneDispatch.strings(milestone.getJSONArray("grants").toString()))
                val revisions = JSONArray()
                val observations = linkedMapOf<String, JSONObject>()
                val refs = milestone.getJSONArray("revisions")
                repeat(refs.length()) { index ->
                    val ref = refs.getJSONObject(index)
                    val original = requireNotNull(workspace.read(scope, ref.getString("object_id"), ref.getInt("revision"))) {
                        "Published original unavailable during archive"
                    }
                    require(CollaborationResearchCandidates.same(original, ref)) { "Published original identity changed" }
                    revisions.put(original)
                    val evidence = original.getJSONArray("host_observations")
                    repeat(evidence.length()) { at ->
                        val observationRef = evidence.getJSONObject(at)
                        val id = observationRef.getString("evidence_id")
                        val observation = requireNotNull(readEvidence(scope, observationRef)) { "Published observation unavailable during archive" }
                        require(observation.getString("evidence_id") == id &&
                            observation.getString("sha256") == observationRef.getString("sha256")) { "Published observation identity changed" }
                        observations[id] = observation
                    }
                }
                pending[token] = JSONObject().put("group_id", groupId).put("run_id", runId).put("turn_id", turnId)
                    .put("round", access.round).put("milestone", milestone).put("originals", revisions)
                    .put("observations", JSONArray(observations.values.toList()))
            }
        }
        records.putAll(pending)
        return snapshot()
    }

    fun snapshot() = JSONObject().put("format", "galaxyssi.adaptive-pilot-milestones.v1")
        .put("capture_role", "test_observer_not_agent").put("peer_read_proven", false)
        .put("scientific_acceptance_proven", false)
        .put("milestones", JSONArray(records.values.map { JSONObject(it.toString()) }))

    companion object {
        fun executionStore(context: Context, database: AgentEncryptedDatabase) = EncryptedAgentTeamExecutionStore(context, database)
    }
}
