package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.UUID

enum class AgentAttentionDisposition {
    NOTIFY_NOW,
    DAILY_DIGEST,
    SILENT_RECORD,
    DISCARD
}

data class AgentAttentionCandidate(
    val relevance: Double,
    val novelty: Double,
    val credibility: Double,
    val actionability: Double,
    val interruptionCost: Double,
    val tokenCost: Double,
    val batteryCost: Double,
    val urgent: Boolean = false
)

data class AgentAttentionDecision(
    val value: Double,
    val threshold: Double,
    val disposition: AgentAttentionDisposition,
    val reasons: List<String>
)

object AgentAttentionBudgetPolicy {
    fun evaluate(candidate: AgentAttentionCandidate, threshold: Double): AgentAttentionDecision {
        val relevance = candidate.relevance.unit()
        val novelty = candidate.novelty.unit()
        val credibility = candidate.credibility.unit()
        val actionability = candidate.actionability.unit()
        val positive = relevance * novelty * credibility * actionability
        val cost = candidate.interruptionCost.unit() * 0.55 + candidate.tokenCost.unit() * 0.25 +
            candidate.batteryCost.unit() * 0.20
        val value = (positive - cost).coerceIn(-1.0, 1.0)
        val normalizedThreshold = threshold.coerceIn(0.0, 1.0)
        val disposition = when {
            candidate.urgent && value >= normalizedThreshold * 0.75 -> AgentAttentionDisposition.NOTIFY_NOW
            value >= normalizedThreshold -> AgentAttentionDisposition.NOTIFY_NOW
            value >= normalizedThreshold * 0.55 -> AgentAttentionDisposition.DAILY_DIGEST
            value > 0.0 -> AgentAttentionDisposition.SILENT_RECORD
            else -> AgentAttentionDisposition.DISCARD
        }
        return AgentAttentionDecision(
            value = value,
            threshold = normalizedThreshold,
            disposition = disposition,
            reasons = listOf(
                "relevance:${format(relevance)}",
                "novelty:${format(novelty)}",
                "credibility:${format(credibility)}",
                "actionability:${format(actionability)}",
                "interruption_cost:${format(candidate.interruptionCost.unit())}",
                "token_cost:${format(candidate.tokenCost.unit())}",
                "battery_cost:${format(candidate.batteryCost.unit())}"
            )
        )
    }

    private fun Double.unit(): Double = coerceIn(0.0, 1.0)
    private fun format(value: Double): String = String.format(Locale.US, "%.4f", value)
}

enum class AgentKnowledgeGapStatus { OPEN, RESEARCHING, RESOLVED, DISMISSED }

data class AgentKnowledgeGap(
    val id: String = UUID.randomUUID().toString(),
    val topic: String,
    val knownSummary: String,
    val unknownQuestions: List<String>,
    val missingEvidence: List<String>,
    val relatedGoal: String = "",
    val sourceRunIds: List<String> = emptyList(),
    val priority: Double = 0.5,
    val status: AgentKnowledgeGapStatus = AgentKnowledgeGapStatus.OPEN,
    val createdAtMillis: Long = System.currentTimeMillis(),
    val updatedAtMillis: Long = createdAtMillis,
    val recheckAfterMillis: Long = 0L
)

data class AgentDecisionLogEntry(
    val id: String = UUID.randomUUID().toString(),
    val question: String,
    val decision: String,
    val alternatives: List<String>,
    val evidenceRefs: List<String>,
    val rationale: String,
    val relatedGoal: String = "",
    val outcome: String = "pending",
    val outcomeEvidenceRefs: List<String> = emptyList(),
    val createdAtMillis: Long = System.currentTimeMillis(),
    val reviewedAtMillis: Long = 0L
)

class AgentCognitiveGovernanceStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun upsertGap(gap: AgentKnowledgeGap): AgentKnowledgeGap {
        val normalized = gap.copy(
            topic = gap.topic.trim().take(400),
            knownSummary = gap.knownSummary.trim().take(4_000),
            unknownQuestions = gap.unknownQuestions.map(String::trim).filter(String::isNotBlank).distinct().take(20),
            missingEvidence = gap.missingEvidence.map(String::trim).filter(String::isNotBlank).distinct().take(20),
            relatedGoal = gap.relatedGoal.trim().take(1_000),
            sourceRunIds = gap.sourceRunIds.map(String::trim).filter(String::isNotBlank).distinct().takeLast(40),
            priority = gap.priority.coerceIn(0.0, 1.0),
            updatedAtMillis = System.currentTimeMillis()
        )
        require(normalized.topic.isNotBlank() && normalized.unknownQuestions.isNotEmpty()) {
            "Knowledge gap requires a topic and at least one unknown question"
        }
        database.writeString("$GAP_PREFIX${normalized.id}", encodeGap(normalized).toString())
        prune(GAP_PREFIX, MAX_GAPS)
        return normalized
    }

    @Synchronized
    fun gaps(status: AgentKnowledgeGapStatus? = null, limit: Int = MAX_GAPS): List<AgentKnowledgeGap> =
        database.entries(GAP_PREFIX).mapNotNull { decodeGap(it.second) }
            .filter { status == null || it.status == status }
            .sortedWith(compareByDescending<AgentKnowledgeGap> { it.priority }
                .thenByDescending { it.updatedAtMillis })
            .take(limit.coerceIn(1, MAX_GAPS))

    @Synchronized
    fun updateGapStatus(id: String, status: AgentKnowledgeGapStatus): AgentKnowledgeGap? {
        val current = database.readString("$GAP_PREFIX${id.trim()}", "").let(::decodeGap) ?: return null
        return upsertGap(current.copy(status = status))
    }

    @Synchronized
    fun appendDecision(entry: AgentDecisionLogEntry): AgentDecisionLogEntry {
        val normalized = entry.copy(
            question = entry.question.trim().take(2_000),
            decision = entry.decision.trim().take(2_000),
            alternatives = entry.alternatives.map(String::trim).filter(String::isNotBlank).distinct().take(20),
            evidenceRefs = entry.evidenceRefs.map(String::trim).filter(String::isNotBlank).distinct().take(40),
            rationale = entry.rationale.trim().take(4_000),
            relatedGoal = entry.relatedGoal.trim().take(1_000),
            outcome = entry.outcome.trim().lowercase(Locale.ROOT).take(80),
            outcomeEvidenceRefs = entry.outcomeEvidenceRefs.map(String::trim)
                .filter(String::isNotBlank).distinct().take(40)
        )
        require(normalized.question.isNotBlank() && normalized.decision.isNotBlank()) {
            "Decision log requires a question and decision"
        }
        database.writeString("$DECISION_PREFIX${normalized.id}", encodeDecision(normalized).toString())
        prune(DECISION_PREFIX, MAX_DECISIONS)
        return normalized
    }

    @Synchronized
    fun decisions(limit: Int = MAX_DECISIONS): List<AgentDecisionLogEntry> =
        database.entries(DECISION_PREFIX).mapNotNull { decodeDecision(it.second) }
            .sortedByDescending(AgentDecisionLogEntry::createdAtMillis)
            .take(limit.coerceIn(1, MAX_DECISIONS))

    @Synchronized
    fun recordDecisionOutcome(
        id: String,
        outcome: String,
        evidenceRefs: List<String>,
        reviewedAtMillis: Long = System.currentTimeMillis()
    ): AgentDecisionLogEntry? {
        val current = database.readString("$DECISION_PREFIX${id.trim()}", "")
            .let(::decodeDecision) ?: return null
        val updated = current.copy(
            outcome = outcome.trim().lowercase(Locale.ROOT).take(80),
            outcomeEvidenceRefs = evidenceRefs.map(String::trim).filter(String::isNotBlank).distinct().take(40),
            reviewedAtMillis = reviewedAtMillis
        )
        database.writeString("$DECISION_PREFIX${updated.id}", encodeDecision(updated).toString())
        return updated
    }

    private fun prune(prefix: String, max: Int) {
        val entries = database.entries(prefix).mapNotNull { (key, raw) ->
            val timestamp = if (prefix == GAP_PREFIX) decodeGap(raw)?.updatedAtMillis else
                decodeDecision(raw)?.createdAtMillis
            timestamp?.let { key to it }
        }.sortedByDescending { it.second }
        database.removeAll(entries.drop(max).map { it.first })
    }

    private fun encodeGap(value: AgentKnowledgeGap) = JSONObject()
        .put("id", value.id).put("topic", value.topic).put("known_summary", value.knownSummary)
        .put("unknown_questions", JSONArray(value.unknownQuestions))
        .put("missing_evidence", JSONArray(value.missingEvidence))
        .put("related_goal", value.relatedGoal).put("source_run_ids", JSONArray(value.sourceRunIds))
        .put("priority", value.priority).put("status", value.status.name)
        .put("created_at_millis", value.createdAtMillis).put("updated_at_millis", value.updatedAtMillis)
        .put("recheck_after_millis", value.recheckAfterMillis)

    private fun decodeGap(raw: String): AgentKnowledgeGap? = runCatching {
        val json = JSONObject(raw)
        AgentKnowledgeGap(
            id = json.getString("id"), topic = json.getString("topic"),
            knownSummary = json.optString("known_summary"),
            unknownQuestions = json.getJSONArray("unknown_questions").strings(),
            missingEvidence = json.getJSONArray("missing_evidence").strings(),
            relatedGoal = json.optString("related_goal"),
            sourceRunIds = json.getJSONArray("source_run_ids").strings(),
            priority = json.optDouble("priority").coerceIn(0.0, 1.0),
            status = runCatching { AgentKnowledgeGapStatus.valueOf(json.optString("status")) }
                .getOrDefault(AgentKnowledgeGapStatus.OPEN),
            createdAtMillis = json.optLong("created_at_millis"),
            updatedAtMillis = json.optLong("updated_at_millis"),
            recheckAfterMillis = json.optLong("recheck_after_millis")
        )
    }.getOrNull()

    private fun encodeDecision(value: AgentDecisionLogEntry) = JSONObject()
        .put("id", value.id).put("question", value.question).put("decision", value.decision)
        .put("alternatives", JSONArray(value.alternatives)).put("evidence_refs", JSONArray(value.evidenceRefs))
        .put("rationale", value.rationale).put("related_goal", value.relatedGoal)
        .put("outcome", value.outcome).put("outcome_evidence_refs", JSONArray(value.outcomeEvidenceRefs))
        .put("created_at_millis", value.createdAtMillis).put("reviewed_at_millis", value.reviewedAtMillis)

    private fun decodeDecision(raw: String): AgentDecisionLogEntry? = runCatching {
        val json = JSONObject(raw)
        AgentDecisionLogEntry(
            id = json.getString("id"), question = json.getString("question"),
            decision = json.getString("decision"), alternatives = json.getJSONArray("alternatives").strings(),
            evidenceRefs = json.getJSONArray("evidence_refs").strings(), rationale = json.optString("rationale"),
            relatedGoal = json.optString("related_goal"), outcome = json.optString("outcome", "pending"),
            outcomeEvidenceRefs = json.getJSONArray("outcome_evidence_refs").strings(),
            createdAtMillis = json.optLong("created_at_millis"),
            reviewedAtMillis = json.optLong("reviewed_at_millis")
        )
    }.getOrNull()

    private fun JSONArray.strings(): List<String> = buildList {
        for (index in 0 until length()) optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
    }

    private companion object {
        const val DATABASE = "signalasi_cognitive_governance_v1"
        const val GAP_PREFIX = "gap:"
        const val DECISION_PREFIX = "decision:"
        const val MAX_GAPS = 1_000
        const val MAX_DECISIONS = 2_000
    }
}

object AgentKnowledgeGapDetector {
    fun observe(
        store: AgentCognitiveGovernanceStore,
        run: AgentRecordedRun,
        sample: AgentEvalSample
    ): AgentKnowledgeGap? {
        val missing = sample.failureReasons.filter { it.startsWith("missing_evidence:") }
        if (missing.isEmpty()) return null
        val topic = AgentLearningAnalyzer.safeTitle(run.originalRequest)
        val existing = store.gaps(AgentKnowledgeGapStatus.OPEN).firstOrNull {
            AgentLearningAnalyzer.sameTaskFamily(it.topic, topic)
        }
        return store.upsertGap(
            (existing ?: AgentKnowledgeGap(
                topic = topic,
                knownSummary = "A real Agent run was observed but its completion evidence was incomplete.",
                unknownQuestions = listOf("What evidence would prove this task completed correctly?"),
                missingEvidence = emptyList(),
                relatedGoal = run.originalRequest,
                priority = 0.65
            )).copy(
                missingEvidence = (existing?.missingEvidence.orEmpty() + missing.map { it.substringAfter(':') })
                    .distinct(),
                sourceRunIds = (existing?.sourceRunIds.orEmpty() + run.runId).distinct().takeLast(40),
                priority = maxOf(existing?.priority ?: 0.0, if (sample.verdict == AgentEvalVerdict.FAILED) 0.80 else 0.65),
                recheckAfterMillis = System.currentTimeMillis() + 7L * 24L * 60L * 60_000L
            )
        )
    }
}

enum class AgentStandardProtocol(val wireValue: String) { MCP("mcp"), AGENT_SKILLS("agent_skills"), ACP("acp"), A2A("a2a") }
enum class AgentProtocolAdapterState { READY, CONNECTED, NEEDS_SETUP, DISABLED }

data class AgentProtocolAdapterDescriptor(
    val protocol: AgentStandardProtocol,
    val state: AgentProtocolAdapterState,
    val version: String,
    val connectedEndpoints: Int,
    val operations: Set<String>,
    val localPermissionBoundary: Boolean = true
)

interface AgentStandardProtocolAdapter {
    val protocol: AgentStandardProtocol
    fun encodeRequest(request: AgentRunRequest): JSONObject
    fun decodeRequest(payload: JSONObject): AgentRunRequest?
    fun encodeEvent(event: AgentRunControlEvent): JSONObject
}

object AgentA2aBoundaryAdapter : AgentStandardProtocolAdapter {
    override val protocol = AgentStandardProtocol.A2A

    override fun encodeRequest(request: AgentRunRequest): JSONObject = JSONObject()
        .put("jsonrpc", "2.0")
        .put("id", request.runId)
        .put("method", "message/send")
        .put("params", JSONObject()
            .put("contextId", request.conversationId)
            .put("message", JSONObject()
                .put("messageId", request.messageId)
                .put("role", "user")
                .put("parts", JSONArray().put(JSONObject().put("kind", "text").put("text", request.goal)))))

    override fun decodeRequest(payload: JSONObject): AgentRunRequest? = runCatching {
        val params = payload.getJSONObject("params")
        val message = params.getJSONObject("message")
        val parts = message.getJSONArray("parts")
        val text = (0 until parts.length()).mapNotNull { parts.optJSONObject(it)?.optString("text") }
            .joinToString("\n").trim()
        if (text.isBlank()) return null
        AgentRunRequest(
            conversationId = params.optString("contextId").ifBlank { UUID.randomUUID().toString() },
            messageId = message.optString("messageId").ifBlank { UUID.randomUUID().toString() },
            taskId = params.optString("taskId").ifBlank { UUID.randomUUID().toString() },
            runId = payload.optString("id").ifBlank { UUID.randomUUID().toString() },
            goal = text
        )
    }.getOrNull()

    override fun encodeEvent(event: AgentRunControlEvent): JSONObject = JSONObject()
        .put("taskId", event.taskId).put("contextId", event.conversationId)
        .put("kind", "status-update").put("final", event.type in TERMINAL_EVENTS)
        .put("status", JSONObject().put("state", event.type.a2aState()).put("timestamp", event.timestampMillis))

    private fun AgentRunControlEventType.a2aState(): String = when (this) {
        AgentRunControlEventType.RUN_COMPLETED -> "completed"
        AgentRunControlEventType.RUN_FAILED -> "failed"
        AgentRunControlEventType.RUN_CANCELLED -> "canceled"
        AgentRunControlEventType.WAITING_FOR_USER, AgentRunControlEventType.TOOL_PERMISSION_REQUIRED -> "input-required"
        AgentRunControlEventType.WAITING_FOR_DEVICE -> "auth-required"
        else -> "working"
    }

    private val TERMINAL_EVENTS = setOf(
        AgentRunControlEventType.RUN_COMPLETED,
        AgentRunControlEventType.RUN_FAILED,
        AgentRunControlEventType.RUN_CANCELLED
    )
}

object AgentAcpBoundaryAdapter : AgentStandardProtocolAdapter {
    override val protocol = AgentStandardProtocol.ACP

    override fun encodeRequest(request: AgentRunRequest): JSONObject = JSONObject()
        .put("jsonrpc", "2.0").put("id", request.runId).put("method", "session/prompt")
        .put("params", JSONObject()
            .put("sessionId", request.conversationId)
            .put("prompt", JSONArray().put(JSONObject().put("type", "text").put("text", request.goal))))

    override fun decodeRequest(payload: JSONObject): AgentRunRequest? = runCatching {
        val params = payload.getJSONObject("params")
        val prompt = params.getJSONArray("prompt")
        val text = (0 until prompt.length()).mapNotNull { prompt.optJSONObject(it)?.optString("text") }
            .joinToString("\n").trim()
        if (text.isBlank()) return null
        AgentRunRequest(
            conversationId = params.optString("sessionId").ifBlank { UUID.randomUUID().toString() },
            messageId = payload.optString("id").ifBlank { UUID.randomUUID().toString() },
            taskId = params.optString("taskId").ifBlank { UUID.randomUUID().toString() },
            runId = payload.optString("id").ifBlank { UUID.randomUUID().toString() },
            goal = text
        )
    }.getOrNull()

    override fun encodeEvent(event: AgentRunControlEvent): JSONObject = JSONObject()
        .put("jsonrpc", "2.0").put("method", "session/update")
        .put("params", JSONObject().put("sessionId", event.conversationId)
            .put("update", JSONObject().put("sessionUpdate", "agent_message_chunk")
                .put("content", JSONObject().put("type", "text").put("text", event.payload.toString()))))
}

object AgentProtocolAdapterRegistry {
    fun descriptors(context: Context): List<AgentProtocolAdapterDescriptor> {
        val settings = AgentEvalOpsStore(context).settings()
        val enabled = settings.protocolAdaptersEnabled
        val mcp = AgentMcpRegistry(EncryptedAgentMcpStore(context)).list()
        val skills = EncryptedAgentSkillStore(context).list()
        val registrations = EncryptedAgentRegistry(context).list()
        return listOf(
            AgentProtocolAdapterDescriptor(
                AgentStandardProtocol.MCP,
                if (!enabled) AgentProtocolAdapterState.DISABLED else if (mcp.any { it.isCallableNow() }) {
                    AgentProtocolAdapterState.CONNECTED
                } else AgentProtocolAdapterState.READY,
                "negotiated",
                mcp.count { it.isCallableNow() },
                setOf("tools/list", "tools/call", "resources/list", "resources/read")
            ),
            AgentProtocolAdapterDescriptor(
                AgentStandardProtocol.AGENT_SKILLS,
                if (enabled) AgentProtocolAdapterState.READY else AgentProtocolAdapterState.DISABLED,
                "SKILL.md",
                skills.count { it.enabled },
                setOf("import", "export", "review", "sign", "install")
            ),
            AgentProtocolAdapterDescriptor(
                AgentStandardProtocol.ACP,
                if (enabled) AgentProtocolAdapterState.READY else AgentProtocolAdapterState.DISABLED,
                "negotiated",
                registrations.count { it.adapterType.contains("acp", ignoreCase = true) },
                setOf("initialize", "session/new", "session/prompt", "session/cancel", "session/update")
            ),
            AgentProtocolAdapterDescriptor(
                AgentStandardProtocol.A2A,
                if (enabled) AgentProtocolAdapterState.READY else AgentProtocolAdapterState.DISABLED,
                "1.0.0",
                registrations.count { it.adapterType.contains("a2a", ignoreCase = true) },
                setOf("agent-card", "message/send", "message/stream", "tasks/get", "tasks/cancel")
            )
        )
    }

    private fun AgentMcpConnection.isCallableNow(): Boolean = isCallable(System.currentTimeMillis())
}
