package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
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

data class AgentAttentionDecisionRecord(
    val messageId: String,
    val decision: AgentAttentionDecision,
    val relatedGoal: String,
    val whyNow: String,
    val impactIfIgnored: String,
    val createdAtMillis: Long = System.currentTimeMillis()
)

class AgentAttentionDecisionStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun get(messageId: String): AgentAttentionDecisionRecord? = decode(
        database.readString("$KEY_PREFIX${messageId.trim()}", "")
    )

    @Synchronized
    fun save(value: AgentAttentionDecisionRecord) {
        database.writeString("$KEY_PREFIX${value.messageId}", JSONObject()
            .put("message_id", value.messageId)
            .put("value", value.decision.value)
            .put("threshold", value.decision.threshold)
            .put("disposition", value.decision.disposition.name)
            .put("reasons", JSONArray(value.decision.reasons))
            .put("related_goal", value.relatedGoal)
            .put("why_now", value.whyNow)
            .put("impact_if_ignored", value.impactIfIgnored)
            .put("created_at_millis", value.createdAtMillis)
            .toString())
        prune()
    }

    @Synchronized
    fun list(limit: Int = MAX_RECORDS): List<AgentAttentionDecisionRecord> = database.entries(KEY_PREFIX)
        .mapNotNull { decode(it.second) }
        .sortedByDescending(AgentAttentionDecisionRecord::createdAtMillis)
        .take(limit.coerceIn(1, MAX_RECORDS))

    private fun prune() {
        val retained = list(MAX_RECORDS).mapTo(hashSetOf()) { "$KEY_PREFIX${it.messageId}" }
        database.removeAll(database.keys(KEY_PREFIX).filterNot(retained::contains))
    }

    private fun decode(raw: String): AgentAttentionDecisionRecord? = runCatching {
        val json = JSONObject(raw)
        AgentAttentionDecisionRecord(
            messageId = json.getString("message_id"),
            decision = AgentAttentionDecision(
                value = json.optDouble("value"),
                threshold = json.optDouble("threshold"),
                disposition = runCatching {
                    AgentAttentionDisposition.valueOf(json.optString("disposition"))
                }.getOrDefault(AgentAttentionDisposition.SILENT_RECORD),
                reasons = json.optJSONArray("reasons").strings()
            ),
            relatedGoal = json.optString("related_goal"),
            whyNow = json.optString("why_now"),
            impactIfIgnored = json.optString("impact_if_ignored"),
            createdAtMillis = json.optLong("created_at_millis")
        )
    }.getOrNull()

    private fun JSONArray?.strings(): List<String> = buildList {
        if (this@strings == null) return@buildList
        for (index in 0 until length()) optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
    }

    private companion object {
        const val DATABASE = "signalasi_attention_decisions_v1"
        const val KEY_PREFIX = "decision:"
        const val MAX_RECORDS = 2_000
    }
}

object AgentAttentionBudgetRuntime {
    fun decide(
        context: Context,
        message: GlobalProactiveMessage,
        threshold: Double
    ): AgentAttentionDecisionRecord {
        val store = AgentAttentionDecisionStore(context)
        store.get(message.id)?.let { return it }
        val device = AgentDeviceEvalProbe.capture(context)
        val actionTerms = listOf("建议", "风险", "机会", "recommend", "risk", "opportunity", "should")
        val candidate = AgentAttentionCandidate(
            relevance = when (message.target) {
                GlobalProactiveTarget.CURRENT_CONVERSATION -> 0.97
                GlobalProactiveTarget.NEW_CONVERSATION -> 0.90
                GlobalProactiveTarget.GLOBAL_DIGEST -> 0.72
            },
            novelty = if (System.currentTimeMillis() - message.createdAtMillis <= 24L * 60L * 60_000L) 0.96 else 0.72,
            credibility = if (message.causalEventIds.isNotEmpty()) 0.96 else 0.72,
            actionability = if (actionTerms.any { message.content.contains(it, ignoreCase = true) }) 0.96 else 0.62,
            interruptionCost = when {
                message.urgent -> 0.10
                message.target == GlobalProactiveTarget.CURRENT_CONVERSATION -> 0.20
                message.target == GlobalProactiveTarget.NEW_CONVERSATION -> 0.38
                else -> 0.12
            },
            tokenCost = (message.content.length / 4_000.0).coerceIn(0.03, 0.75),
            batteryCost = when {
                device.deviceIdleMode -> 0.95
                device.powerSaveMode -> 0.72
                device.batteryPercent in 0..15 -> 0.80
                else -> 0.10
            },
            urgent = message.urgent
        )
        val decision = AgentAttentionBudgetPolicy.evaluate(candidate, threshold)
        return AgentAttentionDecisionRecord(
            messageId = message.id,
            decision = decision,
            relatedGoal = message.topic,
            whyNow = if (message.urgent) {
                "A time-sensitive risk or conflict was detected for ${message.topic}."
            } else {
                "New evidence became relevant to ${message.topic}."
            },
            impactIfIgnored = if (message.urgent) {
                "The current plan may continue with an unresolved material risk."
            } else {
                "A useful decision or follow-up may be delayed."
            }
        ).also(store::save)
    }
}

object AgentCognitiveEvalBridge {
    fun recordFeedback(
        context: Context,
        repository: GlobalAgentRepository,
        dedupeKey: String,
        kind: GlobalAgentFeedbackKind
    ): Int {
        val normalizedKey = dedupeKey.trim()
        val digestPrefix = "global-agent-digest:"
        val messagePrefix = "global-agent:"
        val groupId = when {
            normalizedKey.startsWith(digestPrefix) -> normalizedKey.removePrefix(digestPrefix)
            normalizedKey.startsWith(messagePrefix) -> normalizedKey.removePrefix(messagePrefix)
            else -> return 0
        }
        if (groupId.isBlank()) return 0
        val allMessages = repository.proactiveMessages()
        val targets = if (normalizedKey.startsWith(digestPrefix)) {
            allMessages.filter { it.deliveryGroupId == groupId }
        } else {
            allMessages.filter { it.id == groupId }
        }
        if (targets.isEmpty()) return 0
        val now = System.currentTimeMillis()
        targets.forEach { message ->
            val feedback = GlobalAgentFeedback(
                proactiveMessageId = message.id,
                deliveryGroupId = message.deliveryGroupId.ifBlank { groupId },
                conversationId = message.deliveredConversationId.ifBlank { message.sourceConversationId },
                topic = message.topic,
                target = message.target,
                kind = kind,
                createdAtMillis = now
            )
            repository.replaceFeedback(feedback)
            recordEvalFeedback(context, message, kind)
            repository.enqueue(GlobalConversationEvent(
                id = "global-feedback:${message.id}:${feedback.id}",
                type = GlobalConversationEventType.USER_FEEDBACK,
                conversationId = feedback.conversationId,
                messageId = message.id,
                actor = GlobalConversationActor.USER,
                timestampMillis = now,
                content = kind.name.lowercase(),
                contentRef = "encrypted://global-agent-feedback/${feedback.id}",
                conversationTitle = message.topic,
                topicHints = setOf(message.topic).filter(String::isNotBlank).toSet(),
                metadata = mapOf(
                    "feedback_kind" to kind.name,
                    "proactive_message_id" to message.id,
                    "delivery_group_id" to feedback.deliveryGroupId
                )
            ))
        }
        val ids = targets.map(GlobalProactiveMessage::id).toSet()
        repository.saveProactiveMessages(allMessages.map { message ->
            if (message.id !in ids) return@map message
            message.copy(
                status = when (kind) {
                    GlobalAgentFeedbackKind.HELPFUL -> if (message.deliveredAtMillis > 0L) {
                        GlobalProactiveMessageStatus.DELIVERED
                    } else GlobalProactiveMessageStatus.PENDING
                    GlobalAgentFeedbackKind.NOT_RELEVANT,
                    GlobalAgentFeedbackKind.TOO_FREQUENT -> GlobalProactiveMessageStatus.DISMISSED
                },
                viewedAtMillis = now
            )
        })
        GlobalConversationEventBus.requestProcessing(context.applicationContext)
        return targets.size
    }

    private fun recordEvalFeedback(
        context: Context,
        message: GlobalProactiveMessage,
        kind: GlobalAgentFeedbackKind
    ) {
        val values = when (kind) {
            GlobalAgentFeedbackKind.HELPFUL -> true to true
            GlobalAgentFeedbackKind.NOT_RELEVANT -> false to false
            GlobalAgentFeedbackKind.TOO_FREQUENT -> true to false
        }
        val store = AgentEvalOpsStore(context)
        store.recordProactiveFeedback(
            store.proactiveRunId(message.id),
            relevant = values.first,
            accepted = values.second
        )
    }

    fun shouldNotify(context: Context, message: GlobalProactiveMessage): Boolean {
        val threshold = AgentEvalOpsStore(context).settings().attentionThreshold
        return AgentAttentionBudgetRuntime.decide(context, message, threshold).decision.disposition ==
            AgentAttentionDisposition.NOTIFY_NOW
    }

    fun recordDelivered(context: Context, messages: List<GlobalProactiveMessage>) {
        if (messages.isEmpty()) return
        val store = AgentEvalOpsStore(context)
        val threshold = store.settings().attentionThreshold
        messages.forEach { message ->
            store.recordProactiveDelivery(
                message,
                AgentAttentionBudgetRuntime.decide(context, message, threshold)
            )
        }
    }
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
        val topic = AgentLearningAnalyzer.safeTitle(run.originalRequest)
        val existing = store.gaps().firstOrNull {
            it.status in setOf(AgentKnowledgeGapStatus.OPEN, AgentKnowledgeGapStatus.RESEARCHING) &&
            AgentLearningAnalyzer.sameTaskFamily(it.topic, topic)
        }
        if (missing.isEmpty()) {
            return existing?.takeIf { sample.passed }?.let { gap ->
                store.updateGapStatus(gap.id, AgentKnowledgeGapStatus.RESOLVED)
            }
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

internal object AgentKnowledgeGapResearchPolicy {
    fun shouldQueue(
        gap: AgentKnowledgeGap,
        autonomousResearchEnabled: Boolean,
        duplicateExists: Boolean,
        nowMillis: Long = System.currentTimeMillis()
    ): Boolean = autonomousResearchEnabled &&
        !duplicateExists &&
        gap.status == AgentKnowledgeGapStatus.OPEN &&
        gap.priority >= MIN_PRIORITY &&
        (gap.recheckAfterMillis <= 0L || gap.recheckAfterMillis >= nowMillis)

    private const val MIN_PRIORITY = 0.75
}

object AgentKnowledgeGapResearchBridge {
    fun observe(context: Context, gap: AgentKnowledgeGap) {
        val appContext = context.applicationContext
        val governance = AgentCognitiveGovernanceStore(appContext)
        if (gap.status == AgentKnowledgeGapStatus.RESOLVED) {
            governance.decisions().filter { "knowledge-gap:${gap.id}" in it.evidenceRefs }
                .filter { it.outcome == "pending" }
                .forEach { decision ->
                    governance.recordDecisionOutcome(
                        decision.id,
                        outcome = "resolved",
                        evidenceRefs = gap.sourceRunIds.map { "run:$it" }
                    )
                }
            return
        }
        val repository = GlobalAgentRepository(appContext)
        val sourceEventId = "knowledge-gap:${gap.id}"
        val existing = repository.researchTasks()
        if (!AgentKnowledgeGapResearchPolicy.shouldQueue(
                gap = gap,
                autonomousResearchEnabled = repository.settings().let {
                    it.enabled && it.autonomousResearchEnabled
                },
                duplicateExists = existing.any { it.sourceEventId == sourceEventId }
            )
        ) return
        val now = System.currentTimeMillis()
        val task = GlobalResearchTask(
            sourceEventId = sourceEventId,
            causalEventIds = gap.sourceRunIds.mapTo(linkedSetOf()) { "run:$it" },
            sourceConversationId = AgentEvalSideEffectPolicy.SYNTHETIC_CONVERSATION_ID,
            topic = gap.topic,
            question = gap.unknownQuestions.joinToString("\n").take(4_000),
            depth = if (gap.priority >= 0.90) {
                GlobalResearchDepth.DEEP_RESEARCH
            } else GlobalResearchDepth.QUICK_FACT,
            preferredSources = listOf("official", "primary", "repository", "paper"),
            status = GlobalResearchTaskStatus.QUEUED,
            createdAtMillis = now,
            updatedAtMillis = now
        )
        repository.upsertResearchTask(task)
        governance.updateGapStatus(gap.id, AgentKnowledgeGapStatus.RESEARCHING)
        governance.appendDecision(AgentDecisionLogEntry(
            question = "How should SignalASI close the evidence gap for ${gap.topic}?",
            decision = "Queue bounded background research",
            alternatives = listOf("Wait for user evidence", "Leave the result unverified"),
            evidenceRefs = listOf(sourceEventId) + gap.sourceRunIds.map { "run:$it" },
            rationale = "The outcome contract is missing evidence and the gap exceeded the research threshold.",
            relatedGoal = gap.relatedGoal
        ))
        AndroidCognitionScheduler.requestImmediate(appContext)
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
        if (payload.optString("jsonrpc") != "2.0" || payload.optString("method") != "message/send") {
            return null
        }
        val requestId = payload.optString("id").trim()
        if (requestId.isBlank()) return null
        val params = payload.getJSONObject("params")
        val message = params.getJSONObject("message")
        val messageId = message.optString("messageId").trim()
        if (messageId.isBlank()) return null
        val parts = message.getJSONArray("parts")
        val text = (0 until parts.length()).mapNotNull { parts.optJSONObject(it)?.optString("text") }
            .joinToString("\n").trim()
        if (text.isBlank()) return null
        AgentRunRequest(
            conversationId = params.optString("contextId").ifBlank { UUID.randomUUID().toString() },
            messageId = messageId,
            taskId = params.optString("taskId").ifBlank { UUID.randomUUID().toString() },
            runId = requestId,
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
        if (payload.optString("jsonrpc") != "2.0" || payload.optString("method") != "session/prompt") {
            return null
        }
        val requestId = payload.optString("id").trim()
        if (requestId.isBlank()) return null
        val params = payload.getJSONObject("params")
        val sessionId = params.optString("sessionId").trim()
        if (sessionId.isBlank()) return null
        val prompt = params.getJSONArray("prompt")
        val text = (0 until prompt.length()).mapNotNull { prompt.optJSONObject(it)?.optString("text") }
            .joinToString("\n").trim()
        if (text.isBlank()) return null
        AgentRunRequest(
            conversationId = sessionId,
            messageId = requestId,
            taskId = params.optString("taskId").ifBlank { UUID.randomUUID().toString() },
            runId = requestId,
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

data class AgentProtocolEndpointGrant(
    val endpointId: String,
    val protocol: AgentStandardProtocol,
    val displayName: String,
    val identityFingerprint: String,
    val allowedCapabilities: Set<AgentCapability>,
    val enabled: Boolean = false,
    val createdAtMillis: Long = System.currentTimeMillis(),
    val updatedAtMillis: Long = createdAtMillis
)

class AgentProtocolEndpointGrantStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun save(value: AgentProtocolEndpointGrant) {
        val clean = value.copy(
            endpointId = value.endpointId.trim().take(240),
            displayName = value.displayName.trim().take(240),
            identityFingerprint = value.identityFingerprint.trim().take(256),
            updatedAtMillis = System.currentTimeMillis()
        )
        require(clean.endpointId.isNotBlank() && clean.identityFingerprint.isNotBlank()) {
            "Protocol endpoint requires an id and verified identity fingerprint"
        }
        database.writeString(key(clean.protocol, clean.endpointId), JSONObject()
            .put("endpoint_id", clean.endpointId).put("protocol", clean.protocol.wireValue)
            .put("display_name", clean.displayName).put("identity_fingerprint", clean.identityFingerprint)
            .put("allowed_capabilities", JSONArray(clean.allowedCapabilities.map(AgentCapability::name)))
            .put("enabled", clean.enabled).put("created_at_millis", clean.createdAtMillis)
            .put("updated_at_millis", clean.updatedAtMillis).toString())
    }

    @Synchronized
    fun get(protocol: AgentStandardProtocol, endpointId: String): AgentProtocolEndpointGrant? =
        decode(database.readString(key(protocol, endpointId.trim()), ""))

    @Synchronized
    fun list(): List<AgentProtocolEndpointGrant> = database.entries(KEY_PREFIX)
        .mapNotNull { decode(it.second) }
        .sortedBy(AgentProtocolEndpointGrant::displayName)

    private fun decode(raw: String): AgentProtocolEndpointGrant? = runCatching {
        val json = JSONObject(raw)
        AgentProtocolEndpointGrant(
            endpointId = json.getString("endpoint_id"),
            protocol = AgentStandardProtocol.entries.first { it.wireValue == json.getString("protocol") },
            displayName = json.optString("display_name"),
            identityFingerprint = json.getString("identity_fingerprint"),
            allowedCapabilities = json.getJSONArray("allowed_capabilities").strings()
                .mapNotNull { name -> runCatching { AgentCapability.valueOf(name) }.getOrNull() }.toSet(),
            enabled = json.optBoolean("enabled"),
            createdAtMillis = json.optLong("created_at_millis"),
            updatedAtMillis = json.optLong("updated_at_millis")
        )
    }.getOrNull()

    private fun JSONArray.strings(): List<String> = buildList {
        for (index in 0 until length()) optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
    }

    private fun key(protocol: AgentStandardProtocol, endpointId: String) =
        "$KEY_PREFIX${protocol.wireValue}:${AgentLearningAnalyzer.stableKey(endpointId)}"

    private companion object {
        const val DATABASE = "signalasi_protocol_endpoint_grants_v1"
        const val KEY_PREFIX = "grant:"
    }
}

data class AgentProtocolInboundDecision(
    val allowed: Boolean,
    val request: AgentRunRequest? = null,
    val reason: String,
    val endpointId: String,
    val protocol: AgentStandardProtocol
)

internal object AgentProtocolAuthorizationPolicy {
    fun denialReason(
        grant: AgentProtocolEndpointGrant,
        presentedIdentityFingerprint: String,
        request: AgentRunRequest
    ): String? {
        if (!grant.enabled) return "endpoint_disabled"
        if (!secureEquals(grant.identityFingerprint, presentedIdentityFingerprint)) {
            return "endpoint_identity_mismatch"
        }
        if (!grant.allowedCapabilities.containsAll(request.requiredCapabilities)) {
            return "capability_not_granted"
        }
        return null
    }

    private fun secureEquals(expected: String, actual: String): Boolean {
        val left = expected.trim().lowercase(Locale.ROOT).toByteArray(Charsets.UTF_8)
        val right = actual.trim().lowercase(Locale.ROOT).toByteArray(Charsets.UTF_8)
        return left.isNotEmpty() && MessageDigest.isEqual(left, right)
    }
}

class AgentProtocolBoundaryGateway(context: Context) {
    private val appContext = context.applicationContext
    private val grants = AgentProtocolEndpointGrantStore(appContext)

    fun decodeInbound(
        protocol: AgentStandardProtocol,
        endpointId: String,
        identityFingerprint: String,
        payload: JSONObject
    ): AgentProtocolInboundDecision {
        val cleanEndpoint = endpointId.trim()
        val settings = AgentEvalOpsStore(appContext).settings()
        if (!settings.protocolAdaptersEnabled) return denied(protocol, cleanEndpoint, "protocol_adapters_disabled")
        if (protocol !in setOf(AgentStandardProtocol.ACP, AgentStandardProtocol.A2A)) {
            return denied(protocol, cleanEndpoint, "protocol_uses_dedicated_permission_runtime")
        }
        if (payload.toString().toByteArray(Charsets.UTF_8).size > MAX_PAYLOAD_BYTES) {
            return denied(protocol, cleanEndpoint, "payload_too_large")
        }
        val grant = grants.get(protocol, cleanEndpoint)
            ?: return denied(protocol, cleanEndpoint, "endpoint_not_authorized")
        val adapter = when (protocol) {
            AgentStandardProtocol.ACP -> AgentAcpBoundaryAdapter
            AgentStandardProtocol.A2A -> AgentA2aBoundaryAdapter
            else -> return denied(protocol, cleanEndpoint, "unsupported_boundary_adapter")
        }
        val decodedRequest = adapter.decodeRequest(payload)
            ?: return denied(protocol, cleanEndpoint, "malformed_request")
        val request = decodedRequest.copy(
            requiredCapabilities = decodedRequest.requiredCapabilities +
                AgentTaskRequirementAnalyzer.analyze(decodedRequest.goal).capabilities
        )
        AgentProtocolAuthorizationPolicy.denialReason(grant, identityFingerprint, request)?.let { reason ->
            return denied(protocol, cleanEndpoint, reason)
        }
        if (request.goal.isBlank() || request.goal.length > MAX_GOAL_CHARS) {
            return denied(protocol, cleanEndpoint, "invalid_goal")
        }
        return AgentProtocolInboundDecision(
            allowed = true,
            request = request,
            reason = "authorized",
            endpointId = cleanEndpoint,
            protocol = protocol
        )
    }

    private fun denied(
        protocol: AgentStandardProtocol,
        endpointId: String,
        reason: String
    ) = AgentProtocolInboundDecision(false, reason = reason, endpointId = endpointId, protocol = protocol)

    private companion object {
        const val MAX_PAYLOAD_BYTES = 256 * 1_024
        const val MAX_GOAL_CHARS = 8_000
    }
}
