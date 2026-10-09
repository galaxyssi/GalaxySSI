package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.chat.voice.modelstream.ModelStreamProvider
import org.json.JSONArray
import org.json.JSONObject

internal object CollaborationMilestoneTool {
    const val NAME = "collaboration_publish"
    const val MAX_BYTES = 128 * 1024
    const val DESCRIPTION = "Publish a useful interim research artifact without ending your assignment. " +
        "Only host-enrolled research assignments can publish; coordination/assessment dispatches return their required response instead. " +
        "Use mode=status when availability is unknown; it reports the current assignment without mutation. " +
        "An unavailable capability is not invalid artifact JSON and cannot be repaired by retrying publication. " +
        "mode=publish requires stable milestone_id and artifact (a JSON string using galaxyssi.research-artifact.v1 with versioned workspace evidence). " +
        CollaborationMilestoneCoordination.INSTRUCTIONS +
        "Include format, nonblank summary and workspace; empty top-level candidates/findings may be omitted and decode as []. " +
        "Supplied arrays and typed workspace bodies remain validated; defaults do not supply evidence. " +
        "Retry the identical ID and artifact after an uncertain response; accepted IDs are immutable. " +
        "Use a new ID and exact object_id/base_revision for a substantive revision. " +
        "mode=list with optional cursor recovers this assignment's committed milestone IDs; follow next_cursor. " +
        "mode=receipt with milestone_id and artifact_sha256 (SHA-256 of the exact artifact UTF-8 string, not the journal raw_sha256) reads the original receipt without republishing. " +
        "Only an explicit not_recorded result permits retrying the saved artifact; a failed lookup leaves the outcome uncertain. " +
        "In your final research-artifact use milestones:[saved IDs] to include those original versions without creating them again. " +
        "Recording authorship is not verification, task completion or a guarantee a peer has read the artifact. " +
        "Specialized host candidate-transition assignments must use their final publication contract. " +
        "One request is limited to 131072 UTF-8 bytes; split larger independent deliveries into separate milestones, never truncate evidence."

    fun schema() = JSONObject().put("type", "object").put("additionalProperties", false)
        .put("required", JSONArray(listOf("mode")))
        .put("properties", JSONObject()
            .put("mode", JSONObject().put("type", "string").put("enum", JSONArray(listOf("publish", "list", "status", "receipt"))))
            .put("milestone_id", JSONObject().put("type", "string").put("maxLength", 160))
            .put("artifact", JSONObject().put("type", "string"))
            .put("artifact_sha256", JSONObject().put("type", "string").put("pattern", "^[a-f0-9]{64}$"))
            .put("cursor", JSONObject().put("type", "string").put("maxLength", 512)))

    fun install(prepared: PreparedCloudConversationStream) {
        val function = JSONObject().put("name", NAME).put("description", DESCRIPTION)
        val tools = prepared.body.optJSONArray("tools") ?: JSONArray().also { prepared.body.put("tools", it) }
        when (prepared.provider) {
            ModelStreamProvider.OPENAI_COMPATIBLE -> tools.put(JSONObject().put("type", "function").put("function", function.put("parameters", schema())))
            ModelStreamProvider.ANTHROPIC -> tools.put(function.put("input_schema", schema()))
            ModelStreamProvider.GEMINI -> tools.put(JSONObject().put("functionDeclarations", JSONArray()
                .put(function.put("parameters", schema().apply { remove("additionalProperties") }))))
        }
    }

    fun validate(input: JSONObject) {
        require(input.toString().toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "Publication exceeds 131072 UTF-8 bytes; split independent artifacts, do not truncate" }
        when (input.opt("mode")) {
            "status" -> require(input.keys().asSequence().toSet() == setOf("mode")) { "Status accepts only mode; authority comes from the host assignment" }
            "publish" -> {
                require(input.keys().asSequence().toSet() == setOf("mode", "milestone_id", "artifact")) { "Publish requires only mode, milestone_id and artifact" }
                require(input.opt("milestone_id") is String && input.opt("artifact") is String && input.getString("artifact").isNotBlank()) { "milestone_id and artifact must be nonblank strings" }
                CollaborationMilestoneJournal.validateId(input.getString("milestone_id"))
            }
            "receipt" -> {
                require(input.keys().asSequence().toSet() == setOf("mode", "milestone_id", "artifact_sha256") &&
                    input.opt("milestone_id") is String && input.opt("artifact_sha256") is String &&
                    input.getString("artifact_sha256").matches(Regex("[a-f0-9]{64}"))) { "Receipt requires only mode, milestone_id and lowercase artifact_sha256" }
                CollaborationMilestoneJournal.validateId(input.getString("milestone_id"))
            }
            "list" -> require(input.keys().asSequence().all { it in setOf("mode", "cursor") } &&
                (!input.has("cursor") || input.opt("cursor") is String && input.getString("cursor").length <= 512)) { "List accepts only mode and an optional cursor" }
            else -> throw IllegalArgumentException("mode must be publish, list, status or receipt")
        }
    }

    internal fun unavailable(mode: String) = JSONObject().put("success", false).put("status", "unavailable")
        .put("assignment_completed", false).put("error", when (mode) {
            "status" -> "Publication capability status unavailable; no artifact was submitted. " +
                "Continue the required assignment response; a transport failure does not grant publication."
            "list" -> "Saved milestone list unavailable; this read submitted no artifact. Retry listing after reconnecting. " +
                "Do not infer that an earlier publication failed or repeat completed effects."
            "receipt" -> "Saved publication receipt unavailable; this read submitted no artifact. Retry the exact receipt lookup after reconnecting. " +
                "The original publication outcome remains uncertain; do not repeat completed effects."
            "publish" -> "Publication outcome is uncertain; retry the same milestone_id and artifact, or list saved milestones. " +
                "Do not repeat completed effects."
            else -> "Milestone operation unavailable; inspect the requested operation before retrying."
        })

    fun execute(context: Context, access: CollaborationWorkspaceAccess, input: JSONObject): String =
        execute(CollaborationResearchWorkspace(context), access, input) {
            require(AgentTeamDurableControl(context).get(access.runId) == AgentTeamUserControl.RUN &&
                CollaborationGroupStore(context).load(access.groupId)?.members?.any { it.id == access.personId } == true) {
                "Assignment is paused, stopped or no longer authorized"
            }
        }.toString()

    internal fun execute(workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess,
                         input: JSONObject, active: () -> Unit): JSONObject = try {
        validate(input)
        active()
        workspace.requirePublicationActive(access)
        val capability = workspace.publicationCapability(access)
        when {
            input.getString("mode") == "status" -> JSONObject().put("success", true).put("status", "returned")
                .put("capability", capability).put("assignment_completed", false)
            input.getString("mode") == "publish" && !capability.getBoolean("publish_allowed") ->
                JSONObject().put("success", false).put("status", "unavailable")
                    .put("error_code", capability.getString("reason_code")).put("error", capability.getString("guidance"))
                    .put("capability", capability).put("retryable", false).put("artifact_validated", false)
                    .put("assignment_completed", false)
            else -> {
                val result = when (input.getString("mode")) {
                    "list" -> workspace.milestones(access, input.optString("cursor"))
                    "receipt" -> workspace.milestoneReceipt(access, input.getString("milestone_id"), input.getString("artifact_sha256"))
                    else -> workspace.publishMilestone(access, input.getString("milestone_id"), input.getString("artifact"))
                }
                JSONObject(result.toString()).put("success", result.optString("status") in setOf("recorded", "returned", "not_recorded"))
                    .put("assignment_completed", false)
            }
        }
    } catch (error: IllegalArgumentException) {
        JSONObject().put("success", false).put("status", "rejected").put("error", error.message)
            .put("assignment_completed", false)
    }
}
