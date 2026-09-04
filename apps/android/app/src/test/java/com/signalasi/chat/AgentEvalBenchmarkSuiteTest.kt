package com.signalasi.chat

import org.json.JSONArray
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
        val standardDimensions = suite.cases.map(AgentBenchmarkCase::dimension).distinct()
        assertEquals(6, standardDimensions.size)
        standardDimensions.forEach { dimension ->
            assertEquals(10, suite.cases.count { it.dimension == dimension })
        }
        assertEquals(10, AgentEvalBenchmarkCatalog.longitudinalMemory.cases.size)
        assertTrue(AgentEvalBenchmarkCatalog.longitudinalMemory.cases.all {
            it.dimension == AgentBenchmarkDimension.LONG_TERM_MEMORY
        })
        assertEquals(50, suite.minimumTaskCount)
        assertEquals(100, suite.maximumTaskCount)
        assertEquals(3, suite.minimumRepetitions)
        assertEquals(10, suite.maximumRepetitions)
        assertEquals(0.95, suite.targetPassRate, 0.0001)
    }

    @Test
    fun allocationUsesNinetyTenForSoloTasksAndBothAgentsForTeamTasks() {
        val codex = registration("codex-desktop", "Codex Agent", "codex")
        val deepSeek = registration("deepseek-cloud", "DeepSeek", "deepseek-chat")
        val ignored = registration("claude-cloud", "Claude", "claude-sonnet")

        val allocation = AgentBenchmarkAllocationPolicy.codexDeepSeek90To10(
            suite,
            listOf(codex, deepSeek, ignored)
        )

        assertEquals(setOf(codex.agentId, deepSeek.agentId), allocation.resources.mapTo(hashSetOf()) { it.agentId })
        val soloDimensions = suite.cases.map(AgentBenchmarkCase::dimension).distinct() -
            AgentBenchmarkDimension.MULTI_AGENT
        soloDimensions.forEach { dimension ->
            val assignments = suite.cases.filter { it.dimension == dimension }
                .map { allocation.resourceIdsByCase.getValue(it.id).single() }
            assertEquals(9, assignments.count { it == codex.agentId })
            assertEquals(1, assignments.count { it == deepSeek.agentId })
        }
        assertEquals(45, soloDimensions.flatMap { dimension ->
            suite.cases.filter { it.dimension == dimension }
        }.count { allocation.resourceIdsByCase.getValue(it.id).single() == codex.agentId })
        assertEquals(5, soloDimensions.flatMap { dimension ->
            suite.cases.filter { it.dimension == dimension }
        }.count { allocation.resourceIdsByCase.getValue(it.id).single() == deepSeek.agentId })
        suite.cases.filter { it.dimension == AgentBenchmarkDimension.MULTI_AGENT }.forEach { case ->
            assertEquals(listOf(codex.agentId), allocation.resourceIdsByCase.getValue(case.id))
            assertEquals(listOf(codex.agentId, deepSeek.agentId), allocation.teamResourceIdsByCase.getValue(case.id))
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
    fun preflightSchedulesOnlyCasesWithRealEvidencePaths() {
        val now = 100L * 24L * 60L * 60L * 1_000L
        val readiness = AgentBenchmarkPreflight.assess(
            suite = suite,
            capabilities = AgentBenchmarkHarnessCapabilities(
                planningAndTools = false,
                androidWorld = true,
                recoveryController = false,
                multiAgent = false,
                availableAndroidWorldTaskIds = suite.cases
                    .filter { it.dimension == AgentBenchmarkDimension.ANDROID_WORLD }
                    .mapTo(linkedSetOf(), AgentBenchmarkCase::id)
            ),
            memories = listOf(AgentMemoryItem(
                kind = AgentMemoryKind.KNOWLEDGE,
                value = "IM-01 = SASI-IM-NOVA",
                key = "evalops.immediate.im-01",
                timestampMillis = now,
                source = "evalops_immediate_fixture"
            )),
            nowMillis = now
        )

        assertEquals(AgentBenchmarkReadinessStatus.READY, readiness.getValue("quality-01").status)
        assertEquals(AgentBenchmarkReadinessStatus.BLOCKED, readiness.getValue("plan-tool-01").status)
        assertEquals(AgentBenchmarkReadinessStatus.READY, readiness.getValue("android-world-01").status)
        assertEquals(AgentBenchmarkReadinessStatus.READY, readiness.getValue("immediate-memory-01").status)
        assertEquals(AgentBenchmarkReadinessStatus.WAITING, readiness.getValue("immediate-memory-02").status)
        assertEquals(AgentBenchmarkReadinessStatus.WAITING, readiness.getValue("recovery-network-01").status)
        assertEquals(AgentBenchmarkReadinessStatus.BLOCKED, readiness.getValue("multi-agent-01").status)

        val longitudinalReadiness = AgentBenchmarkPreflight.assess(
            suite = AgentEvalBenchmarkCatalog.longitudinalMemory,
            capabilities = AgentBenchmarkHarnessCapabilities(
                planningAndTools = true,
                androidWorld = true,
                recoveryController = true,
                multiAgent = true
            ),
            memories = listOf(AgentMemoryItem(
                kind = AgentMemoryKind.KNOWLEDGE,
                value = "M30-01 = SASI-M30-ALPHA",
                key = "evalops.fixture.m30-01",
                timestampMillis = now - 31L * 24L * 60L * 60L * 1_000L,
                source = "evalops_fixture"
            )),
            nowMillis = now
        )
        assertEquals(AgentBenchmarkReadinessStatus.READY, longitudinalReadiness.getValue("memory-30-01").status)
        assertEquals(AgentBenchmarkReadinessStatus.WAITING, longitudinalReadiness.getValue("memory-90-01").status)
    }

    @Test
    fun sessionExpectedTrialsUsesOnlyPreflightReadyCases() {
        val base = session()
        val readiness = base.caseIds.associateWith { caseId ->
            AgentBenchmarkCaseReadiness(
                caseId = caseId,
                status = if (caseId.startsWith("quality-")) {
                    AgentBenchmarkReadinessStatus.READY
                } else {
                    AgentBenchmarkReadinessStatus.BLOCKED
                }
            )
        }
        val filtered = base.copy(readinessByCase = readiness)

        assertEquals(10, filtered.scheduledCaseIds.size)
        assertEquals(30, filtered.expectedTrials)
    }

    @Test
    fun everyPlanningCaseUsesOnlyRegisteredProductionNativeTools() {
        val plans = suite.cases.filter { it.dimension == AgentBenchmarkDimension.PLANNING_AND_TOOLS }
            .associateWith { AgentBenchmarkHarnessProtocol.toolsFor(it, "trial-01") }

        assertTrue(plans.values.all(List<AgentBenchmarkPlannedTool>::isNotEmpty))
        assertTrue(plans.values.flatten().all { it.id in AgentPhoneNativeToolCatalog.defaultToolIds })
        assertTrue(plans.values.flatten().none { it.id.contains("mock", ignoreCase = true) })
    }

    @Test
    fun harnessPlanCodecPreservesRealModelPlanAndNormalizesPlainTextFallback() {
        val structured = AgentBenchmarkHarnessProtocol.planJson(
            "```json\n{\"plan\":[{\"step\":\"读取设备状态\"},{\"step\":\"核验回执\"}]}\n```"
        )
        val fallback = AgentBenchmarkHarnessProtocol.planJson("先读取设备状态，再核验回执。")

        assertEquals(2, JSONArray(structured).length())
        assertEquals("读取设备状态", JSONArray(structured).getJSONObject(0).getString("step"))
        assertEquals(1, JSONArray(fallback).length())
        assertTrue(JSONArray(fallback).getJSONObject(0).getString("step").contains("核验回执"))
    }

    @Test
    fun researchReceiptPromptIsBoundedAndPreservesIndependentSources() {
        val huge = "source evidence ".repeat(20_000)
        val raw = JSONObject()
            .put("status", "succeeded")
            .put("output", JSONObject()
                .put("operation", "research")
                .put("status", "completed")
                .put("query", "Android WorkManager")
                .put("documents", JSONArray()
                    .put(JSONObject()
                        .put("citation_id", "android-lifecycle")
                        .put("url", "https://developer.android.com/guide/components/activities/process-lifecycle")
                        .put("title", "Processes and app lifecycle")
                        .put("content", huge))
                    .put(JSONObject()
                        .put("citation_id", "android-workmanager")
                        .put("url", "https://developer.android.com/topic/libraries/architecture/workmanager")
                        .put("title", "WorkManager")
                        .put("content", huge)))
                .put("results", JSONArray())
                .put("receipts", JSONArray()
                    .put(JSONObject().put("source_id", "official-android").put("status", "completed")))
                .put("research", JSONObject()
                    .put("citation_count", 2)
                    .put("evidence_brief", huge)))
            .put("receipt", JSONObject().put("invocation_id", "receipt-research"))
            .toString()
        val receipt = AgentToolCallRecord(
            id = "receipt-research",
            toolName = AgentWebIntelligenceNativeTools.RESEARCH,
            status = AgentToolCallStatus.SUCCEEDED,
            resultJson = raw
        )

        val prompt = AgentBenchmarkHarnessProtocol.finalPrompt(
            requireNotNull(suite.case("plan-tool-09")),
            "[{\"step\":\"research\"}]",
            listOf(receipt)
        )
        val sources = AgentBenchmarkHarnessProtocol.verifiedSources(receipt)

        assertTrue(prompt.length < 16_000)
        assertTrue(prompt.contains("process-lifecycle"))
        assertTrue(prompt.contains("architecture/workmanager"))
        assertFalse(prompt.contains(huge.takeLast(20_000)))
        assertEquals(2, sources.size)
        assertEquals(2, sources.map { it.getString("url") }.distinct().size)
    }

    @Test
    fun preflightBlocksOnlyPlanningCasesWhoseRequiredToolIsUnavailable() {
        val allExceptWebResearch = AgentPhoneNativeToolCatalog.defaultToolIds -
            AgentWebIntelligenceNativeTools.RESEARCH
        val readiness = AgentBenchmarkPreflight.assess(
            suite = suite,
            capabilities = AgentBenchmarkHarnessCapabilities(
                planningAndTools = true,
                androidWorld = true,
                recoveryController = false,
                multiAgent = false,
                availableToolIds = allExceptWebResearch
            ),
            memories = emptyList(),
            nowMillis = System.currentTimeMillis()
        )

        assertEquals(AgentBenchmarkReadinessStatus.READY, readiness.getValue("plan-tool-01").status)
        assertEquals(AgentBenchmarkReadinessStatus.BLOCKED, readiness.getValue("plan-tool-09").status)
        assertTrue(readiness.getValue("plan-tool-09").reasonCode.startsWith("required_tool_unavailable:"))
    }

    @Test
    fun preflightRequiresEachSpecificAndroidWorldTaskDefinition() {
        val installed = suite.cases.filter { case ->
            case.dimension == AgentBenchmarkDimension.ANDROID_WORLD && case.id != "android-world-02"
        }.mapTo(linkedSetOf(), AgentBenchmarkCase::id)
        val readiness = AgentBenchmarkPreflight.assess(
            suite = suite,
            capabilities = AgentBenchmarkHarnessCapabilities(
                planningAndTools = false,
                androidWorld = true,
                recoveryController = false,
                multiAgent = false,
                availableAndroidWorldTaskIds = installed
            ),
            memories = emptyList(),
            nowMillis = System.currentTimeMillis()
        )

        assertEquals(AgentBenchmarkReadinessStatus.READY, readiness.getValue("android-world-01").status)
        assertEquals(AgentBenchmarkReadinessStatus.BLOCKED, readiness.getValue("android-world-02").status)
        assertTrue(readiness.getValue("android-world-02").reasonCode.startsWith("android_world_task_unavailable:"))
    }

    @Test
    fun immediateEntityDisambiguationRequiresTheTargetEntityMemory() {
        val now = System.currentTimeMillis()
        val capabilities = AgentBenchmarkHarnessCapabilities(false, false, false, false)
        val alphaOnly = AgentBenchmarkPreflight.assess(
            suite = suite,
            capabilities = capabilities,
            memories = listOf(AgentMemoryItem(
                kind = AgentMemoryKind.KNOWLEDGE,
                value = "IM-09-A = SASI-IM-ALPHA",
                key = "evalops.immediate.im-09-a",
                source = "evalops_immediate_fixture",
                timestampMillis = now
            )),
            nowMillis = now
        )
        val beta = AgentBenchmarkPreflight.assess(
            suite = suite,
            capabilities = capabilities,
            memories = listOf(AgentMemoryItem(
                kind = AgentMemoryKind.KNOWLEDGE,
                value = "IM-09-B = SASI-IM-BETA",
                key = "evalops.immediate.im-09-b",
                source = "evalops_immediate_fixture",
                timestampMillis = now
            )),
            nowMillis = now
        )

        assertEquals(AgentBenchmarkReadinessStatus.WAITING, alphaOnly.getValue("immediate-memory-09").status)
        assertEquals(AgentBenchmarkReadinessStatus.READY, beta.getValue("immediate-memory-09").status)
    }

    @Test
    fun runAboveNinetyFivePercentMeetsGateAndKeepsModelWorkloadsSeparate() {
        val session = session()
        val failingCases = session.caseIds.takeLast(2).toSet()
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
        assertEquals(58.0 / 60.0, scorecard.overall.passAt1 ?: -1.0, 0.0001)
        assertEquals(58.0 / 60.0, scorecard.overall.passPowerK ?: -1.0, 0.0001)
        assertTrue(scorecard.overall.targetMet)
        assertEquals(54, scorecard.resources.first { it.resource.resourceId == "codex" }.overall.taskCount)
        assertEquals(6, scorecard.resources.first { it.resource.resourceId == "deepseek" }.overall.taskCount)
    }

    @Test
    fun exactlyNinetyFivePercentDoesNotMeetStrictAboveNinetyFiveGate() {
        val session = session()
        val failingCases = session.caseIds.takeLast(3).toSet()
        val results = buildList {
            session.caseIds.forEach { caseId ->
                repeat(session.repetitions) { repetition ->
                    add(result(
                        session = session,
                        caseId = caseId,
                        resourceId = session.resourceIdsByCase.getValue(caseId).single(),
                        repetition = repetition + 1,
                        passed = caseId !in failingCases
                    ))
                }
            }
        }

        val metric = AgentBenchmarkStatistics.scorecard(session, suite, results).overall

        assertEquals(0.95, metric.passAt1 ?: -1.0, 0.0001)
        assertEquals(0.95, metric.passPowerK ?: -1.0, 0.0001)
        assertFalse(metric.targetMet)
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
    fun structuredQualityVerifierUsesJsonSemantics() {
        val structured = requireNotNull(suite.case("quality-03"))
        val extraction = requireNotNull(suite.case("quality-07"))

        assertTrue(evaluate(structured, "{\"count\":3,\"status\":\"ready\"}").passed)
        assertTrue(evaluate(
            extraction,
            "{\"ram\":\"4GB\",\"device\":\"SM-T575\",\"os\":\"Android 13\"}"
        ).passed)
        assertFalse(evaluate(structured, "{\"status\":\"ready\",\"count\":4}").passed)
        assertFalse(evaluate(structured, "status=ready,count=3").passed)
    }

    @Test
    fun conflictVerifierAcceptsEvidenceInEitherNaturalLanguageOrder() {
        val conflict = requireNotNull(suite.case("quality-10"))

        assertTrue(evaluate(
            conflict,
            "按时间顺序，记录2（更晚）显示屏幕理解已移除，因此当前状态是屏幕理解未启用。"
        ).passed)
        assertTrue(evaluate(conflict, "屏幕理解已移除，这是较晚记录更新后的当前状态。").passed)
        assertFalse(evaluate(conflict, "记录2更晚，所以当前仍然启用屏幕理解。").passed)
        assertFalse(evaluate(conflict, "屏幕理解已移除。").passed)
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
    fun multiSourceResearchRequiresTwoDistinctVerifiedSources() {
        val case = requireNotNull(suite.case("plan-tool-09"))
        val oneSource = JSONArray()
            .put(JSONObject().put("url", "https://developer.android.com/source-a"))
            .toString()
        val twoSources = JSONArray(oneSource)
            .put(JSONObject().put("url", "https://developer.android.com/source-b"))
            .toString()
        val evidence = setOf(
            AgentOutcomeEvidenceKind.FINAL_RESPONSE,
            AgentOutcomeEvidenceKind.TOOL_RECEIPT,
            AgentOutcomeEvidenceKind.VERIFIED_SOURCE
        )

        val failed = evaluate(
            case = case,
            output = "两份 Android 官方资料的结论一致。",
            planJson = "[{\"step\":\"检索并交叉验证\"}]",
            toolCalls = listOf(toolCall()),
            evidence = evidence,
            sourcesJson = oneSource
        )
        val passed = evaluate(
            case = case,
            output = "两份 Android 官方资料的结论一致。",
            planJson = "[{\"step\":\"检索并交叉验证\"}]",
            toolCalls = listOf(toolCall()),
            evidence = evidence,
            sourcesJson = twoSources
        )

        assertFalse(failed.passed)
        assertTrue("insufficient_verified_sources" in failed.failureReasons)
        assertTrue(passed.passed)
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
        assertFalse("recovery_failed_after_observation" in missing.failureReasons)
        assertTrue(recovered.passed)
    }

    @Test
    fun scoreSeparatesWaitingConditionsWithoutClaimingFullCertification() {
        val cases = listOf("quality-01", "memory-30-01", "recovery-network-01")
        val session = session(
            caseIds = cases,
            assignment = cases.associateWith { listOf("codex") }
        )
        val results = buildList {
            cases.forEach { caseId ->
                repeat(session.repetitions) { repetition ->
                    val reasons = when (caseId) {
                        "memory-30-01" -> listOf("memory_horizon_not_verified")
                        "recovery-network-01" -> listOf("condition_not_observed")
                        else -> emptyList()
                    }
                    add(result(
                        session = session,
                        caseId = caseId,
                        resourceId = "codex",
                        repetition = repetition + 1,
                        passed = reasons.isEmpty(),
                        failureReasons = reasons
                    ))
                }
            }
        }

        val metric = AgentBenchmarkStatistics.scorecard(session, suite, results).overall

        assertTrue(metric.qualified)
        assertFalse(metric.certificationComplete)
        assertFalse(metric.targetMet)
        assertEquals(1.0, metric.passAt1 ?: -1.0, 0.0001)
        assertEquals(1.0, metric.passPowerK ?: -1.0, 0.0001)
        assertEquals(3, metric.passedTrials)
        assertEquals(6, metric.waitingForRealConditionTrials)
        assertEquals(3, metric.evaluableTrials)
        assertEquals(1, metric.evaluableTaskCount)
    }

    @Test
    fun scoreReportsReadyWaitingBlockedAndNotExecutedTrialsSeparately() {
        val cases = listOf("quality-01", "memory-30-01", "multi-agent-01")
        val base = session(
            caseIds = cases,
            assignment = cases.associateWith { listOf("codex") }
        )
        val session = base.copy(readinessByCase = mapOf(
            "quality-01" to AgentBenchmarkCaseReadiness(
                "quality-01",
                AgentBenchmarkReadinessStatus.READY
            ),
            "memory-30-01" to AgentBenchmarkCaseReadiness(
                "memory-30-01",
                AgentBenchmarkReadinessStatus.WAITING,
                "memory_horizon_not_reached"
            ),
            "multi-agent-01" to AgentBenchmarkCaseReadiness(
                "multi-agent-01",
                AgentBenchmarkReadinessStatus.BLOCKED,
                "multi_agent_harness_unavailable"
            )
        ))
        val results = listOf(result(session, "quality-01", "codex", 1, passed = true))

        val metric = AgentBenchmarkStatistics.scorecard(session, suite, results).overall

        assertEquals(9, metric.plannedTrials)
        assertEquals(3, metric.expectedTrials)
        assertEquals(2, metric.notExecutedTrials)
        assertEquals(3, metric.waitingForRealConditionTrials)
        assertEquals(3, metric.blockedTrials)
        assertEquals(1, metric.evaluableTrials)
        assertEquals(1.0 / 9.0, metric.certificationCoverage ?: -1.0, 0.0001)
        assertFalse(metric.certificationComplete)
    }

    @Test
    fun observedRecoveryFailureCountsAsCapabilityFailure() {
        assertEquals(
            AgentBenchmarkTrialClassification.CAPABILITY_FAILURE,
            AgentBenchmarkTrialClassificationPolicy.classify(
                passed = false,
                failureReasons = listOf("recovery_failed_after_observation")
            )
        )
        assertEquals(
            AgentBenchmarkTrialClassification.WAITING_FOR_REAL_CONDITION,
            AgentBenchmarkTrialClassificationPolicy.classify(
                passed = false,
                failureReasons = listOf("condition_not_observed")
            )
        )
    }

    @Test
    fun failedToolReceiptCannotPassPlanningAndTools() {
        val case = suite.case("plan-tool-03")!!
        val failedTool = AgentToolCallRecord(
            id = "tool-failed",
            toolName = AgentHardwareNativeTools.NETWORK_STATUS,
            status = AgentToolCallStatus.FAILED,
            errorMessage = "network_unavailable"
        )

        val result = evaluate(
            case = case,
            output = "网络工具返回不可用，未生成成功结论。",
            planJson = "[{\"step\":\"检查网络\"}]",
            toolCalls = listOf(failedTool)
        )

        assertFalse(result.passed)
        assertTrue("missing_tool_receipt" in result.failureReasons)
        assertTrue(result.failureReasons.any { it.startsWith("tool_infrastructure:") })
        assertEquals(
            AgentBenchmarkTrialClassification.INFRASTRUCTURE_FAILURE,
            AgentBenchmarkTrialClassificationPolicy.classify(result)
        )
    }

    @Test
    fun faultControllerRequiresFreshDeviceBoundLeaseAndCorrelatedReceipt() {
        val now = 2_000_000L
        val lease = AgentEvalFaultControllerLease(
            controllerId = "controller-1",
            packageName = "com.signalasi.chat",
            deviceModel = "SM-T575",
            issuedAtMillis = now - 10_000L,
            heartbeatAtMillis = now - 1_000L,
            expiresAtMillis = now + 60_000L
        )
        val request = AgentEvalFaultRequest(
            nonce = "nonce-1",
            caseId = "recovery-network-01",
            trialId = "trial-1",
            runId = "run-1",
            condition = AgentEvalCondition.NETWORK_LOSS,
            controllerId = lease.controllerId,
            packageName = "com.signalasi.chat",
            deviceModel = "SM-T575",
            createdAtMillis = now - 500L,
            expiresAtMillis = now + 60_000L
        )
        val receipt = AgentEvalFaultReceipt(
            nonce = request.nonce,
            caseId = request.caseId,
            trialId = request.trialId,
            runId = request.runId,
            condition = request.condition,
            controllerId = lease.controllerId,
            injectedAtMillis = now,
            action = AgentEvalCondition.NETWORK_LOSS.wireValue
        )

        assertTrue(AgentEvalFaultControllerProtocol.activeLease(
            lease, "com.signalasi.chat", "SM-T575", now
        ))
        assertFalse(AgentEvalFaultControllerProtocol.activeLease(
            lease, "com.signalasi.chat", "SM-S26U", now
        ))
        assertTrue(AgentEvalFaultControllerProtocol.validReceipt(
            request, receipt, lease.controllerId, now
        ))
        assertFalse(AgentEvalFaultControllerProtocol.validReceipt(
            request, receipt.copy(runId = "another-run"), lease.controllerId, now
        ))
        assertFalse(AgentEvalFaultControllerProtocol.validReceipt(
            request, receipt.copy(trialId = "another-trial"), lease.controllerId, now
        ))
        assertFalse(AgentEvalFaultControllerProtocol.validReceipt(
            request, receipt.copy(controllerId = "untrusted-controller"), lease.controllerId, now
        ))
        assertFalse(AgentEvalFaultControllerProtocol.validReceipt(
            request.copy(controllerId = "another-controller"), receipt, lease.controllerId, now
        ))
    }

    @Test
    fun lightweightMemoryRecallIsQueryGated() {
        assertTrue(AndroidLightweightMemoryQueryPolicy.shouldRecall("我之前说过我的项目是什么？"))
        assertTrue(AndroidLightweightMemoryQueryPolicy.shouldRecall("读取 IM-08 当前值"))
        assertFalse(AndroidLightweightMemoryQueryPolicy.shouldRecall("请计算 17 + 25"))
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
        recovered: Boolean = false,
        sourcesJson: String = "[]"
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
            sourcesJson = sourcesJson,
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
        targetPassRate = suite.targetPassRate,
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
        passed: Boolean,
        failureReasons: List<String> = if (passed) emptyList() else listOf("expected_failure")
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
        failureReasons = failureReasons,
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
