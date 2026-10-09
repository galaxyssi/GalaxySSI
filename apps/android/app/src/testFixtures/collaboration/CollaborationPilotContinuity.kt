package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal data class CollaborationPilotContinuitySpec(
    val studyId: String, val phase: Long, val previousReportSha256: String, val retainHistory: Boolean
) {
    companion object {
        fun from(value: JSONObject): CollaborationPilotContinuitySpec {
            require(value.keys().asSequence().toSet() == setOf("study_id", "phase", "previous_report_sha256", "retain_history"))
            val id = value.get("study_id") as? String ?: error("Study ID must be a string")
            require(id.matches(Regex("[a-zA-Z0-9][a-zA-Z0-9_-]{0,47}")))
            val phase = CollaborationTrialPolicy.strictLong(value.get("phase"))
            require(phase in 1 until Long.MAX_VALUE)
            val previous = value.get("previous_report_sha256") as? String ?: error("Previous report hash required")
            require(if (phase == 1L) previous.isEmpty() else previous.matches(Regex("[a-f0-9]{64}")))
            val retain = value.get("retain_history") as? Boolean ?: error("Explicit history disposition required")
            return CollaborationPilotContinuitySpec(id, phase, previous, retain)
        }
    }
}

/** Test-only ownership journal; never supplies methods, old answers or a replacement model prompt. */
internal class CollaborationPilotContinuity(
    private val read: (String) -> String?,
    private val write: (String, String) -> Unit
) {
    data class Lease(val studyId: String, val phase: Long, val pilotId: String, val protocolSha256: String,
                     val groupId: String, val retainHistory: Boolean) {
        fun descriptor() = JSONObject().put("study_id", studyId).put("phase", phase)
            .put("history_policy", "unchanged_product_group_memory_and_archive")
            .put("history_disposition", if (retainHistory) "retain" else "release_after_archive")
            .put("fresh_run_and_turn", true).put("old_answers_injected_by_harness", false)
            .put("fresh_provider_thread_verified", false)
            .put("autonomous_retrieval_proven", false).put("retained_learning_proven", false)
    }

    fun open(plan: CollaborationAdaptivePilotPlan, protocolSha256: String, createGroup: () -> String,
             groupExists: (String) -> Boolean, reportDigest: (String) -> String): Lease = synchronized(LOCK) {
        val spec = requireNotNull(plan.continuity)
        require(protocolSha256.matches(Regex("[a-f0-9]{64}")))
        val key = key(spec.studyId)
        val prior = read(key)?.let(::JSONObject)
        val signature = signature(plan)
        val group = if (spec.phase == 1L) {
            require(prior == null) { "Study already reserved; inspect its original phase, do not restart it" }
            ""
        } else {
            requireNotNull(prior) { "No retained study; cannot adopt an arbitrary conversation" }
            require(prior.getString("state") == "ready" && prior.getLong("phase") + 1 == spec.phase) {
                "Prior phase is not safely archived or the requested phase is out of order"
            }
            require(prior.getString("signature") == signature) { "Study model, device or original roster changed" }
            require(prior.getString("report_sha256") == spec.previousReportSha256 &&
                reportDigest(prior.getString("pilot_id")) == spec.previousReportSha256) { "Predecessor report changed" }
            require(prior.getString("pilot_id") != plan.id) { "Each phase requires a fresh pilot identity" }
            prior.getString("group_id").also { require(it.isNotBlank() && groupExists(it)) { "Retained group no longer exists" } }
        }
        val next = JSONObject().put("format", "galaxyssi.pilot-continuity.v1").put("study_id", spec.studyId)
            .put("phase", spec.phase).put("pilot_id", plan.id).put("protocol_sha256", protocolSha256)
            .put("signature", signature).put("group_id", group).put("state", "reserved")
            .put("previous_report_sha256", spec.previousReportSha256)
        // Reserve before any creation or model work. A crashed phase is not silently re-executed.
        write(key, next.toString())
        val owned = group.ifBlank { createGroup().also { require(it.isNotBlank() && groupExists(it)) } }
        next.put("group_id", owned).put("state", "active")
        write(key, next.toString())
        Lease(spec.studyId, spec.phase, plan.id, protocolSha256, owned, spec.retainHistory)
    }

    fun finish(lease: Lease, report: JSONObject, reportSha256: String) = synchronized(LOCK) {
        require(reportSha256.matches(Regex("[a-f0-9]{64}")))
        val key = key(lease.studyId)
        val current = JSONObject(requireNotNull(read(key)))
        require(current.getString("state") == "active" && current.getLong("phase") == lease.phase &&
            current.getString("pilot_id") == lease.pilotId && current.getString("group_id") == lease.groupId &&
            current.getString("protocol_sha256") == lease.protocolSha256) { "Phase ownership changed" }
        require(report.getString("pilot_id") == lease.pilotId && report.getString("conversation_id") == lease.groupId &&
            report.getString("protocol_sha256") == lease.protocolSha256 &&
            report.getString("run_id") == "adaptive-pilot-${lease.pilotId}" &&
            report.getString("turn_id") == "turn-adaptive-pilot-${lease.pilotId}" && report.getBoolean("finished"))
        val safe = report.optBoolean("cleanup_confirmed") && report.optBoolean("milestone_archive_complete") &&
            report.optString("durable_control") == "STOP" && report.getJSONArray("pending_remote_owners").length() == 0
        val state = if (!safe) "blocked" else if (lease.retainHistory) "ready" else "closed"
        current.put("state", state).put("report_sha256", reportSha256)
            .put("last_verdict", report.getString("test_verdict"))
        write(key, current.toString())
    }

    private fun signature(plan: CollaborationAdaptivePilotPlan): String = CollaborationRemotePilotDispatch.sha256(
        JSONObject().put("device", plan.deviceModel).put("target", plan.targetId).put("mode", plan.executionMode)
            .put("model", plan.selection.modelId).put("effort", plan.selection.reasoningEffort.wireValue)
            .put("members", JSONArray(plan.members.map { JSONObject().put("id", it.id).put("name", it.name).put("role", it.role) }))
            .toString().toByteArray(Charsets.UTF_8))

    companion object {
        private val LOCK = Any()
        const val DATABASE = "galaxyssi_test_pilot_continuity_v1"
        private fun key(study: String) = "study:$study"
    }
}
