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
    val repairing: Boolean get() = latest?.getJSONObject("receipt")?.optString("status") == "rejected"

    fun accept(raw: String): Boolean {
        val normalized = raw.trim()
        val receipt = workspace.submitPublication(access, normalized)
        latest = requireNotNull(workspace.publicationCheckpoint(access))
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
            "Preserve valid content and evidence; never invent missing receipts or claim unperformed work. " +
            "A new review/event needs a new stable local id and an empty object_id; it must not change the candidate's kind. " +
            "An edit uses the existing object's exact object_id/base_revision and preserves its kind. " +
            "Review repair basis belongs in body.candidate.basis, not resolves. " +
            "Return the corrected JSON only. Host validation error: " + state.getJSONObject("receipt").optString("reason") +
            "\n" + CollaborationResearchArtifact.instructions(stage) +
            contract.optJSONObject("candidate_task")?.let { "\nExact host candidate task: $it" }.orEmpty()
    }

    fun backoffMillis(): Long = if (!repairing) 0 else
        (1_000L shl (latest!!.getLong("sequence") - 1).coerceIn(0L, 6L).toInt()).coerceAtMost(60_000L)

    fun permitsTool(name: String): Boolean = !repairing || name == CollaborationCloudRecall.NAME

    companion object {
        fun create(context: Context, access: CollaborationWorkspaceAccess): CollaborationPublicationRecovery? {
            val workspace = CollaborationResearchWorkspace(context)
            return if (workspace.publicationContract(access) == null) null else CollaborationPublicationRecovery(workspace, access)
        }
    }
}
