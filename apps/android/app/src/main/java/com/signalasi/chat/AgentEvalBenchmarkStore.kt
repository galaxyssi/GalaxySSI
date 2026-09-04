package com.signalasi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

internal object AgentBenchmarkProgressCounter {
    fun next(current: Int, isNewResult: Boolean, completedTrialsFloor: Int): Int = maxOf(
        current.coerceAtLeast(0) + if (isNewResult) 1 else 0,
        completedTrialsFloor.coerceAtLeast(0)
    )
}

class AgentBenchmarkStore internal constructor(private val database: AgentEncryptedDatabase) {
    constructor(context: Context) : this(AgentEncryptedDatabase(context.applicationContext, DATABASE))

    fun saveSession(session: AgentBenchmarkSession) = synchronized(LOCK) {
        val countKey = resultCountKey(session.id)
        val upserts = linkedMapOf(
            "$SESSION_PREFIX${session.id}" to encodeSession(session).toString(),
            latestSessionKey(session.suiteId, session.suiteVersion) to session.id
        )
        if (!database.contains(countKey)) upserts[countKey] = "0"
        database.mutateStrings(upserts)
        pruneSessions()
    }

    fun session(id: String): AgentBenchmarkSession? = synchronized(LOCK) {
        decodeSession(database.readString("$SESSION_PREFIX${id.trim()}", ""))
    }

    fun sessions(limit: Int = MAX_SESSIONS): List<AgentBenchmarkSession> = synchronized(LOCK) {
        database.entries(SESSION_PREFIX)
            .mapNotNull { decodeSession(it.second) }
            .sortedByDescending(AgentBenchmarkSession::updatedAtMillis)
            .take(limit.coerceIn(1, MAX_SESSIONS))
    }

    fun latestSession(suiteId: String, suiteVersion: String): AgentBenchmarkSession? = synchronized(LOCK) {
        val cleanSuiteId = suiteId.trim()
        val cleanVersion = suiteVersion.trim()
        val indexKey = latestSessionKey(cleanSuiteId, cleanVersion)
        val indexedValue = database.readString(indexKey, "")
        if (indexedValue == NO_SESSION_INDEX) return@synchronized null
        val indexed = indexedValue.takeIf(String::isNotBlank)
            ?.let(::session)
            ?.takeIf { it.suiteId == cleanSuiteId && it.suiteVersion == cleanVersion }
        if (indexed != null) return@synchronized indexed
        sessions().firstOrNull { it.suiteId == cleanSuiteId && it.suiteVersion == cleanVersion }
            .also { database.writeString(indexKey, it?.id ?: NO_SESSION_INDEX) }
    }

    fun saveResult(result: AgentBenchmarkTrialResult, completedTrialsFloor: Int = 0): Int = synchronized(LOCK) {
        val resultKey = resultKey(result.sessionId, result.trialId)
        val isNew = !database.contains(resultKey)
        database.writeString(resultKey, encodeResult(result).toString())
        val countKey = resultCountKey(result.sessionId)
        val current = database.readString(countKey, "0").toIntOrNull()?.coerceAtLeast(0) ?: 0
        val updated = AgentBenchmarkProgressCounter.next(current, isNew, completedTrialsFloor)
        database.writeString(countKey, updated.toString())
        updated
    }

    fun resultCount(sessionId: String): Int? = synchronized(LOCK) {
        val key = resultCountKey(sessionId)
        if (!database.contains(key)) null else database.readString(key, "").toIntOrNull()
    }

    fun results(sessionId: String, limit: Int = MAX_RESULTS): List<AgentBenchmarkTrialResult> =
        synchronized(LOCK) {
            val scopedPrefix = resultSessionPrefix(sessionId)
            val scoped = database.entries(scopedPrefix)
                .mapNotNull { decodeResult(it.second) }
                .filter { it.sessionId == sessionId }
                .sortedBy(AgentBenchmarkTrialResult::completedAtMillis)
                .takeLast(limit.coerceIn(1, MAX_RESULTS))
            if (scoped.isNotEmpty()) return@synchronized scoped
            database.entries(RESULT_PREFIX)
                .filterNot { it.first.startsWith(scopedPrefix) }
                .mapNotNull { decodeResult(it.second) }
                .filter { it.sessionId == sessionId }
                .sortedBy(AgentBenchmarkTrialResult::completedAtMillis)
                .takeLast(limit.coerceIn(1, MAX_RESULTS))
        }

    fun markStatus(id: String, status: AgentBenchmarkSessionStatus): AgentBenchmarkSession? = synchronized(LOCK) {
        val current = session(id) ?: return null
        val updated = current.copy(status = status, updatedAtMillis = System.currentTimeMillis())
        saveSession(updated)
        updated
    }

    private fun pruneSessions() {
        val retained = database.recentKeys(SESSION_PREFIX, MAX_SESSIONS).toHashSet()
        val staleSessionKeys = database.keys(SESSION_PREFIX).filterNot(retained::contains)
        val staleCountKeys = staleSessionKeys.map { key -> resultCountKey(key.removePrefix(SESSION_PREFIX)) }
        database.removeAll(staleSessionKeys + staleCountKeys)
    }

    private fun resultCountKey(sessionId: String) = "$RESULT_COUNT_PREFIX${sessionId.trim()}"

    private fun resultSessionPrefix(sessionId: String) = "$RESULT_PREFIX${sessionId.trim()}:"

    private fun resultKey(sessionId: String, trialId: String) =
        "${resultSessionPrefix(sessionId)}${trialId.trim()}"

    private fun latestSessionKey(suiteId: String, suiteVersion: String) =
        "$LATEST_SESSION_PREFIX$suiteId:$suiteVersion"

    private fun encodeSession(value: AgentBenchmarkSession) = JSONObject()
        .put("id", value.id)
        .put("suite_id", value.suiteId)
        .put("suite_version", value.suiteVersion)
        .put("app_version_name", value.appVersionName)
        .put("app_version_code", value.appVersionCode)
        .put("device_model", value.deviceModel)
        .put("repetitions", value.repetitions)
        .put("target_pass_rate", value.targetPassRate)
        .put("case_ids", JSONArray(value.caseIds))
        .put("resources", JSONArray().apply { value.resources.forEach { put(encodeResource(it)) } })
        .put("resource_ids_by_case", JSONObject().apply {
            value.resourceIdsByCase.forEach { (caseId, resourceIds) -> put(caseId, JSONArray(resourceIds)) }
        })
        .put("campaign_ids_by_case", JSONObject(value.campaignIdsByCase))
        .put("team_resource_ids_by_case", JSONObject().apply {
            value.teamResourceIdsByCase.forEach { (caseId, resourceIds) -> put(caseId, JSONArray(resourceIds)) }
        })
        .put("readiness_by_case", JSONObject().apply {
            value.readinessByCase.forEach { (caseId, readiness) ->
                put(caseId, encodeReadiness(readiness))
            }
        })
        .put("allocation_profile", value.allocationProfile)
        .put("status", value.status.name)
        .put("created_at_millis", value.createdAtMillis)
        .put("updated_at_millis", value.updatedAtMillis)

    private fun decodeSession(raw: String): AgentBenchmarkSession? = runCatching {
        val json = JSONObject(raw)
        val resourceIdsByCase = json.optJSONObject("resource_ids_by_case").stringListMap()
        AgentBenchmarkSession(
            id = json.getString("id"),
            suiteId = json.getString("suite_id"),
            suiteVersion = json.getString("suite_version"),
            appVersionName = json.optString("app_version_name"),
            appVersionCode = json.optLong("app_version_code"),
            deviceModel = json.optString("device_model"),
            repetitions = json.optInt("repetitions", 3).coerceIn(3, 10),
            targetPassRate = json.optDouble("target_pass_rate", 0.90).coerceIn(0.0, 1.0),
            caseIds = json.optJSONArray("case_ids").strings(),
            resources = json.optJSONArray("resources").objects().mapNotNull(::decodeResource),
            resourceIdsByCase = resourceIdsByCase,
            campaignIdsByCase = json.optJSONObject("campaign_ids_by_case").stringMap(),
            teamResourceIdsByCase = json.optJSONObject("team_resource_ids_by_case").stringListMap(),
            readinessByCase = json.optJSONObject("readiness_by_case").readinessMap(),
            allocationProfile = json.optString("allocation_profile", "codex_90_deepseek_10"),
            status = runCatching { AgentBenchmarkSessionStatus.valueOf(json.optString("status")) }
                .getOrDefault(AgentBenchmarkSessionStatus.RUNNING),
            createdAtMillis = json.optLong("created_at_millis"),
            updatedAtMillis = json.optLong("updated_at_millis")
        )
    }.getOrNull()

    private fun encodeResource(value: AgentBenchmarkResourceSnapshot) = JSONObject()
        .put("resource_id", value.resourceId)
        .put("display_name", value.displayName)
        .put("provider_id", value.providerId)
        .put("model_id", value.modelId)
        .put("adapter_type", value.adapterType)
        .put("capabilities_hash", value.capabilitiesHash)

    private fun decodeResource(json: JSONObject): AgentBenchmarkResourceSnapshot? = runCatching {
        AgentBenchmarkResourceSnapshot(
            resourceId = json.getString("resource_id"),
            displayName = json.optString("display_name"),
            providerId = json.optString("provider_id"),
            modelId = json.optString("model_id"),
            adapterType = json.optString("adapter_type"),
            capabilitiesHash = json.optString("capabilities_hash")
        )
    }.getOrNull()

    private fun encodeReadiness(value: AgentBenchmarkCaseReadiness) = JSONObject()
        .put("case_id", value.caseId)
        .put("status", value.status.name)
        .put("reason_code", value.reasonCode)
        .put("eligible_at_millis", value.eligibleAtMillis)

    private fun decodeReadiness(json: JSONObject): AgentBenchmarkCaseReadiness? = runCatching {
        AgentBenchmarkCaseReadiness(
            caseId = json.getString("case_id"),
            status = AgentBenchmarkReadinessStatus.valueOf(json.getString("status")),
            reasonCode = json.optString("reason_code"),
            eligibleAtMillis = json.optLong("eligible_at_millis").coerceAtLeast(0L)
        )
    }.getOrNull()

    private fun encodeResult(value: AgentBenchmarkTrialResult) = JSONObject()
        .put("id", value.id)
        .put("session_id", value.sessionId)
        .put("case_id", value.caseId)
        .put("campaign_id", value.campaignId)
        .put("trial_id", value.trialId)
        .put("run_id", value.runId)
        .put("resource_id", value.resourceId)
        .put("repetition", value.repetition)
        .put("passed", value.passed)
        .put("verified", value.verified)
        .put("failure_reasons", JSONArray(value.failureReasons))
        .put("duration_millis", value.durationMillis)
        .put("reported_cost_micros", value.reportedCostMicros)
        .put("battery_delta_percent", value.batteryDeltaPercent)
        .put("peak_thermal_status", value.peakThermalStatus)
        .put("completed_at_millis", value.completedAtMillis)

    private fun decodeResult(raw: String): AgentBenchmarkTrialResult? = runCatching {
        val json = JSONObject(raw)
        AgentBenchmarkTrialResult(
            id = json.getString("id"),
            sessionId = json.getString("session_id"),
            caseId = json.getString("case_id"),
            campaignId = json.getString("campaign_id"),
            trialId = json.getString("trial_id"),
            runId = json.getString("run_id"),
            resourceId = json.getString("resource_id"),
            repetition = json.optInt("repetition").coerceAtLeast(1),
            passed = json.optBoolean("passed"),
            verified = json.optBoolean("verified"),
            failureReasons = json.optJSONArray("failure_reasons").strings(),
            durationMillis = json.optLong("duration_millis").coerceAtLeast(0L),
            reportedCostMicros = json.optLong("reported_cost_micros").coerceAtLeast(0L),
            batteryDeltaPercent = json.optInt("battery_delta_percent").coerceAtLeast(0),
            peakThermalStatus = json.optInt("peak_thermal_status", -1),
            completedAtMillis = json.optLong("completed_at_millis")
        )
    }.getOrNull()

    private fun JSONArray?.strings(): List<String> = buildList {
        if (this@strings == null) return@buildList
        for (index in 0 until length()) optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
    }

    private fun JSONArray?.objects(): List<JSONObject> = buildList {
        if (this@objects == null) return@buildList
        for (index in 0 until length()) optJSONObject(index)?.let(::add)
    }

    private fun JSONObject?.stringMap(): Map<String, String> = buildMap {
        if (this@stringMap == null) return@buildMap
        keys().forEach { key -> optString(key).trim().takeIf(String::isNotBlank)?.let { put(key, it) } }
    }

    private fun JSONObject?.stringListMap(): Map<String, List<String>> = buildMap {
        if (this@stringListMap == null) return@buildMap
        keys().forEach { key -> put(key, optJSONArray(key).strings()) }
    }

    private fun JSONObject?.readinessMap(): Map<String, AgentBenchmarkCaseReadiness> = buildMap {
        if (this@readinessMap == null) return@buildMap
        keys().forEach { key ->
            optJSONObject(key)?.let(::decodeReadiness)?.let { put(key, it) }
        }
    }

    private companion object {
        val LOCK = Any()
        const val DATABASE = "signalasi_agent_benchmark_v1"
        const val SESSION_PREFIX = "session:"
        const val RESULT_PREFIX = "result:"
        const val RESULT_COUNT_PREFIX = "result-count:"
        const val LATEST_SESSION_PREFIX = "latest-session:"
        const val NO_SESSION_INDEX = "-"
        const val MAX_SESSIONS = 20
        const val MAX_RESULTS = 5_000
    }
}

object AgentBenchmarkStatistics {
    fun scorecard(
        session: AgentBenchmarkSession,
        suite: AgentBenchmarkSuite,
        allResults: List<AgentBenchmarkTrialResult>
    ): AgentBenchmarkScorecard {
        val results = allResults.filter { it.sessionId == session.id }
            .groupBy(AgentBenchmarkTrialResult::trialId)
            .mapNotNull { (_, attempts) -> attempts.maxByOrNull(AgentBenchmarkTrialResult::completedAtMillis) }
        val dimensions = AgentBenchmarkDimension.entries.map { dimension ->
            val ids = session.caseIds.filter { suite.case(it)?.dimension == dimension }
            metric(session, ids, results, suite.targetPassRate, null, dimension)
        }
        val resourceScores = session.resources.map { resource ->
            val assigned = session.caseIds.filter { resource.resourceId in session.resourceIdsByCase[it].orEmpty() }
            val resourceResults = results.filter { it.resourceId == resource.resourceId }
            AgentBenchmarkResourceScore(
                resource = resource,
                overall = metric(session, assigned, resourceResults, suite.targetPassRate, resource.resourceId, null),
                dimensions = AgentBenchmarkDimension.entries.map { dimension ->
                    val ids = assigned.filter { suite.case(it)?.dimension == dimension }
                    metric(session, ids, resourceResults, suite.targetPassRate, resource.resourceId, dimension)
                }
            )
        }
        return AgentBenchmarkScorecard(
            session = session,
            overall = metric(session, session.caseIds, results, suite.targetPassRate, null, null),
            dimensions = dimensions,
            resources = resourceScores
        )
    }

    private fun metric(
        session: AgentBenchmarkSession,
        caseIds: List<String>,
        results: List<AgentBenchmarkTrialResult>,
        target: Double,
        resourceId: String?,
        dimension: AgentBenchmarkDimension?
    ): AgentBenchmarkMetric {
        val allAssignments = buildList {
            caseIds.forEach { caseId ->
                session.resourceIdsByCase[caseId].orEmpty()
                    .filter { resourceId == null || it == resourceId }
                    .forEach { add(caseId to it) }
            }
        }
        val assignments = allAssignments.filter { it.first in session.scheduledCaseIds }
        val relevant = results.filter { result -> assignments.any { it.first == result.caseId && it.second == result.resourceId } }
        val expectedTrials = assignments.size * session.repetitions
        val completeGroups = assignments.count { (caseId, assignedResource) ->
            relevant.count { it.caseId == caseId && it.resourceId == assignedResource } >= session.repetitions
        }
        val coveredTasks = caseIds.count { caseId ->
            val assigned = assignments.filter { it.first == caseId }
            assigned.isNotEmpty() && assigned.all { pair ->
                relevant.count { it.caseId == pair.first && it.resourceId == pair.second } >= session.repetitions
            }
        }
        val classified = relevant.associateWith(AgentBenchmarkTrialClassificationPolicy::classify)
        val evaluable = relevant.filter {
            classified[it] != AgentBenchmarkTrialClassification.WAITING_FOR_REAL_CONDITION
        }
        val passAt1 = evaluable.takeIf(List<*>::isNotEmpty)?.let {
            it.count(AgentBenchmarkTrialResult::passed).toDouble() / it.size
        }
        val evaluableGroups = assignments.mapNotNull { (caseId, assignedResource) ->
            relevant.filter { it.caseId == caseId && it.resourceId == assignedResource }
                .takeIf { group ->
                    group.size >= session.repetitions && group.takeLast(session.repetitions).none { result ->
                        classified[result] == AgentBenchmarkTrialClassification.WAITING_FOR_REAL_CONDITION
                    }
                }
        }
        val passPower = evaluableGroups.takeIf(List<*>::isNotEmpty)?.let { groups ->
            groups.count { group ->
                group.takeLast(session.repetitions).all(AgentBenchmarkTrialResult::passed)
            }.toDouble() / groups.size
        }
        val qualified = assignments.isNotEmpty() && relevant.size >= expectedTrials && completeGroups == assignments.size
        val completedWaitingTrials = classified.values.count {
            it == AgentBenchmarkTrialClassification.WAITING_FOR_REAL_CONDITION
        }
        val waitingAssignments = allAssignments.count { (caseId, _) ->
            session.readinessByCase[caseId]?.status == AgentBenchmarkReadinessStatus.WAITING
        }
        val blockedAssignments = allAssignments.count { (caseId, _) ->
            session.readinessByCase[caseId]?.status == AgentBenchmarkReadinessStatus.BLOCKED
        }
        val waitingTrials = completedWaitingTrials + waitingAssignments * session.repetitions
        val blockedTrials = blockedAssignments * session.repetitions
        val plannedTrials = allAssignments.size * session.repetitions
        val notExecutedTrials = (expectedTrials - relevant.size).coerceAtLeast(0)
        val certificationComplete = qualified && waitingTrials == 0 && blockedTrials == 0 &&
            caseIds.all { it in session.scheduledCaseIds }
        val evaluableTaskCount = caseIds.count { caseId ->
            val assigned = assignments.filter { it.first == caseId }
            assigned.isNotEmpty() && assigned.all { pair ->
                val group = relevant.filter { it.caseId == pair.first && it.resourceId == pair.second }
                group.size >= session.repetitions && group.takeLast(session.repetitions).none { result ->
                    classified[result] == AgentBenchmarkTrialClassification.WAITING_FOR_REAL_CONDITION
                }
            }
        }
        return AgentBenchmarkMetric(
            dimension = dimension,
            taskCount = caseIds.size,
            coveredTaskCount = coveredTasks,
            expectedTrials = expectedTrials,
            completedTrials = relevant.size.coerceAtMost(expectedTrials),
            verifiedTrials = relevant.count(AgentBenchmarkTrialResult::verified).coerceAtMost(expectedTrials),
            passAt1 = passAt1,
            passPowerK = passPower,
            averageLatencyMillis = relevant.map(AgentBenchmarkTrialResult::durationMillis).averageLong(),
            averageReportedCostMicros = relevant.map(AgentBenchmarkTrialResult::reportedCostMicros).averageLong(),
            averageBatteryDeltaPercent = relevant.map(AgentBenchmarkTrialResult::batteryDeltaPercent)
                .let { if (it.isEmpty()) 0.0 else it.average() },
            peakThermalStatus = relevant.maxOfOrNull(AgentBenchmarkTrialResult::peakThermalStatus) ?: -1,
            qualified = qualified,
            targetMet = certificationComplete && passAt1 != null && passAt1 > target &&
                passPower != null && passPower > target,
            passedTrials = classified.values.count { it == AgentBenchmarkTrialClassification.PASSED },
            capabilityFailureTrials = classified.values.count {
                it == AgentBenchmarkTrialClassification.CAPABILITY_FAILURE
            },
            infrastructureFailureTrials = classified.values.count {
                it == AgentBenchmarkTrialClassification.INFRASTRUCTURE_FAILURE
            },
            waitingForRealConditionTrials = waitingTrials,
            evaluableTrials = evaluable.size,
            evaluableTaskCount = evaluableTaskCount,
            certificationComplete = certificationComplete,
            plannedTrials = plannedTrials,
            notExecutedTrials = notExecutedTrials,
            blockedTrials = blockedTrials,
            certificationCoverage = plannedTrials.takeIf { it > 0 }?.let {
                evaluable.size.toDouble() / it
            }
        )
    }

    private fun List<Long>.averageLong(): Long = if (isEmpty()) 0L else sum() / size
}

object AgentBenchmarkComparisonPolicy {
    fun comparable(left: AgentBenchmarkSession, right: AgentBenchmarkSession): Boolean =
        left.suiteId == right.suiteId &&
            left.suiteVersion == right.suiteVersion &&
            left.caseIds == right.caseIds &&
            left.repetitions == right.repetitions &&
            left.resourceIdsByCase.values.map(List<String>::size) == right.resourceIdsByCase.values.map(List<String>::size) &&
            left.teamResourceIdsByCase.values.map(List<String>::size) ==
            right.teamResourceIdsByCase.values.map(List<String>::size)
}
