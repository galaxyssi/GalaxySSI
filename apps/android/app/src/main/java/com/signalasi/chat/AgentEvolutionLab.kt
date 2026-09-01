package com.signalasi.chat

import android.content.Context
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

enum class AgentLabCampaignStatus { DRAFT, RUNNING, READY_FOR_REVIEW, COMPLETED, CANCELLED }
enum class AgentLabTrialStatus { PENDING, RUNNING, COMPLETED, FAILED, CANCELLED }

data class AgentLabTrial(
    val id: String = UUID.randomUUID().toString(),
    val agentId: String,
    val blindAlias: String,
    val repetition: Int,
    val runId: String = "",
    val status: AgentLabTrialStatus = AgentLabTrialStatus.PENDING,
    val evalSampleId: String = "",
    val previousRunId: String = "",
    val recoveryCondition: AgentEvalCondition = AgentEvalCondition.NORMAL
)

data class AgentLabCampaign(
    val id: String = UUID.randomUUID().toString(),
    val task: String,
    val outcomeContract: AgentOutcomeContract,
    val trials: List<AgentLabTrial>,
    val blindReview: Boolean = true,
    val status: AgentLabCampaignStatus = AgentLabCampaignStatus.DRAFT,
    val winnerTrialId: String = "",
    val createdAtMillis: Long = System.currentTimeMillis(),
    val updatedAtMillis: Long = createdAtMillis
)

object AgentLabRecoveryPolicy {
    fun resetInterrupted(
        campaign: AgentLabCampaign,
        condition: AgentEvalCondition,
        nowMillis: Long = System.currentTimeMillis()
    ): AgentLabCampaign = campaign.copy(
        trials = campaign.trials.map { trial ->
            if (trial.status == AgentLabTrialStatus.RUNNING) {
                trial.copy(
                    runId = "",
                    status = AgentLabTrialStatus.PENDING,
                    evalSampleId = "",
                    previousRunId = trial.runId,
                    recoveryCondition = condition
                )
            } else trial
        },
        status = AgentLabCampaignStatus.DRAFT,
        updatedAtMillis = nowMillis
    )
}

data class AgentLabBlindResult(
    val trialId: String,
    val label: String,
    val verdict: AgentEvalVerdict,
    val durationMillis: Long,
    val reportedCostMicros: Long,
    val toolEvidenceCount: Int,
    val artifactEvidenceCount: Int,
    val recoverySucceeded: Boolean,
    val failureReasons: List<String>,
    val outputPreview: String = ""
)

data class AgentSpecialtyProfile(
    val resourceId: String,
    val strongestTaskClass: AgentEvalTaskClass,
    val verifiedSamples: Int,
    val passAt1: Double,
    val averageLatencyMillis: Long
)

class AgentLabStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun create(task: String, agentIds: List<String>, repetitions: Int): AgentLabCampaign {
        val cleanTask = task.trim().take(4_000)
        val agents = agentIds.map(String::trim).filter(String::isNotBlank).distinct().take(12)
        require(cleanTask.isNotBlank() && agents.size >= 2) { "Agent Lab requires a task and at least two Agents" }
        val count = repetitions.coerceIn(1, 10)
        val campaignId = UUID.randomUUID().toString()
        val contract = AgentOutcomeContractCompiler.compile("lab:$campaignId", cleanTask)
        val aliases = agents.indices.associateWith { index -> "Agent ${('A'.code + index).toChar()}" }
        val trials = buildList {
            repeat(count) { repetition ->
                agents.forEachIndexed { index, agentId ->
                    add(AgentLabTrial(
                        agentId = agentId,
                        blindAlias = aliases.getValue(index),
                        repetition = repetition + 1
                    ))
                }
            }
        }
        return AgentLabCampaign(
            id = campaignId,
            task = cleanTask,
            outcomeContract = contract,
            trials = trials
        ).also(::save)
    }

    @Synchronized
    fun save(campaign: AgentLabCampaign) {
        database.writeString("$KEY_PREFIX${campaign.id}", encode(campaign).toString())
        prune()
    }

    @Synchronized
    fun get(id: String): AgentLabCampaign? =
        decode(database.readString("$KEY_PREFIX${id.trim()}", ""))

    @Synchronized
    fun list(limit: Int = MAX_CAMPAIGNS): List<AgentLabCampaign> =
        database.entries(KEY_PREFIX).mapNotNull { decode(it.second) }
            .sortedByDescending(AgentLabCampaign::updatedAtMillis)
            .take(limit.coerceIn(1, MAX_CAMPAIGNS))

    @Synchronized
    fun bindRun(campaignId: String, trialId: String, runId: String): AgentLabCampaign? {
        val campaign = get(campaignId) ?: return null
        if (campaign.trials.none { it.id == trialId } || runId.isBlank()) return null
        val updated = campaign.copy(
            trials = campaign.trials.map { trial ->
                if (trial.id == trialId) trial.copy(runId = runId, status = AgentLabTrialStatus.RUNNING) else trial
            },
            status = AgentLabCampaignStatus.RUNNING,
            updatedAtMillis = System.currentTimeMillis()
        )
        save(updated)
        return updated
    }

    @Synchronized
    fun markTrialFailed(campaignId: String, trialId: String): AgentLabCampaign? {
        val campaign = get(campaignId) ?: return null
        if (campaign.trials.none { it.id == trialId }) return null
        val updated = campaign.copy(
            trials = campaign.trials.map { trial ->
                if (trial.id == trialId) trial.copy(status = AgentLabTrialStatus.FAILED) else trial
            },
            status = AgentLabCampaignStatus.RUNNING,
            updatedAtMillis = System.currentTimeMillis()
        ).withTerminalCampaignState()
        save(updated)
        return updated
    }

    @Synchronized
    fun cancel(campaignId: String): AgentLabCampaign? {
        val campaign = get(campaignId) ?: return null
        val updated = campaign.copy(
            trials = campaign.trials.map { trial ->
                if (trial.status in TERMINAL_TRIALS) trial else trial.copy(status = AgentLabTrialStatus.CANCELLED)
            },
            status = AgentLabCampaignStatus.CANCELLED,
            updatedAtMillis = System.currentTimeMillis()
        )
        save(updated)
        return updated
    }

    @Synchronized
    fun resetInterruptedTrials(
        campaignId: String,
        condition: AgentEvalCondition = AgentEvalCondition.PROCESS_DEATH
    ): AgentLabCampaign? {
        val campaign = get(campaignId) ?: return null
        val updated = AgentLabRecoveryPolicy.resetInterrupted(campaign, condition)
        save(updated)
        return updated
    }

    @Synchronized
    fun observe(sample: AgentEvalSample): AgentLabCampaign? {
        val campaign = list().firstOrNull { item -> item.trials.any { it.runId == sample.runId } } ?: return null
        val trials = campaign.trials.map { trial ->
            if (trial.runId != sample.runId) trial else trial.copy(
                status = if (sample.passed) AgentLabTrialStatus.COMPLETED else AgentLabTrialStatus.FAILED,
                evalSampleId = sample.id
            )
        }
        val terminal = trials.all { it.status in TERMINAL_TRIALS }
        val updated = campaign.copy(
            trials = trials,
            status = if (terminal) AgentLabCampaignStatus.READY_FOR_REVIEW else AgentLabCampaignStatus.RUNNING,
            updatedAtMillis = System.currentTimeMillis()
        )
        save(updated)
        return updated
    }

    @Synchronized
    fun selectWinner(campaignId: String, trialId: String): AgentLabCampaign? {
        val campaign = get(campaignId) ?: return null
        val winner = campaign.trials.firstOrNull { it.id == trialId && it.status == AgentLabTrialStatus.COMPLETED }
            ?: return null
        val updated = campaign.copy(
            winnerTrialId = winner.id,
            status = AgentLabCampaignStatus.COMPLETED,
            updatedAtMillis = System.currentTimeMillis()
        )
        save(updated)
        return updated
    }

    fun blindResults(
        campaignId: String,
        evalStore: AgentEvalOpsStore,
        recorder: AgentRunRecorder? = null
    ): List<AgentLabBlindResult> {
        val campaign = get(campaignId) ?: return emptyList()
        return campaign.trials.mapNotNull { trial ->
            val sample = trial.runId.takeIf(String::isNotBlank)?.let(evalStore::sample) ?: return@mapNotNull null
            AgentLabBlindResult(
                trialId = trial.id,
                label = if (campaign.blindReview) "${trial.blindAlias} · ${trial.repetition}" else trial.agentId,
                verdict = sample.verdict,
                durationMillis = sample.durationMillis,
                reportedCostMicros = sample.reportedCostMicros,
                toolEvidenceCount = if (AgentOutcomeEvidenceKind.TOOL_RECEIPT in sample.evidenceKinds) 1 else 0,
                artifactEvidenceCount = if (AgentOutcomeEvidenceKind.ARTIFACT_DIGEST in sample.evidenceKinds) 1 else 0,
                recoverySucceeded = sample.recovered,
                failureReasons = sample.failureReasons,
                outputPreview = trial.runId.takeIf(String::isNotBlank)?.let { runId ->
                    recorder?.run(runId)?.finalOutputJson?.let { raw ->
                        runCatching {
                            JSONObject(raw).let { json ->
                                sequenceOf("text", "message", "content", "result")
                                    .map(json::optString).firstOrNull(String::isNotBlank).orEmpty()
                            }
                        }.getOrDefault("")
                    }
                }.orEmpty().take(2_000)
            )
        }.sortedWith(compareByDescending<AgentLabBlindResult> { it.verdict == AgentEvalVerdict.PASSED }
            .thenBy(AgentLabBlindResult::durationMillis))
    }

    fun winnerRunIds(campaignId: String): List<String> {
        val campaign = get(campaignId) ?: return emptyList()
        val winner = campaign.trials.firstOrNull { it.id == campaign.winnerTrialId } ?: return emptyList()
        return campaign.trials.filter { it.agentId == winner.agentId && it.status == AgentLabTrialStatus.COMPLETED }
            .map(AgentLabTrial::runId).filter(String::isNotBlank)
    }

    private fun AgentLabCampaign.withTerminalCampaignState(): AgentLabCampaign = copy(
        status = if (trials.all { it.status in TERMINAL_TRIALS }) {
            AgentLabCampaignStatus.READY_FOR_REVIEW
        } else AgentLabCampaignStatus.RUNNING
    )

    private fun prune() {
        val retained = list(MAX_CAMPAIGNS).mapTo(hashSetOf()) { "$KEY_PREFIX${it.id}" }
        database.removeAll(database.keys(KEY_PREFIX).filterNot(retained::contains))
    }

    private fun encode(value: AgentLabCampaign) = JSONObject()
        .put("id", value.id).put("task", value.task)
        .put("outcome_contract", encodeContract(value.outcomeContract))
        .put("trials", JSONArray().apply { value.trials.forEach { put(encodeTrial(it)) } })
        .put("blind_review", value.blindReview).put("status", value.status.name)
        .put("winner_trial_id", value.winnerTrialId)
        .put("created_at_millis", value.createdAtMillis).put("updated_at_millis", value.updatedAtMillis)

    private fun encodeContract(value: AgentOutcomeContract) = JSONObject()
        .put("id", value.id).put("run_id", value.runId).put("goal", value.goal)
        .put("task_class", value.taskClass.wireValue)
        .put("success_criteria", JSONArray(value.successCriteria))
        .put("allowed_resources", JSONArray(value.allowedResources.toList()))
        .put("forbidden_resources", JSONArray(value.forbiddenResources.toList()))
        .put("required_evidence", JSONArray(value.requiredEvidence.map(AgentOutcomeEvidenceKind::wireValue)))
        .put("max_duration_millis", value.maxDurationMillis)
        .put("max_reported_cost_micros", value.maxReportedCostMicros)
        .put("memory_horizon_days", value.memoryHorizonDays).put("condition", value.condition.wireValue)
        .put("created_at_millis", value.createdAtMillis)

    private fun encodeTrial(value: AgentLabTrial) = JSONObject()
        .put("id", value.id).put("agent_id", value.agentId).put("blind_alias", value.blindAlias)
        .put("repetition", value.repetition).put("run_id", value.runId)
        .put("status", value.status.name).put("eval_sample_id", value.evalSampleId)
        .put("previous_run_id", value.previousRunId)
        .put("recovery_condition", value.recoveryCondition.wireValue)

    private fun decode(raw: String): AgentLabCampaign? = runCatching {
        val json = JSONObject(raw)
        val contractJson = json.getJSONObject("outcome_contract")
        AgentLabCampaign(
            id = json.getString("id"), task = json.getString("task"),
            outcomeContract = AgentOutcomeContract(
                id = contractJson.getString("id"), runId = contractJson.getString("run_id"),
                goal = contractJson.getString("goal"),
                taskClass = AgentEvalTaskClass.entries.firstOrNull {
                    it.wireValue == contractJson.optString("task_class")
                } ?: AgentEvalTaskClass.GENERAL,
                successCriteria = contractJson.getJSONArray("success_criteria").strings(),
                allowedResources = contractJson.getJSONArray("allowed_resources").strings().toSet(),
                forbiddenResources = contractJson.getJSONArray("forbidden_resources").strings().toSet(),
                requiredEvidence = contractJson.getJSONArray("required_evidence").strings().mapNotNull { wire ->
                    AgentOutcomeEvidenceKind.entries.firstOrNull { it.wireValue == wire }
                }.toSet(),
                maxDurationMillis = contractJson.optLong("max_duration_millis"),
                maxReportedCostMicros = contractJson.optLong("max_reported_cost_micros"),
                memoryHorizonDays = contractJson.optInt("memory_horizon_days"),
                condition = AgentEvalCondition.entries.firstOrNull {
                    it.wireValue == contractJson.optString("condition")
                } ?: AgentEvalCondition.NORMAL,
                createdAtMillis = contractJson.optLong("created_at_millis")
            ),
            trials = json.getJSONArray("trials").objects().mapNotNull(::decodeTrial),
            blindReview = json.optBoolean("blind_review", true),
            status = runCatching { AgentLabCampaignStatus.valueOf(json.optString("status")) }
                .getOrDefault(AgentLabCampaignStatus.DRAFT),
            winnerTrialId = json.optString("winner_trial_id"),
            createdAtMillis = json.optLong("created_at_millis"),
            updatedAtMillis = json.optLong("updated_at_millis")
        )
    }.getOrNull()

    private fun decodeTrial(json: JSONObject): AgentLabTrial? = runCatching {
        AgentLabTrial(
            id = json.getString("id"), agentId = json.getString("agent_id"),
            blindAlias = json.getString("blind_alias"), repetition = json.optInt("repetition").coerceAtLeast(1),
            runId = json.optString("run_id"),
            status = runCatching { AgentLabTrialStatus.valueOf(json.optString("status")) }
                .getOrDefault(AgentLabTrialStatus.PENDING),
            evalSampleId = json.optString("eval_sample_id"),
            previousRunId = json.optString("previous_run_id"),
            recoveryCondition = AgentEvalCondition.entries.firstOrNull {
                it.wireValue == json.optString("recovery_condition")
            } ?: AgentEvalCondition.NORMAL
        )
    }.getOrNull()

    private fun JSONArray.objects(): List<JSONObject> = buildList {
        for (index in 0 until length()) optJSONObject(index)?.let(::add)
    }

    private fun JSONArray.strings(): List<String> = buildList {
        for (index in 0 until length()) optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
    }

    private companion object {
        const val DATABASE = "signalasi_agent_lab_v1"
        const val KEY_PREFIX = "campaign:"
        const val MAX_CAMPAIGNS = 200
        val TERMINAL_TRIALS = setOf(
            AgentLabTrialStatus.COMPLETED,
            AgentLabTrialStatus.FAILED,
            AgentLabTrialStatus.CANCELLED
        )
    }
}

object AgentSpecialtyAnalyzer {
    fun profiles(samples: List<AgentEvalSample>): List<AgentSpecialtyProfile> = samples.filter(AgentEvalSample::verified)
        .groupBy(AgentEvalSample::resourceId)
        .mapNotNull { (resourceId, values) ->
            val strongest = values.groupBy(AgentEvalSample::taskClass).maxByOrNull { (_, classSamples) ->
                classSamples.count(AgentEvalSample::passed).toDouble() / classSamples.size
            } ?: return@mapNotNull null
            val classSamples = strongest.value
            AgentSpecialtyProfile(
                resourceId = resourceId,
                strongestTaskClass = strongest.key,
                verifiedSamples = classSamples.size,
                passAt1 = classSamples.count(AgentEvalSample::passed).toDouble() / classSamples.size,
                averageLatencyMillis = classSamples.map(AgentEvalSample::durationMillis)
                    .filter { it > 0L }.let { if (it.isEmpty()) 0L else it.sum() / it.size }
            )
        }.sortedByDescending(AgentSpecialtyProfile::passAt1)
}

enum class AgentShadowReleaseStage {
    PROPOSED,
    BUILT,
    DEVICE_SHADOW,
    COMPARING,
    CANARY,
    WAITING_APPROVAL,
    RELEASED,
    ROLLED_BACK,
    FAILED
}

data class AgentShadowReleaseMetrics(
    val passAt1: Double,
    val passPowerK: Double,
    val averageLatencyMillis: Long,
    val averageBatteryDeltaPercent: Double,
    val peakThermalStatus: Int,
    val crashCount: Int,
    val verifiedRuns: Int
)

data class AgentShadowRelease(
    val id: String = UUID.randomUUID().toString(),
    val evolutionTaskId: String,
    val candidateCommit: String,
    val candidateBranch: String,
    val deviceModel: String,
    val stage: AgentShadowReleaseStage = AgentShadowReleaseStage.PROPOSED,
    val baseline: AgentShadowReleaseMetrics? = null,
    val candidate: AgentShadowReleaseMetrics? = null,
    val rollbackReason: String = "",
    val createdAtMillis: Long = System.currentTimeMillis(),
    val updatedAtMillis: Long = createdAtMillis
)

data class AgentShadowReleaseDecision(
    val promote: Boolean,
    val rollback: Boolean,
    val reasons: List<String>
)

object AgentShadowReleasePolicy {
    fun compare(
        baseline: AgentShadowReleaseMetrics,
        candidate: AgentShadowReleaseMetrics
    ): AgentShadowReleaseDecision {
        val reasons = buildList {
            if (candidate.crashCount > baseline.crashCount) add("crash_regression")
            if (candidate.passAt1 + 0.02 < baseline.passAt1) add("pass_at_1_regression")
            if (candidate.passPowerK + 0.02 < baseline.passPowerK) add("pass_power_k_regression")
            if (baseline.averageLatencyMillis > 0L &&
                candidate.averageLatencyMillis > baseline.averageLatencyMillis * 1.15
            ) add("latency_regression")
            if (candidate.averageBatteryDeltaPercent > baseline.averageBatteryDeltaPercent + 1.0) {
                add("battery_regression")
            }
            if (candidate.peakThermalStatus > baseline.peakThermalStatus + 1) add("thermal_regression")
            if (candidate.verifiedRuns < MIN_VERIFIED_RUNS) add("insufficient_shadow_evidence")
        }
        val hardFailure = reasons.any { it in HARD_FAILURES }
        return AgentShadowReleaseDecision(
            promote = reasons.isEmpty(),
            rollback = hardFailure,
            reasons = reasons
        )
    }

    private const val MIN_VERIFIED_RUNS = 10
    private val HARD_FAILURES = setOf("crash_regression", "pass_at_1_regression", "pass_power_k_regression")
}

class AgentShadowReleaseStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun create(task: AgentSelfEvolutionTask): AgentShadowRelease {
        require(task.candidateCommit.isNotBlank() && task.candidateBranch.isNotBlank()) {
            "Self-evolution candidate is not ready for shadow release"
        }
        val release = AgentShadowRelease(
            evolutionTaskId = task.taskId,
            candidateCommit = task.candidateCommit,
            candidateBranch = task.candidateBranch,
            deviceModel = Build.MODEL.orEmpty().ifBlank { "Android" }
        )
        save(release)
        return release
    }

    @Synchronized
    fun save(release: AgentShadowRelease) {
        database.writeString("$KEY_PREFIX${release.id}", encode(release.copy(
            updatedAtMillis = System.currentTimeMillis()
        )).toString())
    }

    @Synchronized
    fun get(id: String): AgentShadowRelease? = decode(
        database.readString("$KEY_PREFIX${id.trim()}", "")
    )

    @Synchronized
    fun update(id: String, transform: (AgentShadowRelease) -> AgentShadowRelease): AgentShadowRelease? {
        val current = get(id) ?: return null
        return transform(current).copy(updatedAtMillis = System.currentTimeMillis()).also(::save)
    }

    @Synchronized
    fun list(limit: Int = 100): List<AgentShadowRelease> =
        database.entries(KEY_PREFIX).mapNotNull { decode(it.second) }
            .sortedByDescending(AgentShadowRelease::updatedAtMillis).take(limit.coerceIn(1, 100))

    private fun encode(value: AgentShadowRelease) = JSONObject()
        .put("id", value.id).put("evolution_task_id", value.evolutionTaskId)
        .put("candidate_commit", value.candidateCommit).put("candidate_branch", value.candidateBranch)
        .put("device_model", value.deviceModel).put("stage", value.stage.name)
        .put("baseline", value.baseline?.let(::encodeMetrics)).put("candidate", value.candidate?.let(::encodeMetrics))
        .put("rollback_reason", value.rollbackReason)
        .put("created_at_millis", value.createdAtMillis).put("updated_at_millis", value.updatedAtMillis)

    private fun encodeMetrics(value: AgentShadowReleaseMetrics) = JSONObject()
        .put("pass_at_1", value.passAt1).put("pass_power_k", value.passPowerK)
        .put("average_latency_millis", value.averageLatencyMillis)
        .put("average_battery_delta_percent", value.averageBatteryDeltaPercent)
        .put("peak_thermal_status", value.peakThermalStatus).put("crash_count", value.crashCount)
        .put("verified_runs", value.verifiedRuns)

    private fun decode(raw: String): AgentShadowRelease? = runCatching {
        val json = JSONObject(raw)
        AgentShadowRelease(
            id = json.getString("id"), evolutionTaskId = json.getString("evolution_task_id"),
            candidateCommit = json.getString("candidate_commit"), candidateBranch = json.getString("candidate_branch"),
            deviceModel = json.optString("device_model"),
            stage = runCatching { AgentShadowReleaseStage.valueOf(json.optString("stage")) }
                .getOrDefault(AgentShadowReleaseStage.PROPOSED),
            baseline = json.optJSONObject("baseline")?.let(::decodeMetrics),
            candidate = json.optJSONObject("candidate")?.let(::decodeMetrics),
            rollbackReason = json.optString("rollback_reason"),
            createdAtMillis = json.optLong("created_at_millis"), updatedAtMillis = json.optLong("updated_at_millis")
        )
    }.getOrNull()

    private fun decodeMetrics(json: JSONObject) = AgentShadowReleaseMetrics(
        passAt1 = json.optDouble("pass_at_1"), passPowerK = json.optDouble("pass_power_k"),
        averageLatencyMillis = json.optLong("average_latency_millis"),
        averageBatteryDeltaPercent = json.optDouble("average_battery_delta_percent"),
        peakThermalStatus = json.optInt("peak_thermal_status", -1), crashCount = json.optInt("crash_count"),
        verifiedRuns = json.optInt("verified_runs")
    )

    private companion object {
        const val DATABASE = "signalasi_shadow_release_v1"
        const val KEY_PREFIX = "release:"
    }
}

class AgentShadowReleaseCoordinator(context: Context) {
    private val store = AgentShadowReleaseStore(context.applicationContext)

    fun attachBaseline(releaseId: String, metrics: AgentShadowReleaseMetrics): AgentShadowRelease? =
        store.update(releaseId) { current ->
            current.copy(baseline = metrics, stage = AgentShadowReleaseStage.DEVICE_SHADOW)
        }

    fun compareCandidate(
        releaseId: String,
        metrics: AgentShadowReleaseMetrics
    ): Pair<AgentShadowRelease, AgentShadowReleaseDecision>? {
        val current = store.get(releaseId) ?: return null
        val baseline = current.baseline ?: return null
        val decision = AgentShadowReleasePolicy.compare(baseline, metrics)
        val stage = when {
            decision.rollback -> AgentShadowReleaseStage.ROLLED_BACK
            decision.promote -> AgentShadowReleaseStage.WAITING_APPROVAL
            else -> AgentShadowReleaseStage.COMPARING
        }
        val updated = store.update(releaseId) { release ->
            release.copy(
                candidate = metrics,
                stage = stage,
                rollbackReason = if (decision.rollback) decision.reasons.joinToString(",") else ""
            )
        } ?: return null
        return updated to decision
    }

    fun approve(releaseId: String): AgentShadowRelease? {
        val current = store.get(releaseId) ?: return null
        val baseline = current.baseline ?: return null
        val candidate = current.candidate ?: return null
        if (current.stage != AgentShadowReleaseStage.WAITING_APPROVAL ||
            !AgentShadowReleasePolicy.compare(baseline, candidate).promote
        ) return null
        return store.update(releaseId) { it.copy(stage = AgentShadowReleaseStage.RELEASED) }
    }

    fun rollback(releaseId: String, reason: String): AgentShadowRelease? = store.update(releaseId) {
        it.copy(
            stage = AgentShadowReleaseStage.ROLLED_BACK,
            rollbackReason = reason.trim().take(2_000).ifBlank { "Manual rollback" }
        )
    }

    fun metrics(samples: List<AgentEvalSample>, crashCount: Int = 0, k: Int = 3): AgentShadowReleaseMetrics {
        val verified = samples.filter(AgentEvalSample::verified)
        val dashboard = AgentEvalStatistics.dashboard(verified, k)
        return AgentShadowReleaseMetrics(
            passAt1 = dashboard.passAt1,
            passPowerK = dashboard.passPowerK,
            averageLatencyMillis = dashboard.averageLatencyMillis,
            averageBatteryDeltaPercent = verified.map(AgentEvalSample::batteryDeltaPercent)
                .takeIf(List<*>::isNotEmpty)?.average() ?: 0.0,
            peakThermalStatus = verified.maxOfOrNull(AgentEvalSample::peakThermalStatus) ?: -1,
            crashCount = crashCount.coerceAtLeast(0),
            verifiedRuns = verified.size
        )
    }
}

object AgentEvolutionLabService {
    fun observe(context: Context, sample: AgentEvalSample) {
        AgentLabStore(context).observe(sample)
    }
}
