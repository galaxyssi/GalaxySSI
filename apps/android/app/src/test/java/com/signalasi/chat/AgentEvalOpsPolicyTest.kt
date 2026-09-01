package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

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
}
