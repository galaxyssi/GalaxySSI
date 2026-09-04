package com.signalasi.chat

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import kotlin.system.measureTimeMillis

@RunWith(AndroidJUnit4::class)
class AgentEvalBenchmarkDeviceAcceptanceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun requireRequestedTargetDevice() {
        val expectedModel = InstrumentationRegistry.getArguments()
            .getString(TARGET_MODEL_ARGUMENT)
            .orEmpty()
            .trim()
        if (expectedModel.isNotBlank()) {
            assertEquals(normalizedModel(expectedModel), normalizedModel(Build.MODEL))
        }
    }

    @Test
    fun fixedSuiteAndLocalizedEntryAreAvailableOnTargetDevice() {
        val suite = AgentEvalBenchmarkCatalog.standard

        assertEquals(60, suite.cases.size)
        assertEquals(10, suite.cases.count { it.dimension == AgentBenchmarkDimension.IMMEDIATE_MEMORY })
        assertTrue(context.getString(R.string.cc_agent_benchmark_title).isNotBlank())
        assertTrue(context.getString(R.string.cc_agent_benchmark_subtitle, 60, 3).contains("60"))
    }

    @Test
    fun androidWorldCompatibleFixturesInstallWithProgrammaticVerifiers() {
        AgentAndroidWorldBenchmarkFixtures.install(context)
        val tasks = AgentAndroidWorldStore(context).tasks(200)
            .filter { it.sourceVersion == AgentEvalBenchmarkCatalog.standard.version }

        assertEquals(10, tasks.size)
        tasks.forEach { task ->
            assertTrue(task.verifiers.isNotEmpty())
            assertTrue(task.requiredPackages.contains(context.packageName))
            assertNotNull(AgentEvalBenchmarkCatalog.standard.case(task.id))
        }
    }

    @Test
    fun androidWorldResultsUseExactRunIndexOnDevice() {
        val runId = "android-world-index-${UUID.randomUUID()}"
        val expected = AgentAndroidWorldResult(
            taskId = "android-world-index-test",
            runId = runId,
            passed = true,
            verifierResults = listOf(AgentAndroidWorldVerifierResult(
                verifierId = "exact-run-index",
                passed = true,
                actual = context.packageName,
                reason = ""
            ))
        )
        val store = AgentAndroidWorldStore(context)

        store.save(expected)

        assertEquals(expected, store.resultForRun(runId))
        assertEquals(expected, store.resultsForRuns(listOf("missing", runId))[runId])
        assertNull(store.resultForRun("missing-$runId"))
    }

    @Test
    fun repeatedTrialPolicyIsThreeToTenOnDevice() {
        assertEquals(3, AgentEvalOpsSettings(repeatedTrials = 2).normalized().repeatedTrials)
        assertEquals(10, AgentEvalOpsSettings(repeatedTrials = 99).normalized().repeatedTrials)
    }

    @Test
    fun immediateMemoryFixturesAreIdempotentAndFast() {
        assertEquals(11, AgentBenchmarkMemoryFixtures.prepareImmediate(context))
        var prepared = 0
        val elapsedMillis = measureTimeMillis {
            prepared = AgentBenchmarkMemoryFixtures.prepareImmediate(context)
        }

        assertEquals(11, prepared)
        assertTrue("Idempotent memory preparation took ${elapsedMillis}ms", elapsedMillis < 3_000L)
        val readiness = AgentBenchmarkPreflight.assess(context, AgentEvalBenchmarkCatalog.standard)
        AgentEvalBenchmarkCatalog.standard.cases
            .filter { it.dimension == AgentBenchmarkDimension.IMMEDIATE_MEMORY }
            .forEach { case ->
                assertEquals(AgentBenchmarkReadinessStatus.READY, readiness.getValue(case.id).status)
            }
    }

    @Test
    fun recentEvalSamplesRemainBoundedAndFastWithProductionHistory() {
        lateinit var samples: List<AgentEvalSample>
        val elapsedMillis = measureTimeMillis {
            samples = AgentEvalOpsStore(context).samples(50)
        }

        assertTrue(samples.size <= 50)
        assertTrue("Reading 50 recent EvalOps samples took ${elapsedMillis}ms", elapsedMillis < 3_000L)
    }

    @Test
    fun availableAgentSnapshotIsReusedWithinRefreshWindow() {
        val runtime = AgentEvolutionLabRuntime(context)
        try {
            val first = runtime.availableAgents()
            lateinit var second: List<AgentRegistration>
            val elapsedMillis = measureTimeMillis {
                second = runtime.availableAgents()
            }

            assertTrue(first.isNotEmpty())
            assertEquals(first, second)
            assertTrue("Reading the cached Agent snapshot took ${elapsedMillis}ms", elapsedMillis < 500L)
        } finally {
            runtime.close()
        }
    }

    @Test
    fun structuredMemoryIdentifiersOutrankUnrelatedRecentFixtures() {
        val store = EncryptedAgentMemoryStore(context)
        val target = AgentMemoryItem(
            kind = AgentMemoryKind.IDENTITY,
            key = "evalops.immediate.im-03",
            value = "IM-03 = SASI-IM-TABLET",
            important = true,
            confidence = 1.0
        )
        val unrelated = target.copy(
            id = UUID.randomUUID().toString(),
            key = "evalops.immediate.im-10",
            value = "IM-10 = SASI-IM-PROVENANCE",
            timestampMillis = target.timestampMillis + 10_000L
        )
        val query = "从跨会话即时记忆回答 IM-03 的值"

        assertTrue(store.score(target, query) > store.score(unrelated, query))
    }

    @Test
    fun immediateMemoryPromptUsesTheLightweightForegroundPath() {
        AgentBenchmarkMemoryFixtures.prepareImmediate(context)
        val query = "从跨会话即时记忆回答 IM-03 的值"
        val conversationId = "agent-lab:device-acceptance-${UUID.randomUUID()}"
        val base = AgentConversationContext(
            conversationId = conversationId,
            summary = "",
            turns = listOf(AgentTranscriptEntry(
                id = "device-acceptance-turn",
                role = AgentTranscriptRole.USER,
                text = query,
                timestampMillis = System.currentTimeMillis(),
                conversationId = conversationId,
                turnId = "device-acceptance-${UUID.randomUUID()}"
            )),
            privateMode = false
        )
        lateinit var compiled: AgentConversationContext
        val elapsedMillis = measureTimeMillis {
            compiled = GlobalSuperAgentRuntime.get(context).augmentImmediateMemoryContext(base, query)
        }

        assertTrue(compiled.globalContext.contains("SASI-IM-TABLET"))
        assertTrue(compiled.globalContext.length <= 4_000)
        assertTrue("Immediate prompt compilation took ${elapsedMillis}ms", elapsedMillis < 3_000L)
    }

    @Test
    fun concurrentMemorySelectionsAttachToTheirOwnRuns() {
        val database = AgentEncryptedDatabase(
            context,
            "signalasi_memory_trust_test_${UUID.randomUUID()}"
        )
        val store = AgentMemoryTrustStore(database)
        val now = System.currentTimeMillis()
        try {
            repeat(3) { index ->
                assertNotNull(store.recordSelection(
                    memoryIds = listOf("memory-$index"),
                    conversationId = "conversation",
                    turnId = "turn-$index",
                    query = "same concurrent query",
                    memoryTimestampsMillis = listOf(now - 1_000L),
                    nowMillis = now + index
                ))
            }
            assertEquals(3, database.keys("pending-index:").size)
            repeat(3) { index ->
                assertEquals(1, store.attachAnswer(
                    conversationId = "conversation",
                    runId = "run-$index",
                    answer = "answer-$index",
                    query = "same concurrent query",
                    turnId = "turn-$index",
                    answeredAtMillis = now + 1_000L + index
                ))
                assertNotNull(store.verifiedUsageForRun("run-$index", 0, now + 1_000L + index))
            }
            assertTrue(database.keys("pending-index:").isEmpty())
            assertEquals(3, database.keys("run-index:").size)
        } finally {
            database.clear()
        }
    }

    @Test
    fun recoveredAttemptReplacesInterruptedTrialResult() {
        val database = AgentEncryptedDatabase(
            context,
            "signalasi_benchmark_result_test_${UUID.randomUUID()}"
        )
        val store = AgentBenchmarkStore(database)
        fun result(runId: String, passed: Boolean, completedAtMillis: Long) = AgentBenchmarkTrialResult(
            sessionId = "session",
            caseId = "recovery-process-01",
            campaignId = "campaign",
            trialId = "trial",
            runId = runId,
            resourceId = "codex",
            repetition = 1,
            passed = passed,
            verified = true,
            failureReasons = if (passed) emptyList() else listOf("interrupted"),
            durationMillis = 1_000L,
            reportedCostMicros = 0L,
            batteryDeltaPercent = 0,
            peakThermalStatus = 0,
            completedAtMillis = completedAtMillis
        )
        try {
            assertEquals(1, store.saveResult(result("old-run", false, 1L)))
            assertEquals(1, store.saveResult(result("recovered-run", true, 2L)))
            assertEquals(1, store.resultCount("session"))
            val retained = store.results("session")
            assertEquals(1, retained.size)
            assertEquals("recovered-run", retained.single().runId)
            assertTrue(retained.single().passed)
        } finally {
            database.clear()
        }
    }

    @Test
    fun standardSuiteCampaignsPersistInOneBoundedBatch() {
        val database = AgentEncryptedDatabase(
            context,
            "signalasi_agent_eval_batch_test_${UUID.randomUUID()}"
        )
        val store = AgentLabStore(database)
        lateinit var campaigns: List<AgentLabCampaign>
        try {
            store.createBatch((1..200).map { index ->
                AgentLabCampaignRequest(
                    task = "Seed retained campaign $index",
                    agentIds = listOf("codex-test"),
                    repetitions = 1
                )
            })
            val elapsedMillis = measureTimeMillis {
                campaigns = store.createBatch(AgentEvalBenchmarkCatalog.standard.cases.map { case ->
                    AgentLabCampaignRequest(
                        task = case.taggedPrompt,
                        agentIds = listOf("codex-test"),
                        repetitions = 3
                    )
                })
            }

            assertEquals(60, campaigns.size)
            val retained = store.list(200)
            assertEquals(200, retained.size)
            assertTrue(retained.map(AgentLabCampaign::id).containsAll(campaigns.map(AgentLabCampaign::id)))
            assertTrue("Batch preparation took ${elapsedMillis}ms", elapsedMillis < 10_000L)

            val cancelled = store.cancelBatch(campaigns.map(AgentLabCampaign::id))
            assertEquals(60, cancelled.size)
            assertTrue(cancelled.all { it.status == AgentLabCampaignStatus.CANCELLED })
            assertTrue(cancelled.flatMap(AgentLabCampaign::trials).all {
                it.status == AgentLabTrialStatus.CANCELLED
            })
        } finally {
            database.clear()
        }
    }

    @Test
    fun cancelledCampaignCannotBeRevivedByStaleWorkerState() {
        val database = AgentEncryptedDatabase(
            context,
            "signalasi_agent_eval_cancel_test_${UUID.randomUUID()}"
        )
        val store = AgentLabStore(database)
        try {
            val campaign = store.create("Cancellation durability", listOf("codex-test"), 3)
            assertEquals(1, store.requestCancellation(listOf(campaign.id)))

            store.save(campaign.copy(status = AgentLabCampaignStatus.RUNNING))
            val afterStaleWrite = requireNotNull(store.get(campaign.id))
            assertEquals(AgentLabCampaignStatus.CANCELLED, afterStaleWrite.status)
            assertTrue(afterStaleWrite.trials.all { it.status == AgentLabTrialStatus.CANCELLED })

            val reset = requireNotNull(store.resetIncompleteTrials(campaign.id))
            assertEquals(AgentLabCampaignStatus.CANCELLED, reset.status)
            assertTrue(store.isCancellationRequested(campaign.id))
        } finally {
            database.clear()
        }
    }

    @Test
    fun cancelledCampaignCannotBeStartedByRuntime() {
        val database = AgentEncryptedDatabase(
            context,
            "signalasi_agent_eval_runtime_cancel_test_${UUID.randomUUID()}"
        )
        val store = AgentLabStore(database)
        val runtime = AgentEvolutionLabRuntime(context, store = store)
        try {
            val staleCampaign = store.create("Runtime cancellation durability", listOf("codex-test"), 3)
            assertEquals(1, store.requestCancellation(listOf(staleCampaign.id)))

            assertTrue(store.isCancellationRequested(staleCampaign.id))
            assertEquals(false, runtime.startPrepared(staleCampaign))
            assertEquals(false, runtime.start(staleCampaign.id))
            assertTrue(runtime.snapshot().runningCampaignIds.isEmpty())
        } finally {
            runtime.close()
            database.clear()
        }
    }

    private fun normalizedModel(value: String): String = value
        .replace('_', '-')
        .trim()
        .uppercase()

    private companion object {
        const val TARGET_MODEL_ARGUMENT = "signalasi_target_model"
    }
}
