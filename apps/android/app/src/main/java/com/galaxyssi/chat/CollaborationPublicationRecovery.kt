package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** A rejected draft stays inside its original assignment; only the host can accept it. */
internal class CollaborationPublicationRecovery(
    private val workspace: CollaborationResearchWorkspace,
    private val access: CollaborationWorkspaceAccess
) {
    private val contract = requireNotNull(workspace.publicationContract(access))
    private val stage = CollaborationResearchStage.valueOf(contract.getString("stage"))
    var latest: JSONObject? = workspace.publicationCheckpoint(access)
        private set
    init { workspace.requirePublicationActive(access) }
    val repairing: Boolean get() = latest?.getJSONObject("receipt")?.optString("status") == "rejected"

    fun resumeAssistance() {
        workspace.publicationAssistance(access)?.let { request ->
            throw CollaborationPublicationAssistanceException(access.nodeId, request.toString())
        }
    }

    fun accept(raw: String, revalidate: Boolean = false): Boolean {
        val normalized = raw.trim()
        if (!revalidate && repairing) {
            val request = runCatching { JSONObject(normalized) }.getOrNull()
            if (request?.optString("format") == CollaborationPublicationAssistance.FORMAT) {
                workspace.publicationAssistance(access, request)
                resumeAssistance()
            }
        }
        val receipt = workspace.submitPublication(access, normalized, revalidate)
        latest = requireNotNull(workspace.publicationCheckpoint(access))
        check(!receipt.optBoolean("retired")) { "This publication was retired; do not retry or repair it" }
        check(latest!!.getString("raw") == normalized && latest!!.getJSONObject("receipt").toString() == receipt.toString()) {
            "A different publication already owns this assignment"
        }
        return receipt.getString("status") == "recorded"
    }

    fun feedback(): String {
        val state = requireNotNull(latest)
        require(repairing)
        return "The host rejected this publication; no part of this draft was committed. " +
            "Correct the complete structured response for the SAME assignment and author. " +
            "Do not rerun experiments, search, generate files, change the goal or lower its acceptance criteria. " +
            "Only scoped collaboration_recall is available to read already saved originals and references. " +
            "You choose whether to correct this yourself, inspect saved evidence, or ask the coordinator for help. " +
            "Do not guess repeatedly or resubmit unchanged work without a reason it could pass. " +
            "There is no retry-count rule. If help is appropriate, return " +
            "{\"format\":\"${CollaborationPublicationAssistance.FORMAT}\",\"diagnosis\":\"specific obstacle and uncertainty\"," +
            "\"attempted_corrections\":\"what you tried and what the host reported\",\"requested_help\":\"concrete assistance or alternative to consider\"}. " +
            "The host preserves the complete draft and sends this request to the coordinator; it does not grant permissions or complete the goal. " +
            "Preserve valid content and evidence; never invent missing receipts or claim unperformed work. " +
            "A new review/event needs a new stable local id and an empty object_id; it must not change the candidate's kind. " +
            "An edit uses the existing object's exact object_id/base_revision and preserves its kind. " +
            "Review repair basis belongs in body.candidate.basis, not resolves. " +
            "Return either the corrected publication JSON or an assistance request JSON. Host validation error: " +
            state.getJSONObject("receipt").optString("reason") +
            "\nHost-observed problem state (not a recovery decision): " + (state.optJSONObject("problem_state") ?:
                CollaborationPublicationProblem.observe(state.getString("raw"), state.getJSONObject("receipt"), null)) +
            "\n" + CollaborationResearchArtifact.instructions(stage) +
            contract.optJSONObject("candidate_task")?.let { "\nExact host candidate task: $it" }.orEmpty()
    }

    fun backoffMillis(): Long = if (!repairing) 0 else
        (1_000L shl (latest!!.getLong("sequence") - 1).coerceIn(0L, 6L).toInt()).coerceAtMost(60_000L)

    fun permitsTool(name: String): Boolean {
        workspace.requirePublicationActive(access)
        return !repairing || name == CollaborationCloudRecall.NAME
    }

    companion object {
        fun create(context: Context, access: CollaborationWorkspaceAccess): CollaborationPublicationRecovery? {
            val workspace = CollaborationResearchWorkspace(context)
            return if (workspace.publicationContract(access) == null) null else CollaborationPublicationRecovery(workspace, access)
        }
    }
}

/** A member-selected handoff, not a host retry-count cutoff. */
internal class CollaborationPublicationAssistanceException(node: String, request: String) : IllegalStateException(
    "$CODE: the member requested help for publication node $node: $request. " +
        "The complete draft and observations remain saved; the goal is NOT complete. " +
        "Coordinator should assess the request and choose the next action; do not repeat executed tools or experiments merely to repair a handoff."
) {
    companion object { const val CODE = "COLLABORATION_PUBLICATION_ASSISTANCE" }
}

internal object CollaborationPublicationAssistance {
    const val FORMAT = "galaxyssi.publication-assistance.v1"
    fun validate(request: JSONObject) {
        require(request.optString("format") == FORMAT)
        require(request.keys().asSequence().toSet() == setOf("format", "diagnosis", "attempted_corrections", "requested_help"))
        listOf("diagnosis", "attempted_corrections", "requested_help").forEach {
            require(request.opt(it) is String && request.getString(it).isNotBlank()) { "Assistance request needs $it" }
        }
    }
}
