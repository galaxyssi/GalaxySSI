package com.galaxyssi.chat

import java.util.concurrent.ConcurrentHashMap
import org.json.JSONArray
import org.json.JSONObject

/** Local deterministic fixture shared by JVM and encrypted-device runtime tests; no providers or physical tools. */
internal class CandidateRuntimeFixture(rows: CollaborationWorkspaceRows, evidenceRows: CollaborationWorkspaceRows) {
    val ledger = CollaborationEvidenceLedger(evidenceRows)
    val workspace = CollaborationResearchWorkspace(rows, evidence = ledger::references, evidenceReadCoverage = ledger::requireReadCoverage)
    val access = CollaborationWorkspaceAccess("candidate-fixture", "candidate-run", "candidate-turn", 4, "final", "lead")
    val criterion = JSONObject().put("id", "accuracy").put("requirement", "Documented accuracy")
        .put("verification", "documentary").put("status", "open").put("evidence_kind", "observed").put("evidence", JSONArray())
        .put("required_observations", JSONArray().put(JSONObject().put("origin", "android_cloud_tool").put("tool", "original_check")))
    val targets = ConcurrentHashMap<String, JSONObject>()
    val source by lazy { ledger.record(access.copy(nodeId = "source", personId = "author", round = 0),
        "fixture-invocation", "original_check", "{}", "{\"value\":17}", 1, 2) }

    fun record(): AgentTeamExecutionRecord {
        val people = listOf("lead", "author", "reviewer-a", "reviewer-b", "editor", "slow-person").map { person ->
            AgentTeamMember("local-fixture", AgentDeliveryMode.IGNORE, instanceId = person, context = mapOf(
                CollaborationGoalLoop.ENABLED to "1", CollaborationLiveGraph.ENABLED to "1", CollaborationGoalLoop.ROSTER to "true",
                CollaborationResearchWorkflow.PERSON to person, CollaborationResearchWorkflow.STAGE to "DELIVER",
                "collaboration_group_id" to access.groupId, "collaboration_name" to person))
        }
        fun work(person: String, id: String) = people.single { it.memberId == person }.let {
            it.copy(instanceId = id, deliveryMode = AgentDeliveryMode.OBSERVE, objective = id,
                context = it.context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to id,
                    CollaborationResearchWorkflow.STAGE to "EXECUTE", CollaborationWorkGraph.POLICY to "success"))
        }
        val nodes = listOf(work("author", "producer"), work("slow-person", "slow"))
        val final = people.first().copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
            dependsOnAgentIds = setOf("producer", "slow"), context = people.first().context + (CollaborationGoalLoop.ROSTER to "false"))
        return AgentTeamExecutionRecord(AgentTeamDefinition("candidate-team", "local-fixture", people + nodes + final,
            primaryInstanceId = "final"), AgentRunRequest(access.groupId, access.turnId, "candidate-task", runId = access.runId,
            goal = "Check two candidate documents without waiting for unrelated work", context = mapOf(
                CollaborationGoalLoop.ROUND to "4", CollaborationGoalLoop.CRITERIA to JSONArray().put(criterion).toString(),
                CollaborationGoalLoop.HOST_ACCEPTANCE to "1")))
    }

    fun produce(): String {
        val items = listOf("a", "b").map { candidate(it) }
        val raw = raw(items)
        val result = workspace.publish(access.copy(nodeId = "producer", personId = "author"), raw)
        check(result.optString("status") == "recorded") { result.toString() }
        val revisions = result.getJSONArray("revisions")
        listOf("a", "b").forEachIndexed { index, id -> targets[id] = revisions.getJSONObject(index) }
        return raw
    }

    fun expansion(enroll: Boolean = false) = JSONObject().put("format", CollaborationLiveGraph.FORMAT)
        .put("summary", "Check alternatives independently").put("work", JSONArray())
        .put(CollaborationCandidateEvolution.REQUESTS, JSONArray().apply {
            if (enroll) listOf("a", "b").forEach { id -> put(JSONObject().put("target", targets.getValue(id))
                .put("criterion_id", "accuracy").put("editor", "editor").put("reviewer", "reviewer-$id")
                .put(CollaborationCandidateLiveGraph.PRODUCERS, JSONArray().put("producer"))) }
        }).toString()

    fun execute(member: AgentTeamMember, outcome: String = "supported"): String {
        val task = JSONObject(member.context.getValue(CollaborationCandidateEvolution.TASK))
        val target = task.getJSONObject("target")
        val who = access.copy(nodeId = member.memberId, personId = task.getString("member"), dependencyNodes = member.dependsOnAgentIds)
        workspace.replayCandidateTask(who, task)?.let { return it.toString() }
        CollaborationCandidateEvolution.checkTask(workspace, who, task)
        workspace.enrollPublication(who, if (task.getString("operation") == "review")
            CollaborationResearchStage.VERIFY else CollaborationResearchStage.REVISE, task)
        val raw = draft(member, outcome)
        val result = workspace.publish(who, raw, candidateTask = task)
        check(result.optString("status") == "recorded") { result.toString() }
        return raw
    }

    fun draft(member: AgentTeamMember, outcome: String = "supported"): String {
        val task = JSONObject(member.context.getValue(CollaborationCandidateEvolution.TASK))
        val target = task.getJSONObject("target")
        val who = access.copy(nodeId = member.memberId, personId = task.getString("member"), dependencyNodes = member.dependsOnAgentIds)
        if (task.getString("operation") == "review") check(requireNotNull(ledger.readPage(who, source.getString("evidence_id"),
            source.getString("sha256"))).next == null)
        val item = if (task.getString("operation") == "review") JSONObject()
            .put("id", "review-${member.memberId}").put("kind", "candidate_event").put("title", "Independent documentary check")
            .put("observations", JSONArray().put(source)).put("body", JSONObject().put("candidate_event", JSONObject()
                .put("operation", "review").put("targets", JSONArray().put(target)).put("criterion", criterion.getString("requirement"))
                .put("check", "Compare exact saved source").put("rationale", "Local fixture, not scientific validation")
                .put("outcome", outcome).put("unresolved", JSONArray().apply { if (outcome == "refuted") put("Revise the original") })))
        else candidate("repair").put("object_id", target.getString("object_id")).put("base_revision", target.getInt("revision"))
            .put("parents", JSONArray().put(target)).apply {
                getJSONObject("body").put("content", "Revised original with documented correction")
                getJSONObject("body").getJSONObject("candidate").put("operation", "revise").put("basis", task.getJSONObject("basis"))
            }
        return raw(listOf(item))
    }

    fun assessment() = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Documentary routes settled; goal still needs acceptance")
        .put("decision", "continue").put("criteria", JSONArray().put(criterion)).put("work", JSONArray()).put("blockers", JSONArray()).toString()

    private fun candidate(id: String) = JSONObject().put("id", id).put("kind", "candidate").put("title", "Alternative $id")
        .put("observations", JSONArray().put(source)).put("body", JSONObject().put("content", "Full original $id")
            .put("candidate", JSONObject().put("operation", "propose").put("rationale", "Different documented route")
                .put("criteria", JSONArray().put(criterion.getString("requirement")))))

    private fun raw(items: List<JSONObject>) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Saved local fixture evidence").put("candidates", JSONArray()).put("findings", JSONArray())
        .put("workspace", JSONArray(items)).toString()
}
