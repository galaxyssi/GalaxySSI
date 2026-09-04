package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject

class AgentEvalOpsPolicyTest {
    @Test
    fun outcomeContractRequiresMemoryProvenanceForLongHorizonRecall() {
        val contract = AgentOutcomeContractCompiler.compile(
            "run-memory",
            "请验证我在90天前保存的长期记忆，并说明来源"
        )

        assertEquals(AgentEvalTaskClass.MEMORY, contract.taskClass)
        assertEquals(90, contract.memoryHorizonDays)
        assertTrue(AgentOutcomeEvidenceKind.FINAL_RESPONSE in contract.requiredEvidence)
        assertTrue(AgentOutcomeEvidenceKind.MEMORY_PROVENANCE in contract.requiredEvidence)
    }

    @Test
    fun empiricalPassPowerKRequiresEveryTrialInTheBatchToPass() {
        val samples = listOf(true, true, true, true, false, true).mapIndexed { index, passed ->
            sample("run-$index", passed, completedAt = index.toLong())
        }

        assertEquals(0.5, AgentEvalStatistics.empiricalPassPowerK(samples, 3), 0.0001)
        assertEquals(0.25, AgentEvalStatistics.theoreticalPassPowerK(0.5, 2), 0.0001)
    }

    @Test
    fun agentLabKeepsOnePhysicalRuntimeAndPrefersConcreteDeviceAlias() {
        val generic = registration("codex", "Codex")
        val concrete = registration("desktop-1:codex", "Codex Agent · DESKTOP-T14")

        val selected = AgentLabAgentSelectionPolicy.independentAgents(listOf(generic, concrete))

        assertEquals(listOf("desktop-1:codex"), selected.map(AgentRegistration::agentId))
    }

    @Test
    fun currentDashboardUsesNewestCompleteCampaignWithoutDeletingHistory() {
        val oldTrial = AgentLabTrial(agentId = "agent-a", blindAlias = "Agent A", repetition = 1,
            runId = "old-run", status = AgentLabTrialStatus.FAILED)
        val currentTrials = (1..10).map { index ->
            AgentLabTrial(agentId = "agent-a", blindAlias = "Agent A", repetition = index,
                runId = "current-$index", status = AgentLabTrialStatus.COMPLETED)
        }
        val old = AgentLabCampaign(
            task = "old", outcomeContract = AgentOutcomeContractCompiler.compile("old", "old"),
            trials = listOf(oldTrial), status = AgentLabCampaignStatus.READY_FOR_REVIEW,
            updatedAtMillis = 1_000L
        )
        val current = AgentLabCampaign(
            task = "current", outcomeContract = AgentOutcomeContractCompiler.compile("current", "current"),
            trials = currentTrials, blindReview = false, status = AgentLabCampaignStatus.READY_FOR_REVIEW,
            updatedAtMillis = 2_000L
        )
        val history = listOf(sample("old-run", false, 1_000L)) + currentTrials.mapIndexed { index, trial ->
            sample(trial.runId, true, 2_000L + index)
        }

        val currentSamples = AgentLabDashboardPolicy.currentCompletedSamples(listOf(old, current), history)
        val dashboard = AgentEvalStatistics.dashboard(requireNotNull(currentSamples), 10)

        assertEquals(11, history.size)
        assertEquals(10, dashboard.totalRuns)
        assertEquals(1.0, dashboard.passAt1, 0.0001)
        assertEquals(1.0, dashboard.passPowerK, 0.0001)
    }

    @Test
    fun labFailureCodeSeparatesTimeoutFromEmptyResponse() {
        val timeout = kotlinx.coroutines.runBlocking {
            runCatching {
                kotlinx.coroutines.withTimeout(1L) { kotlinx.coroutines.awaitCancellation() }
            }.exceptionOrNull()
        }
        assertEquals(
            "response_timeout",
            AgentLabRunFailurePolicy.code(timeout, null, "")
        )
        assertEquals("empty_response", AgentLabRunFailurePolicy.code(null, null, ""))
        assertEquals("", AgentLabRunFailurePolicy.code(null, null, "done"))
    }

    @Test
    fun attentionBudgetSeparatesHighValueInsightFromCostlyNoise() {
        val high = AgentAttentionBudgetPolicy.evaluate(
            AgentAttentionCandidate(
                relevance = 0.98,
                novelty = 0.96,
                credibility = 0.96,
                actionability = 0.96,
                interruptionCost = 0.10,
                tokenCost = 0.05,
                batteryCost = 0.05
            ),
            threshold = 0.58
        )
        val low = AgentAttentionBudgetPolicy.evaluate(
            AgentAttentionCandidate(
                relevance = 0.30,
                novelty = 0.30,
                credibility = 0.40,
                actionability = 0.20,
                interruptionCost = 0.90,
                tokenCost = 0.80,
                batteryCost = 0.80
            ),
            threshold = 0.58
        )

        assertEquals(AgentAttentionDisposition.NOTIFY_NOW, high.disposition)
        assertEquals(AgentAttentionDisposition.DISCARD, low.disposition)
        assertTrue(high.value > low.value)
    }

    @Test
    fun shadowReleaseRollsBackHardRegressionAndWaitsForEvidence() {
        val baseline = metrics(passAt1 = 0.90, passPowerK = 0.80, crashes = 0, runs = 20)
        val crashRegression = AgentShadowReleasePolicy.compare(
            baseline,
            metrics(passAt1 = 0.92, passPowerK = 0.82, crashes = 1, runs = 20)
        )
        val insufficient = AgentShadowReleasePolicy.compare(
            baseline,
            metrics(passAt1 = 0.95, passPowerK = 0.85, crashes = 0, runs = 4)
        )
        val promotable = AgentShadowReleasePolicy.compare(
            baseline,
            metrics(passAt1 = 0.94, passPowerK = 0.84, crashes = 0, runs = 12)
        )

        assertTrue(crashRegression.rollback)
        assertFalse(insufficient.promote)
        assertFalse(insufficient.rollback)
        assertTrue(promotable.promote)
        assertEquals(
            AgentShadowReleaseStage.CANARY,
            AgentShadowReleaseTransitionPolicy.afterComparison(
                AgentShadowReleaseStage.DEVICE_SHADOW,
                promotable
            )
        )
        assertEquals(
            AgentShadowReleaseStage.WAITING_APPROVAL,
            AgentShadowReleaseTransitionPolicy.afterCanary(promotable)
        )
        assertEquals(
            AgentShadowReleaseStage.ROLLED_BACK,
            AgentShadowReleaseTransitionPolicy.afterCanary(crashRegression)
        )
    }

    @Test
    fun interruptedLabTrialKeepsRecoveryLineageAndBecomesPending() {
        val contract = AgentOutcomeContractCompiler.compile("lab", "Do a reliable task")
        val campaign = AgentLabCampaign(
            task = "Do a reliable task",
            outcomeContract = contract,
            trials = listOf(AgentLabTrial(
                id = "trial-1",
                agentId = "agent-a",
                blindAlias = "Agent A",
                repetition = 1,
                runId = "old-run",
                status = AgentLabTrialStatus.RUNNING
            )),
            status = AgentLabCampaignStatus.RUNNING
        )

        val recovered = AgentLabRecoveryPolicy.resetInterrupted(
            campaign,
            AgentEvalCondition.PROCESS_DEATH,
            nowMillis = 2_000L
        )
        val trial = recovered.trials.single()

        assertEquals(AgentLabCampaignStatus.DRAFT, recovered.status)
        assertEquals(AgentLabTrialStatus.PENDING, trial.status)
        assertEquals("", trial.runId)
        assertEquals("old-run", trial.previousRunId)
        assertEquals(AgentEvalCondition.PROCESS_DEATH, trial.recoveryCondition)
        assertEquals(1, trial.recoveryAttempt)
    }

    @Test
    fun recoveredLabTrialUsesANewIdempotencyKey() {
        val initial = AgentLabTrial(
            id = "trial-1",
            agentId = "agent-a",
            blindAlias = "Agent A",
            repetition = 1
        )
        val recovered = initial.copy(previousRunId = "old-run", recoveryAttempt = 1)

        assertEquals("agent-lab:campaign-1:trial-1", AgentLabRunIdentity.idempotencyKey("campaign-1", initial))
        assertEquals(
            "agent-lab:campaign-1:trial-1:recovery:1",
            AgentLabRunIdentity.idempotencyKey("campaign-1", recovered)
        )
    }

    @Test
    fun incompleteLabRecoveryRekeysPendingTrialsWithLostReceipts() {
        val campaign = AgentLabCampaign(
            task = "Do a reliable task",
            outcomeContract = AgentOutcomeContractCompiler.compile("lab", "Do a reliable task"),
            trials = listOf(
                AgentLabTrial("done", "agent-a", "Agent A", 1, status = AgentLabTrialStatus.COMPLETED),
                AgentLabTrial("pending", "agent-a", "Agent A", 2)
            ),
            status = AgentLabCampaignStatus.RUNNING
        )

        val recovered = AgentLabRecoveryPolicy.resetIncomplete(
            campaign,
            AgentEvalCondition.PROCESS_DEATH,
            nowMillis = 2_000L
        )

        assertEquals(0, recovered.trials.first().recoveryAttempt)
        assertEquals(1, recovered.trials.last().recoveryAttempt)
        assertEquals(AgentLabTrialStatus.PENDING, recovered.trials.last().status)
    }

    @Test
    fun benchmarkGapRecoveryOnlyRekeysTrialsWithoutDurableResults() {
        val campaign = AgentLabCampaign(
            task = "Do a reliable task",
            outcomeContract = AgentOutcomeContractCompiler.compile("lab", "Do a reliable task"),
            trials = listOf(
                AgentLabTrial(
                    id = "recorded",
                    agentId = "agent-a",
                    blindAlias = "Agent A",
                    repetition = 1,
                    runId = "recorded-run",
                    status = AgentLabTrialStatus.COMPLETED,
                    evalSampleId = "recorded-sample"
                ),
                AgentLabTrial(
                    id = "missing",
                    agentId = "agent-a",
                    blindAlias = "Agent A",
                    repetition = 2,
                    runId = "missing-run",
                    status = AgentLabTrialStatus.FAILED,
                    evalSampleId = ""
                )
            ),
            status = AgentLabCampaignStatus.READY_FOR_REVIEW
        )

        val recovered = AgentLabRecoveryPolicy.resetTrialsMissingBenchmarkResults(
            campaign = campaign,
            trialIds = setOf("missing"),
            condition = AgentEvalCondition.PROCESS_DEATH,
            nowMillis = 2_000L
        )

        assertEquals(AgentLabCampaignStatus.DRAFT, recovered.status)
        assertEquals(campaign.trials.first(), recovered.trials.first())
        with(recovered.trials.last()) {
            assertEquals(AgentLabTrialStatus.PENDING, status)
            assertEquals("", runId)
            assertEquals("", evalSampleId)
            assertEquals("missing-run", previousRunId)
            assertEquals(AgentEvalCondition.PROCESS_DEATH, recoveryCondition)
            assertEquals(1, recoveryAttempt)
        }
    }

    @Test
    fun stalledLabCampaignRecoversWhetherItsWorkerExitedOrStoppedMakingProgress() {
        val campaign = AgentLabCampaign(
            task = "Do a reliable task",
            outcomeContract = AgentOutcomeContractCompiler.compile("lab", "Do a reliable task"),
            trials = listOf(AgentLabTrial(
                id = "trial-1",
                agentId = "agent-a",
                blindAlias = "Agent A",
                repetition = 1,
                runId = "active-run",
                status = AgentLabTrialStatus.RUNNING
            )),
            status = AgentLabCampaignStatus.RUNNING,
            updatedAtMillis = 1_000L
        )

        assertTrue(AgentLabStallRecoveryPolicy.shouldRecover(campaign, false, 2_000L, 10_000L))
        assertFalse(AgentLabStallRecoveryPolicy.shouldRecover(campaign, true, 10_999L, 10_000L))
        assertTrue(AgentLabStallRecoveryPolicy.shouldRecover(campaign, true, 11_000L, 10_000L))
    }

    @Test
    fun agentLabHeartbeatPersistsAtBoundedIntervalsWithoutMaskingClockChanges() {
        assertTrue(AgentLabHeartbeatPolicy.shouldPersist(null, 10_000L, 15_000L))
        assertFalse(AgentLabHeartbeatPolicy.shouldPersist(10_000L, 24_999L, 15_000L))
        assertTrue(AgentLabHeartbeatPolicy.shouldPersist(10_000L, 25_000L, 15_000L))
        assertTrue(AgentLabHeartbeatPolicy.shouldPersist(20_000L, 10_000L, 15_000L))
    }

    @Test
    fun evalSampleKeepsEveryObservedReliabilityCondition() {
        val contract = AgentOutcomeContractCompiler.compile("run-faults", "Complete a task")
        val events = listOf(
            recoveryEvent(AgentRunControlEventType.RETRYING, AgentEvalCondition.DOZE, 1),
            recoveryEvent(AgentRunControlEventType.RUN_RECOVERED, AgentEvalCondition.DOZE, 2),
            recoveryEvent(AgentRunControlEventType.RETRYING, AgentEvalCondition.NETWORK_LOSS, 3),
            recoveryEvent(AgentRunControlEventType.RUN_RECOVERED, AgentEvalCondition.NETWORK_LOSS, 4)
        )

        assertEquals(
            setOf(AgentEvalCondition.DOZE, AgentEvalCondition.NETWORK_LOSS),
            AgentEvalOpsService.observedConditions(contract, events)
        )
    }

    @Test
    fun continuousEvaluationSchedulesOnlyEligibleRealRunsAfterCooldown() {
        val settings = AgentEvalOpsSettings(
            captureRealRuns = true,
            continuousEvaluationEnabled = true,
            repeatedTrials = 3
        )
        val completed = completedRun("conversation")
        val eligible = AgentContinuousEvalPolicy.decide(
            settings,
            completed,
            sample("run", true, 2_000L),
            availableAgentCount = 4,
            lastScheduledAtMillis = 0L,
            nowMillis = 10_000L
        )
        val labRun = AgentContinuousEvalPolicy.decide(
            settings,
            completedRun("agent-lab:campaign"),
            sample("run-lab", true, 2_000L),
            availableAgentCount = 4,
            lastScheduledAtMillis = 0L,
            nowMillis = 10_000L
        )
        val cooldown = AgentContinuousEvalPolicy.decide(
            settings,
            completed,
            sample("run-cooldown", true, 2_000L),
            availableAgentCount = 4,
            lastScheduledAtMillis = 9_000L,
            nowMillis = 10_000L
        )

        assertTrue(eligible.schedule)
        assertEquals("agent_lab_run", labRun.reason)
        assertEquals("scenario_cooldown", cooldown.reason)
    }

    @Test
    fun agentLabRunsDoNotTrainPersonalMemoryOrAutonomy() {
        assertFalse(AgentEvalSideEffectPolicy.allowsPersonalLearning("agent-lab:campaign-1"))
        assertTrue(AgentEvalSideEffectPolicy.allowsPersonalLearning("conversation-1"))
    }

    @Test
    fun blindReviewRedactsProviderAndConnectorIdentity() {
        val redacted = AgentBlindReviewSanitizer.redact(
            "Claude completed this with codex-agent-desktop and DeepSeek.",
            listOf("codex-agent-desktop", "claude-cloud")
        )

        assertFalse(redacted.contains("Claude", ignoreCase = true))
        assertFalse(redacted.contains("Codex", ignoreCase = true))
        assertFalse(redacted.contains("DeepSeek", ignoreCase = true))
        assertTrue(redacted.contains("[Agent]"))
    }

    @Test
    fun longHorizonMemoryEvidenceRequiresOldEnoughSelectedMemory() {
        val day = 86_400_000L
        val answeredAt = 100L * day

        assertTrue(AgentMemoryHorizonPolicy.qualifies(10L * day, answeredAt, 90))
        assertFalse(AgentMemoryHorizonPolicy.qualifies(20L * day, answeredAt, 90))
        assertTrue(AgentMemoryHorizonPolicy.qualifies(99L * day, answeredAt, 0))
        assertFalse(AgentMemoryHorizonPolicy.qualifies(0L, answeredAt, 30))
    }

    @Test
    fun qualityRoutingPromotesOnlyAfterVerifiedEvidenceThreshold() {
        val actual = resourceCandidate("actual", score = 400)
        val better = resourceCandidate("better", score = 500)
        val requirements = AgentTaskRequirementAnalyzer.analyze("Answer this general question")
        val samples = (1..6).map { index ->
            sample("better-$index", true, index.toLong()).copy(resourceId = "better", durationMillis = 500)
        }
        val enabled = AgentEvalOpsSettings(
            shadowRoutingEnabled = true,
            automaticQualityRoutingEnabled = true,
            minimumAutomaticRoutingSamples = 6
        )

        val promoted = AgentQualityAwareRoutingPolicy.recommend(
            "Answer this general question",
            requirements,
            listOf(actual, better),
            samples,
            actualResourceId = "actual",
            settings = enabled
        )
        val shadowOnly = AgentQualityAwareRoutingPolicy.recommend(
            "Answer this general question",
            requirements,
            listOf(actual, better),
            samples,
            actualResourceId = "actual",
            settings = enabled.copy(automaticQualityRoutingEnabled = false)
        )

        assertEquals("better", promoted?.recommendedResourceId)
        assertTrue(promoted?.shouldAutoSwitch == true)
        assertFalse(shadowOnly?.shouldAutoSwitch ?: true)
    }

    @Test
    fun knowledgeGapResearchRequiresPriorityPermissionAndNoDuplicate() {
        val gap = AgentKnowledgeGap(
            topic = "Evidence gap",
            knownSummary = "One run was incomplete",
            unknownQuestions = listOf("Which source proves the result?"),
            missingEvidence = listOf("verified_source"),
            priority = 0.80
        )

        assertTrue(AgentKnowledgeGapResearchPolicy.shouldQueue(gap, true, false, gap.createdAtMillis))
        assertFalse(AgentKnowledgeGapResearchPolicy.shouldQueue(gap.copy(priority = 0.50), true, false))
        assertFalse(AgentKnowledgeGapResearchPolicy.shouldQueue(gap, false, false))
        assertFalse(AgentKnowledgeGapResearchPolicy.shouldQueue(gap, true, true))
    }

    @Test
    fun protocolAdaptersAndAuthorizationRejectUntrustedInboundPayloads() {
        val request = AgentRunRequest(
            conversationId = "conversation",
            messageId = "message",
            taskId = "task",
            runId = "run",
            goal = "Inspect the project",
            requiredCapabilities = setOf(AgentCapability.CODE)
        )
        val a2a = AgentA2aBoundaryAdapter.encodeRequest(request)
        val acp = AgentAcpBoundaryAdapter.encodeRequest(request)
        assertNotNull(AgentA2aBoundaryAdapter.decodeRequest(a2a))
        assertNotNull(AgentAcpBoundaryAdapter.decodeRequest(acp))
        assertNull(AgentA2aBoundaryAdapter.decodeRequest(JSONObject(a2a.toString()).put("method", "tasks/get")))
        assertNull(AgentAcpBoundaryAdapter.decodeRequest(JSONObject(acp.toString()).put("jsonrpc", "1.0")))

        val grant = AgentProtocolEndpointGrant(
            endpointId = "trusted-endpoint",
            protocol = AgentStandardProtocol.A2A,
            displayName = "Trusted endpoint",
            identityFingerprint = "ABC123",
            allowedCapabilities = setOf(AgentCapability.CODE),
            enabled = true
        )
        assertNull(AgentProtocolAuthorizationPolicy.denialReason(grant, "abc123", request))
        assertEquals(
            "endpoint_identity_mismatch",
            AgentProtocolAuthorizationPolicy.denialReason(grant, "different", request)
        )
        assertEquals(
            "capability_not_granted",
            AgentProtocolAuthorizationPolicy.denialReason(
                grant.copy(allowedCapabilities = emptySet()),
                "abc123",
                request
            )
        )
    }

    private fun sample(runId: String, passed: Boolean, completedAt: Long) = AgentEvalSample(
        runId = runId,
        scenarioId = "same-scenario",
        taskClass = AgentEvalTaskClass.GENERAL,
        resourceId = "agent-a",
        verdict = if (passed) AgentEvalVerdict.PASSED else AgentEvalVerdict.FAILED,
        contractSatisfied = passed,
        verified = true,
        durationMillis = 100,
        completedAtMillis = completedAt
    )

    private fun metrics(
        passAt1: Double,
        passPowerK: Double,
        crashes: Int,
        runs: Int
    ) = AgentShadowReleaseMetrics(
        passAt1 = passAt1,
        passPowerK = passPowerK,
        averageLatencyMillis = 1_000,
        averageBatteryDeltaPercent = 1.0,
        peakThermalStatus = 2,
        crashCount = crashes,
        verifiedRuns = runs
    )

    private fun recoveryEvent(
        type: AgentRunControlEventType,
        condition: AgentEvalCondition,
        sequence: Long
    ) = AgentRunControlEvent(
        conversationId = "conversation",
        messageId = "message",
        taskId = "task",
        runId = "run-faults",
        agentId = "agent-a",
        deviceId = "phone",
        type = type,
        sequence = sequence,
        payload = mapOf("condition" to condition.wireValue)
    )

    private fun completedRun(conversationId: String) = AgentRecordedRun(
        runId = "run",
        conversationId = conversationId,
        taskThreadId = "thread",
        originalRequest = "Compare the implementation with evidence",
        status = AgentRecordedRunStatus.COMPLETED,
        createdAtMillis = 1_000L,
        completedAtMillis = 2_000L
    )

    private fun resourceCandidate(id: String, score: Int) = AgentResourceCandidate(
        resource = AgentResourceDescriptor(
            id = id,
            title = id,
            type = AgentResourceType.CLOUD_MODEL,
            location = AgentResourceLocation.CLOUD,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = setOf(AgentCapability.CHAT, AgentCapability.REASONING),
            cost = AgentResourceCost.LOW,
            latency = AgentResourceLatency.FAST,
            quality = AgentResourceQuality.STRONG,
            supportsTools = true,
            targetId = id,
            trust = AgentResourceTrust.VERIFIED_PAIRED,
            maxParallelTasks = 10
        ),
        score = score,
        reasons = emptyList()
    )

    private fun registration(id: String, name: String) = AgentRegistration(
        agentId = id,
        installationId = "desktop-1",
        deviceId = "desktop-1",
        providerId = "desktop-1",
        displayName = name,
        kind = AgentConnectorKind.AGENT,
        location = AgentResourceLocation.TRUSTED_DESKTOP,
        status = AgentEndpointStatus.ONLINE,
        capabilities = setOf(AgentCapability.CHAT),
        protocol = AgentProtocolRange("1.0", "1.0", "1.0"),
        connectionKind = AgentConnectionKind.GALAXYSSI_LINK,
        runtimeFailureDomain = "desktop-1:codex-app-server-or-cli",
        adapterType = "codex-app-server-or-cli"
    )
}
