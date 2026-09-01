package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.UUID

data class AgentShadowRoutingScore(
    val resourceId: String,
    val score: Double,
    val verifiedSamples: Int,
    val passAt1: Double,
    val averageLatencyMillis: Long,
    val averageCostMicros: Long,
    val recoveryRate: Double,
    val reasons: List<String>
)

data class AgentShadowRoutingRecommendation(
    val id: String = UUID.randomUUID().toString(),
    val scenarioId: String,
    val taskClass: AgentEvalTaskClass,
    val actualResourceId: String,
    val recommendedResourceId: String,
    val scores: List<AgentShadowRoutingScore>,
    val shouldAutoSwitch: Boolean,
    val confidence: Double,
    val createdAtMillis: Long = System.currentTimeMillis()
)

object AgentQualityAwareRoutingPolicy {
    fun recommend(
        goal: String,
        requirements: AgentTaskRequirements,
        candidates: List<AgentResourceCandidate>,
        samples: List<AgentEvalSample>,
        actualResourceId: String,
        settings: AgentEvalOpsSettings
    ): AgentShadowRoutingRecommendation? {
        if (!settings.shadowRoutingEnabled || candidates.isEmpty()) return null
        val taskClass = AgentOutcomeContractCompiler.classify(goal, requirements)
        val taskSamples = samples.filter { it.taskClass == taskClass && it.verified }
        val scores = candidates.map { candidate ->
            score(candidate, taskSamples)
        }.sortedByDescending(AgentShadowRoutingScore::score)
        val recommended = scores.firstOrNull() ?: return null
        val actual = scores.firstOrNull { sameResource(it.resourceId, actualResourceId) }
        val margin = recommended.score - (actual?.score ?: 0.0)
        val enoughEvidence = recommended.verifiedSamples >= settings.minimumAutomaticRoutingSamples
        return AgentShadowRoutingRecommendation(
            scenarioId = AgentLearningAnalyzer.stableKey(goal),
            taskClass = taskClass,
            actualResourceId = actualResourceId,
            recommendedResourceId = recommended.resourceId,
            scores = scores,
            shouldAutoSwitch = settings.automaticQualityRoutingEnabled && enoughEvidence &&
                !sameResource(recommended.resourceId, actualResourceId) && margin >= AUTO_SWITCH_MARGIN,
            confidence = (recommended.verifiedSamples.toDouble() /
                settings.minimumAutomaticRoutingSamples.coerceAtLeast(1)).coerceIn(0.0, 1.0)
        )
    }

    private fun score(
        candidate: AgentResourceCandidate,
        samples: List<AgentEvalSample>
    ): AgentShadowRoutingScore {
        val resourceId = candidate.resource.targetId.ifBlank { candidate.resource.id }
        val relevant = samples.filter { sameResource(it.resourceId, resourceId) }
        val passAt1 = if (relevant.isEmpty()) 0.5 else relevant.count(AgentEvalSample::passed).toDouble() / relevant.size
        val latency = relevant.map(AgentEvalSample::durationMillis).positiveAverage()
        val cost = relevant.map(AgentEvalSample::reportedCostMicros).positiveAverage()
        val recoveries = relevant.filter(AgentEvalSample::recoveryAttempted)
        val recoveryRate = if (recoveries.isEmpty()) 0.5 else
            recoveries.count(AgentEvalSample::recovered).toDouble() / recoveries.size
        val capacity = 1.0 - candidate.resource.activeTasks.toDouble() /
            candidate.resource.maxParallelTasks.coerceAtLeast(1)
        val privacy = when (candidate.resource.trust) {
            AgentResourceTrust.PHONE_SYSTEM -> 1.0
            AgentResourceTrust.VERIFIED_PAIRED -> 0.90
            AgentResourceTrust.PRIVATE_CONFIGURED -> 0.75
            AgentResourceTrust.CLOUD_CONFIGURED -> 0.45
            AgentResourceTrust.UNKNOWN -> 0.20
        }
        val latencyScore = when {
            latency <= 0L -> 0.5
            latency <= 2_000L -> 1.0
            latency >= 120_000L -> 0.0
            else -> 1.0 - (latency - 2_000L).toDouble() / 118_000.0
        }
        val costScore = when {
            cost <= 0L -> 1.0
            cost >= 2_000_000L -> 0.0
            else -> 1.0 - cost / 2_000_000.0
        }
        val historicalConfidence = (relevant.size / 12.0).coerceIn(0.0, 1.0)
        val observedQuality = passAt1 * 0.45 + latencyScore * 0.15 + costScore * 0.10 +
            privacy * 0.12 + capacity.coerceIn(0.0, 1.0) * 0.08 + recoveryRate * 0.10
        val baseline = ((candidate.score + 1_000).toDouble() / 2_000.0).coerceIn(0.0, 1.0)
        val score = observedQuality * historicalConfidence + baseline * (1.0 - historicalConfidence)
        return AgentShadowRoutingScore(
            resourceId = resourceId,
            score = score,
            verifiedSamples = relevant.size,
            passAt1 = passAt1,
            averageLatencyMillis = latency,
            averageCostMicros = cost,
            recoveryRate = recoveryRate,
            reasons = listOf(
                "verified_samples:${relevant.size}",
                "pass_at_1:${format(passAt1)}",
                "latency_ms:$latency",
                "reported_cost_micros:$cost",
                "privacy:${format(privacy)}",
                "capacity:${format(capacity)}",
                "recovery:${format(recoveryRate)}"
            )
        )
    }

    fun sameResource(left: String, right: String): Boolean =
        canonical(left) == canonical(right)

    private fun canonical(value: String): String {
        val id = value.trim().lowercase(Locale.ROOT)
        return when {
            id.contains(":codex") || id == "codex" -> "codex"
            id.contains(":claude") || id in setOf("claude", "claude-code") -> "claude-code"
            id.contains(":hermes") || id == "hermes" -> "hermes"
            id.startsWith("cloud-model:") -> id.substringAfter("cloud-model:")
            id.startsWith("skill:") -> id.substringAfter("skill:")
            else -> id
        }
    }

    private fun List<Long>.positiveAverage(): Long {
        val valid = filter { it > 0L }
        return if (valid.isEmpty()) 0L else valid.sum() / valid.size
    }

    private fun format(value: Double): String = String.format(Locale.US, "%.4f", value)

    private const val AUTO_SWITCH_MARGIN = 0.08
}

class AgentShadowRoutingStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun save(recommendation: AgentShadowRoutingRecommendation) {
        database.writeString("$KEY_PREFIX${recommendation.id}", encode(recommendation).toString())
        prune()
    }

    @Synchronized
    fun recent(limit: Int = MAX_ITEMS): List<AgentShadowRoutingRecommendation> =
        database.entries(KEY_PREFIX).mapNotNull { decode(it.second) }
            .sortedByDescending(AgentShadowRoutingRecommendation::createdAtMillis)
            .take(limit.coerceIn(1, MAX_ITEMS))

    private fun prune() {
        val retained = recent(MAX_ITEMS).mapTo(hashSetOf()) { "$KEY_PREFIX${it.id}" }
        database.removeAll(database.keys(KEY_PREFIX).filterNot(retained::contains))
    }

    private fun encode(value: AgentShadowRoutingRecommendation) = JSONObject()
        .put("id", value.id)
        .put("scenario_id", value.scenarioId)
        .put("task_class", value.taskClass.wireValue)
        .put("actual_resource_id", value.actualResourceId)
        .put("recommended_resource_id", value.recommendedResourceId)
        .put("should_auto_switch", value.shouldAutoSwitch)
        .put("confidence", value.confidence)
        .put("created_at_millis", value.createdAtMillis)
        .put("scores", JSONArray().apply { value.scores.forEach { put(encodeScore(it)) } })

    private fun encodeScore(value: AgentShadowRoutingScore) = JSONObject()
        .put("resource_id", value.resourceId)
        .put("score", value.score)
        .put("verified_samples", value.verifiedSamples)
        .put("pass_at_1", value.passAt1)
        .put("average_latency_millis", value.averageLatencyMillis)
        .put("average_cost_micros", value.averageCostMicros)
        .put("recovery_rate", value.recoveryRate)
        .put("reasons", JSONArray(value.reasons))

    private fun decode(raw: String): AgentShadowRoutingRecommendation? = runCatching {
        val json = JSONObject(raw)
        AgentShadowRoutingRecommendation(
            id = json.getString("id"),
            scenarioId = json.getString("scenario_id"),
            taskClass = AgentEvalTaskClass.entries.firstOrNull {
                it.wireValue == json.optString("task_class")
            } ?: AgentEvalTaskClass.GENERAL,
            actualResourceId = json.optString("actual_resource_id"),
            recommendedResourceId = json.optString("recommended_resource_id"),
            scores = json.getJSONArray("scores").objects().mapNotNull(::decodeScore),
            shouldAutoSwitch = json.optBoolean("should_auto_switch"),
            confidence = json.optDouble("confidence").coerceIn(0.0, 1.0),
            createdAtMillis = json.optLong("created_at_millis")
        )
    }.getOrNull()

    private fun decodeScore(json: JSONObject): AgentShadowRoutingScore? = runCatching {
        AgentShadowRoutingScore(
            resourceId = json.getString("resource_id"),
            score = json.optDouble("score").coerceIn(0.0, 1.0),
            verifiedSamples = json.optInt("verified_samples").coerceAtLeast(0),
            passAt1 = json.optDouble("pass_at_1").coerceIn(0.0, 1.0),
            averageLatencyMillis = json.optLong("average_latency_millis").coerceAtLeast(0L),
            averageCostMicros = json.optLong("average_cost_micros").coerceAtLeast(0L),
            recoveryRate = json.optDouble("recovery_rate").coerceIn(0.0, 1.0),
            reasons = json.getJSONArray("reasons").strings()
        )
    }.getOrNull()

    private fun JSONArray.objects(): List<JSONObject> = buildList {
        for (index in 0 until length()) optJSONObject(index)?.let(::add)
    }

    private fun JSONArray.strings(): List<String> = buildList {
        for (index in 0 until length()) optString(index).takeIf(String::isNotBlank)?.let(::add)
    }

    private companion object {
        const val DATABASE = "signalasi_agent_shadow_routing_v1"
        const val KEY_PREFIX = "recommendation:"
        const val MAX_ITEMS = 500
    }
}

object AgentQualityRoutingService {
    fun observe(
        context: Context,
        goal: String,
        decision: AgentRoutingDecision
    ): AgentShadowRoutingRecommendation? {
        val store = AgentEvalOpsStore(context)
        val allCandidates = listOfNotNull(decision.primary) + decision.fallbacks
        val recommendation = AgentQualityAwareRoutingPolicy.recommend(
            goal = goal,
            requirements = decision.requirements,
            candidates = allCandidates,
            samples = store.samples(),
            actualResourceId = decision.primary?.resource?.targetId.orEmpty(),
            settings = store.settings()
        ) ?: return null
        AgentShadowRoutingStore(context).save(recommendation)
        return recommendation
    }
}
