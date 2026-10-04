package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Host-owned delivery facts, independent of model execution success and scientific acceptance. */
data class CollaborationDeliveryReceipt(
    val status: String,
    val archiveRecordId: String,
    val originalSha256: String,
    val reason: String = ""
) {
    fun encode(): JSONObject = JSONObject().put("status", status).put("archive_record_id", archiveRecordId)
        .put("original_sha256", originalSha256).put("reason", reason)
        .put("goal_acceptance", "not_implied")

    companion object {
        fun decode(value: JSONObject?): CollaborationDeliveryReceipt? = value?.let {
            if (it.optString("status") !in setOf("recorded", "not_required", "rejected")) null else
                CollaborationDeliveryReceipt(it.getString("status"), it.optString("archive_record_id"),
                    it.optString("original_sha256"), it.optString("reason"))
        }
    }
}

/** The same durable finalization is used for live replies and replies recovered after process death. */
internal class CollaborationResultFinalizer(
    private val workspace: CollaborationResearchWorkspace,
    private val archive: (AgentTeamMemberExecutionContext, String) -> String,
    private val evidence: (AgentTeamMemberExecutionContext) -> JSONArray = { JSONArray() },
    private val acceptance: (CollaborationWorkspaceAccess, String, String, String) -> CollaborationAcceptanceReceipt? = { _, _, _, _ -> null }
) {
    constructor(context: Context) : this(CollaborationResearchWorkspace(context),
        { execution, raw -> CollaborationResearchArchive(context,
            execution.member.context["collaboration_group_id"].orEmpty()).record(execution, raw) },
        { execution -> AndroidCollaborationRemoteEvidence.summary(context, execution) },
        { access, raw, criteria, goal -> CollaborationGoalAcceptance(context).evaluate(access, raw, criteria, goal) })

    fun finish(execution: AgentTeamMemberExecutionContext, output: AgentSubagentOutput): AgentSubagentOutput {
        val group = execution.member.context["collaboration_group_id"].orEmpty()
        if (group.isBlank()) return output
        val archiveId = archive(execution, output.content)
        val stage = CollaborationResearchWorkflow.stage(execution.member) ?: return output
        if (CollaborationLiveGraph.planner(execution.member)) return output
        val access = CollaborationWorkspaceAccess.from(execution)
        val artifact = CollaborationResearchArtifact.decode(output.content)
        artifact?.remove("workspace_receipt")
        artifact?.remove("remote_evidence_import")
        artifact?.remove("delivery_receipt")
        artifact?.remove("archive_record_id")
        val remote = evidence(execution)
        if (remote.length() > 0) artifact?.put("remote_evidence_import", remote)
        val publication = if (stage != CollaborationResearchStage.DELIVER) {
            if (workspace.publicationContract(access) != null) workspace.submitPublication(access, output.content.trim())
            else workspace.publish(access, output.content,
                candidateTask = execution.member.context[CollaborationCandidateEvolution.TASK]?.takeIf(String::isNotBlank)?.let(::JSONObject))
        } else JSONObject()
        val recorded = publication.optString("status") == "recorded" &&
            (publication.optJSONArray("revisions")?.length() ?: 0) > 0
        val delivery = CollaborationDeliveryReceipt(
            status = if (stage == CollaborationResearchStage.DELIVER) "not_required"
                else if (recorded) "recorded" else "rejected",
            archiveRecordId = archiveId, originalSha256 = AgentNativeJsonCodec.sha256(output.content),
            reason = publication.optString("reason").ifBlank {
                if (stage != CollaborationResearchStage.DELIVER && !recorded)
                    CollaborationResearchArtifact.validationError(output.content).ifBlank { "No versioned workspace delivery was recorded" }
                else ""
            })
        val accepted = if (stage == CollaborationResearchStage.DELIVER &&
            execution.member.context[CollaborationGoalLoop.ENABLED] == "1" &&
            CollaborationGoalLoop.decode(output.content)?.optString("decision") == "achieved")
            acceptance(access, output.content, execution.request.context[CollaborationGoalLoop.CRITERIA]?.toString() ?: "[]",
                execution.request.goal) else null
        if (stage == CollaborationResearchStage.DELIVER)
            return output.copy(collaborationAcceptance = accepted, collaborationDelivery = delivery)
        val handoff = artifact ?: JSONObject(CollaborationResearchArtifact.handoff(output.content, stage))
        handoff.put("workspace_receipt", publication).put("delivery_receipt", delivery.encode())
        if (archiveId.isNotBlank()) handoff.put("archive_record_id", archiveId)
        if (delivery.status == "rejected") handoff.put("delivery_warning",
            "Execution ended, but delivery was not accepted: ${delivery.reason}. " +
                (if (archiveId.isNotBlank()) "Original output is archived. " else "Original archive is unavailable. ") +
                "Plan a targeted repair using a new work id and repair_of; do not repeat completed side effects.")
        return output.copy(content = CollaborationResearchArtifact.compactHandoff(handoff.toString(), archiveId),
            collaborationAcceptance = accepted, collaborationDelivery = delivery)
    }
}
