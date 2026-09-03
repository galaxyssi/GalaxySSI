package com.signalasi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentEvalBenchmarkSuiteTest {
    private val suite = AgentEvalBenchmarkCatalog.standard

    @Test
    fun standardSuiteHasSixtyFixedBalancedCases() {
        assertEquals(60, suite.cases.size)
        assertEquals(60, suite.cases.map(AgentBenchmarkCase::id).distinct().size)
        AgentBenchmarkDimension.entries.forEach { dimension ->
            assertEquals(10, suite.cases.count { it.dimension == dimension })
        }
        assertEquals(50, suite.minimumTaskCount)
        assertEquals(100, suite.maximumTaskCount)
        assertEquals(3, suite.minimumRepetitions)
        assertEquals(10, suite.maximumRepetitions)
        assertEquals(0.90, suite.targetPassRate, 0.0001)
    }

    @Test
    fun allocationUsesOnlyCodexAndDeepSeekAtExactNinetyTenSplit() {
        val codex = registration("codex-desktop", "Codex Agent", "codex")
        val deepSeek = registration("deepseek-cloud", "DeepSeek", "deepseek-chat")
        val ignored = registration("claude-cloud", "Claude", "claude-sonnet")

        val allocation = AgentBenchmarkAllocationPolicy.codexDeepSeek90To10(
            suite,
            listOf(codex, deepSeek, ignored)
        )

        assertEquals(setOf(codex.agentId, deepSeek.agentId), allocation.resources.mapTo(hashSetOf()) { it.agentId })
        assertEquals(54, allocation.resourceIdsByCase.values.count { codex.agentId in it })
        assertEquals(6, allocation.resourceIdsByCase.values.count { deepSeek.agentId in it })
        AgentBenchmarkDimension.entries.forEach { dimension ->
            val assignments = suite.cases.filter { it.dimension == dimension }
                .map { allocation.resourceIdsByCase.getValue(it.id).single() }
            assertEquals(9, assignments.count { it == codex.agentId })
            assertEquals(1, assignments.count { it == deepSeek.agentId })
        }
    }

    @Test(expected = IllegalStateException::class)
    fun allocationRefusesToPretendMissingDeepSeekWasTested() {
        AgentBenchmarkAllocationPolicy.codexDeepSeek90To10(
            suite,
            listOf(registration("codex", "Codex", "codex"))
        )
    }

    @Test
    fun completeNinetyPercentRunMeetsGateAndKeepsModelWorkloadsSeparate() {
        val session = session()
        val failingCases = session.caseIds.takeLast(6).toSet()
        val results = buildList {
            session.caseIds.forEach { caseId ->
                repeat(session.repetitions) { repetition ->
                    val resource = session.resourceIdsByCase.getValue(caseId).single()
                    add(result(
                        session = session,
                        caseId = caseId,
                        resourceId = resource,
                        repetition = repetition + 1,
                        passed = caseId !in failingCases
                    ))
                }
            }
        }

        val scorecard = AgentBenchmarkStatistics.scorecard(session, suite, results)

        assertTrue(scorecard.overall.qualified)
        assertEquals(0.90, scorecard.overall.passAt1 ?: -1.0, 0.0001)
        assertEquals(0.90, scorecard.overall.passPowerK ?: -1.0, 0.0001)
        assertTrue(scorecard.overall.targetMet)
        assertEquals(54, scorecard.resources.first { it.resource.resourceId == "codex" }.overall.taskCount)
        assertEquals(6, scorecard.resources.first { it.resource.resourceId == "deepseek" }.overall.taskCount)
    }

    @Test
    fun incompleteRunNeverClaimsTargetEvenWhenEveryObservedTrialPassed() {
        val session = session()
        val result = result(session, session.caseIds.first(), "codex", 1, passed = true)

        val metric = AgentBenchmarkStatistics.scorecard(session, suite, listOf(result)).overall

        assertFalse(metric.qualified)
        assertFalse(metric.targetMet)
        assertEquals(1.0, metric.passAt1 ?: -1.0, 0.0001)
        assertEquals(1, metric.completedTrials)
        assertEquals(180, metric.expectedTrials)
    }

    @Test
    fun qualityVerifierRequiresExpectedAnswerRatherThanAnyNonEmptyReply() {
        val case = requireNotNull(suite.case("quality-01"))
        val passed = evaluate(case, "379")
        val failed = evaluate(case, "I finished the calculation.")

        assertTrue(passed.passed)
        assertFalse(failed.passed)
        assertTrue(failed.failureReasons.any { it.startsWith("required_output_pattern:") })
    }

    @Test
    fun planningVerifierRequiresRealPlanAndToolReceipts() {
        val case = requireNotNull(suite.case("plan-tool-01"))
        val noEvidence = evaluate(case, "设备型号为 SM-T575，Android 13。")
        val withEvidence = evaluate(
            case = case,
            output = "设备型号为 SM-T575，Android 13，已使用系统信息工具核验。",
            planJson = "[{\"step\":\"读取设备信息\"}]",
            toolCalls = listOf(toolCall()),
            evidence = setOf(AgentOutcomeEvidenceKind.FINAL_RESPONSE, AgentOutcomeEvidenceKind.TOOL_RECEIPT)
        )

        assertFalse(noEvidence.passed)
        assertTrue("missing_plan_evidence" in noEvidence.failureReasons)
        assertTrue("missing_tool_receipt" in noEvidence.failureReasons)
        assertTrue(withEvidence.passed)
    }

    @Test
    fun recoveryVerifierRequiresObservedFaultAndRecoveryReceipt() {
        val case = requireNotNull(suite.case("recovery-network-01"))
        val missing = evaluate(case, "RECOVERED-NET-01")
        val recovered = evaluate(
            case = case,
            output = "RECOVERED-NET-01",
            evidence = setOf(AgentOutcomeEvidenceKind.FINAL_RESPONSE, AgentOutcomeEvidenceKind.RECOVERY_EVENT),
            observedConditions = setOf(AgentEvalCondition.NETWORK_LOSS),
            recovered = true
        )

        assertFalse(missing.passed)
        assertTrue("condition_not_observed" in missing.failureReasons)
        assertTrue("recovery_not_verified" in missing.failureReasons)
        assertTrue(recovered.passed)
    }

    @Test
    fun modelOrVersionComparisonRequiresSameEvaluationContract() {
        val baseline = session()
        assertTrue(AgentBenchmarkComparisonPolicy.comparable(baseline, baseline.copy(appVersionName = "next")))
        assertFalse(AgentBenchmarkComparisonPolicy.comparable(
            baseline,
            baseline.copy(suiteVersion = "2.0.0")
        ))
        assertFalse(AgentBenchmarkComparisonPolicy.comparable(
            baseline,
            baseline.copy(repetitions = 5)
        ))
    }

    @Test
    fun benchmarkProgressUsesIncrementalCountsAndMigratesLegacyRuns() {
        assertEquals(576, AgentBenchmarkProgressCounter.next(575, isNewResult = true, completedTrialsFloor = 0))
        assertEquals(576, AgentBenchmarkProgressCounter.next(576, isNewResult = false, completedTrialsFloor = 0))
        assertEquals(576, AgentBenchmarkProgressCounter.next(0, isNewResult = true, completedTrialsFloor = 576))
    }

    private fun evaluate(
        case: AgentBenchmarkCase,
        output: String,
        planJson: String = "[]",
        toolCalls: List<AgentToolCallRecord> = emptyList(),
        evidence: Set<AgentOutcomeEvidenceKind> = setOf(AgentOutcomeEvidenceKind.FINAL_RESPONSE),
        observedConditions: Set<AgentEvalCondition> = emptySet(),
        recovered: Boolean = false
    ): AgentBenchmarkTrialResult {
        val session = session(caseIds = listOf(case.id), assignment = mapOf(case.id to listOf("codex")))
        val trial = AgentLabTrial(agentId = "codex", blindAlias = "Agent A", repetition = 1, runId = "run")
        val campaign = AgentLabCampaign(
            id = "campaign",
            task = case.taggedPrompt,
            outcomeContract = AgentOutcomeContractCompiler.compile("run", case.taggedPrompt),
            trials = listOf(trial)
        )
        val run = AgentRecordedRun(
            runId = "run",
            conversationId = "benchmark",
            taskThreadId = "thread",
            originalRequest = case.taggedPrompt,
            agentPlanJson = planJson,
            toolCalls = toolCalls,
            finalOutputJson = JSONObject().put("text", output).toString(),
            executionResourceId = "codex",
            status = AgentRecordedRunStatus.COMPLETED,
            createdAtMillis = 1_000L,
            completedAtMillis = 2_000L
        )
        val sample = AgentEvalSample(
            runId = "run",
            scenarioId = case.id,
            taskClass = AgentEvalTaskClass.GENERAL,
            resourceId = "codex",
            verdict = AgentEvalVerdict.PASSED,
            contractSatisfied = true,
            verified = true,
            durationMillis = 1_000L,
            recovered = recovered,
            observedConditions = observedConditions,
            memoryHorizonDays = case.expectation.memoryHorizonDays,
            evidenceKinds = evidence
        )
        val events = listOf(event(AgentRunControlEventType.RUN_STARTED, "codex", 1L))
        return AgentBenchmarkTrialEvaluator.evaluate(
            session, case, campaign, trial, run, sample, events, null
        )
    }

    private fun session(
        caseIds: List<String> = suite.cases.map(AgentBenchmarkCase::id),
        assignment: Map<String, List<String>> = buildMap {
            AgentBenchmarkDimension.entries.forEach { dimension ->
                suite.cases.filter { it.dimension == dimension }.forEachIndexed { index, case ->
                    put(case.id, listOf(if (index == 9) "deepseek" else "codex"))
                }
            }
        }
    ) = AgentBenchmarkSession(
        id = "session",
        suiteId = suite.id,
        suiteVersion = suite.version,
        appVersionName = "0.5.96",
        appVersionCode = 832,
        deviceModel = "SM-T575",
        repetitions = 3,
        targetPassRate = 0.90,
        caseIds = caseIds,
        resources = listOf(
            resource("codex", "Codex"),
            resource("deepseek", "DeepSeek")
        ),
        resourceIdsByCase = assignment,
        campaignIdsByCase = caseIds.associateWith { "campaign-$it" }
    )

    private fun result(
        session: AgentBenchmarkSession,
        caseId: String,
        resourceId: String,
        repetition: Int,
        passed: Boolean
    ) = AgentBenchmarkTrialResult(
        sessionId = session.id,
        caseId = caseId,
        campaignId = "campaign-$caseId",
        trialId = "$caseId-$resourceId-$repetition",
        runId = "run-$caseId-$resourceId-$repetition",
        resourceId = resourceId,
        repetition = repetition,
        passed = passed,
        verified = true,
        failureReasons = if (passed) emptyList() else listOf("expected_failure"),
        durationMillis = 1_000,
        reportedCostMicros = 10,
        batteryDeltaPercent = 0,
        peakThermalStatus = 1
    )

    private fun resource(id: String, name: String) = AgentBenchmarkResourceSnapshot(
        resourceId = id,
        displayName = name,
        providerId = id,
        modelId = id,
        adapterType = "test",
        capabilitiesHash = "hash"
    )

    private fun registration(id: String, name: String, model: String) = AgentRegistration(
        agentId = id,
        installationId = id,
        deviceId = id,
        providerId = model,
        displayName = name,
        kind = AgentConnectorKind.AGENT,
        location = AgentResourceLocation.CLOUD,
        status = AgentEndpointStatus.ONLINE,
        capabilities = setOf(AgentCapability.CHAT, AgentCapability.REASONING),
        protocol = AgentProtocolRange("1.0", "1.0", "1.0"),
        connectionKind = AgentConnectionKind.HTTP,
        maxParallelRuns = 10,
        providerProfile = ProviderProfile(
            profileId = id,
            resourceId = id,
            providerId = model,
            productId = model,
            displayName = name,
            kind = ProviderProfileKind.CLOUD_MODEL,
            location = AgentResourceLocation.CLOUD,
            status = AgentConnectorStatus.AVAILABLE,
            protocolFamily = "test",
            adapterType = "test",
            modelId = model
        )
    )

    private fun toolCall() = AgentToolCallRecord(
        id = "tool",
        toolName = "android.system.info",
        status = AgentToolCallStatus.SUCCEEDED,
        argumentsJson = "{}"
    )

    private fun event(type: AgentRunControlEventType, agentId: String, sequence: Long) = AgentRunControlEvent(
        conversationId = "benchmark",
        messageId = "message",
        taskId = "task",
        runId = "run",
        agentId = agentId,
        deviceId = "device",
        type = type,
        sequence = sequence
    )
}
