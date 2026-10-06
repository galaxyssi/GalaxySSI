package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.chat.voice.modelstream.ModelCallAuditSink
import org.json.JSONObject

/** Host-only accounting, deliberately separate from model-authored evidence and prompt context. */
internal class CollaborationModelCallLedger(
    private val rows: CollaborationWorkspaceRows,
    private val now: () -> Long = System::currentTimeMillis,
    private val authorized: (CollaborationWorkspaceAccess) -> Boolean = { true }
) {
    constructor(context: Context) : this(object : CollaborationWorkspaceRows {
        private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)
        override fun read(key: String): String? {
            val value = database.readString(key, "").takeIf(String::isNotBlank)
            check(value != null || !database.contains(key)) { "Model accounting row is unreadable" }
            return value
        }
        override fun commit(values: Map<String, String>) = database.mutateStrings(values)
        override fun page(prefix: String, after: String, limit: Int) = database.keysAfter(prefix, after, limit)
    }, authorized = { access -> CollaborationEvidenceLedger(context.applicationContext).authorizes(access) })

    fun sink(access: CollaborationWorkspaceAccess): ModelCallAuditSink {
        require(listOf(access.groupId, access.runId, access.turnId, access.nodeId, access.personId).all(String::isNotBlank))
        return object : ModelCallAuditSink {
            override fun singleHttpRequest(): Boolean = synchronized(LOCK) {
                check(authorized(access)) { "Model accounting access revoked" }
                trial(access.groupId, access.runId) != null
            }
            override fun write(receipt: JSONObject) = record(access, receipt)
        }
    }

    private fun record(access: CollaborationWorkspaceAccess, receipt: JSONObject) = synchronized(LOCK) {
        check(authorized(access)) { "Model accounting access revoked" }
        val id = receipt.getString("call_id")
        require(ID.matches(id) && receipt.getString("format") == "galaxyssi.model-call.v1")
        val key = prefix(access.groupId, access.runId) + id
        val initialKey = "$key:admission"
        val old = rows.read(key)?.let(::JSONObject)
        val payload = JSONObject(receipt.toString()).put("group_id", access.groupId).put("run_id", access.runId)
            .put("turn_id", access.turnId).put("round", access.round).put("node_id", access.nodeId).put("person_id", access.personId)
        val initial = rows.read(initialKey)?.let(::JSONObject)
        if (initial == null) {
            check(old == null && payload.getString("status") == "started") { "Model admission receipt is missing" }
            val writes = linkedMapOf(key to payload.toString(), initialKey to payload.toString())
            trial(access.groupId, access.runId)?.let { trial ->
                val policy = requireOpen(trial)
                policy.requireRequest(payload)
                val admitted = CollaborationTrialPolicy.strictLong(trial.get("admitted"))
                if (admitted >= policy.maxRequestAdmissions) CollaborationTrialPolicy.deny("request_admissions_exhausted")
                writes[trialKey(access.groupId, access.runId)] = trial.put("admitted", admitted + 1).toString()
            }
            // The debit and admission share the same durable transaction and lock across members.
            rows.commit(writes)
        } else {
            if (payload.getString("status") == "started" && trial(access.groupId, access.runId) != null)
                CollaborationTrialPolicy.deny("admission_replay")
            listOf("call_id", "request_id", "provider", "transport", "requested_model", "request_sha256", "started_at",
                "group_id", "run_id", "turn_id", "round", "node_id", "person_id").forEach {
                val same = if (it == "round" || it == "started_at") initial.getLong(it) == payload.getLong(it)
                    else initial.get(it) == payload.get(it)
                check(same) { "Model call identity changed: $it" }
            }
            if (initial.has("single_http_request")) check(initial.get("single_http_request") == payload.opt("single_http_request")) {
                "Model call admission mode changed"
            }
            if (initial.has("request_controls")) check(initial.getJSONObject("request_controls").toString() ==
                payload.optJSONObject("request_controls")?.toString()) { "Model request controls changed" }
            check(old != null) { "Model receipt index is incomplete" }
            if (old.toString() != payload.toString()) {
                check(old.getString("status") == "started" && payload.getString("status") in TERMINAL) {
                    "A settled model receipt is immutable"
                }
                rows.commit(mapOf(key to payload.toString()))
            }
        }
    }

    fun configureTrial(group: String, run: String, policy: CollaborationTrialPolicy) = synchronized(LOCK) {
        require(group.isNotBlank() && run.isNotBlank())
        val key = trialKey(group, run)
        val existing = trial(group, run)
        if (existing != null) {
            check(CollaborationTrialPolicy.from(existing.getJSONObject("policy")) == policy) { "Trial policy is immutable" }
            return@synchronized
        }
        check(rows.page(prefix(group, run), "", 1).isEmpty()) { "Cannot attach a budget after model dispatch" }
        val created = now()
        require(created >= 0 && policy.admitUntilMillis > created)
        rows.commit(mapOf(key to JSONObject().put("policy", policy.json()).put("created_at", created)
            .put("admitted", 0L).put("closed", false).toString()))
    }

    fun requireTrialTarget(access: CollaborationWorkspaceAccess, target: String, adapterType: String): Boolean = synchronized(LOCK) {
        val trial = trial(access.groupId, access.runId) ?: return@synchronized false
        val policy = requireOpen(trial)
        policy.requireTarget(target, adapterType)
        if (CollaborationTrialPolicy.strictLong(trial.get("admitted")) >= policy.maxRequestAdmissions)
            CollaborationTrialPolicy.deny("request_admissions_exhausted")
        true
    }

    fun trialSnapshot(group: String, run: String): JSONObject? = synchronized(LOCK) { trial(group, run) }

    fun resourceObservation(execution: AgentTeamMemberExecutionContext): AgentTeamResourceObservation? = synchronized(LOCK) {
        val access = CollaborationWorkspaceAccess.from(execution)
        check(authorized(access)) { "Model accounting access revoked" }
        val trial = trial(access.groupId, access.runId) ?: return@synchronized null
        val policy = CollaborationTrialPolicy.from(trial.getJSONObject("policy"))
        val current = now()
        val created = CollaborationTrialPolicy.strictLong(trial.get("created_at"))
        val remaining = if (current >= created) (policy.admitUntilMillis - current).coerceAtLeast(0) else null
        val admitted = CollaborationTrialPolicy.strictLong(trial.get("admitted"))
        AgentTeamResourceObservation.capture(execution, AgentTeamResourceObservation.Unit.HTTP_REQUEST,
            policy.maxRequestAdmissions.toLong(), admitted, current, remaining,
            trial.getBoolean("closed") || remaining == 0L || current < created || admitted >= policy.maxRequestAdmissions,
            AgentTeamResourceObservation.Window.ADMISSION)
    }

    fun closeTrial(group: String, run: String) = synchronized(LOCK) {
        trial(group, run)?.let { rows.commit(mapOf(trialKey(group, run) to it.put("closed", true).toString())) }
    }

    private fun trial(group: String, run: String) = rows.read(trialKey(group, run))?.let(::JSONObject)
    private fun requireOpen(trial: JSONObject): CollaborationTrialPolicy {
        val policy = CollaborationTrialPolicy.from(trial.getJSONObject("policy"))
        val created = CollaborationTrialPolicy.strictLong(trial.get("created_at"))
        val current = now()
        val closed = trial.get("closed")
        check(closed is Boolean) { "Trial closure state is not a boolean" }
        if (closed) CollaborationTrialPolicy.deny("trial_closed")
        if (current < created) CollaborationTrialPolicy.deny("clock_moved_before_admission_window")
        if (current >= policy.admitUntilMillis) CollaborationTrialPolicy.deny("admission_window_expired")
        return policy
    }

    /** Local export only. Entries left at started remain unknown after process death. */
    fun page(group: String, run: String, after: String = ""): Pair<List<JSONObject>, String?> = synchronized(LOCK) {
        require(group.isNotBlank() && run.isNotBlank())
        val prefix = prefix(group, run)
        require(after.isEmpty() || after.startsWith(prefix) && ID.matches(after.removePrefix(prefix)))
        // Admission records sort directly after their call. Read two rows per call, plus lookahead.
        val keys = rows.page(prefix, after, 202).filterNot { it.endsWith(":admission") }
        val selected = keys.take(100)
        selected.map { key -> JSONObject(requireNotNull(rows.read(key))) } to
            selected.lastOrNull()?.takeIf { keys.size > selected.size }
    }

    companion object {
        private const val DATABASE = "galaxyssi_collaboration_model_calls_v1"
        private val LOCK = Any()
        private val ID = Regex("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}")
        private val TERMINAL = setOf("completed", "failed", "cancelled", "interrupted")
        private fun groupPrefix(group: String) = "group:${AgentNativeJsonCodec.sha256(group)}:"
        private fun prefix(group: String, run: String) = groupPrefix(group) + "run:${AgentNativeJsonCodec.sha256(run)}:"
        private fun trialKey(group: String, run: String) = groupPrefix(group) + "trial:${AgentNativeJsonCodec.sha256(run)}"
        fun remove(context: Context, group: String) = synchronized(LOCK) {
            val db = AgentEncryptedDatabase(context.applicationContext, DATABASE)
            db.mutateStrings(emptyMap(), db.keys(groupPrefix(group)))
        }
    }
}
