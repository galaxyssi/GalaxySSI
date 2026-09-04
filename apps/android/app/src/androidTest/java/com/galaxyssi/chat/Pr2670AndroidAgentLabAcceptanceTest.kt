package com.galaxyssi.chat

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class Pr2670AndroidAgentLabAcceptanceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun requireSmT575() {
        assertEquals("SM-T575", Build.MODEL.replace('_', '-').uppercase())
    }

    @Test
    fun feature04EvalOpsMemoryHorizonAndAndroidWorldVerifier() {
        val now = System.currentTimeMillis()
        val query = "pr2670-memory-${UUID.randomUUID()}"
        val runId = "pr2670-run-${UUID.randomUUID()}"
        val trust = AgentMemoryTrustStore(context)
        assertNotNull(trust.recordSelection(
            memoryIds = listOf("memory-90-day"),
            conversationId = "pr2670-acceptance",
            turnId = "turn-04",
            query = query,
            memoryTimestampsMillis = listOf(now - 91L * DAY_MILLIS),
            nowMillis = now - 1_000L
        ))
        assertEquals(0, trust.attachAnswer("pr2670-acceptance", runId, "wrong", query = "other", answeredAtMillis = now))
        assertEquals(1, trust.attachAnswer("pr2670-acceptance", runId, "verified", query = query, answeredAtMillis = now))
        assertNotNull(trust.verifiedUsageForRun(runId, 90, now))

        val packageName = context.packageName
        val task = AgentAndroidWorldTask(
            id = "pr2670-world",
            instruction = "Verify GalaxySSI is installed",
            category = "acceptance",
            requiredPackages = listOf(packageName),
            verifiers = emptyList()
        )
        val result = AgentAndroidWorldEvaluator.evaluate(
            task,
            AgentAndroidWorldObservation("", emptyList(), emptyMap(), emptyMap(), setOf(packageName)),
            runId
        )
        assertTrue(result.passed)
    }

    @Test
    fun feature05TrajectoryCompilerKeepsStableStepsAndRegressionCases() {
        val stable = descriptor("test.stable")
        val oneOff = descriptor("test.one_off")
        val runtime = AgentSkillRuntime(availableNativeToolIds = setOf(stable.id, oneOff.id))
        val runs = listOf(
            completedRun("run-1", "Process item one", stable.id),
            completedRun("run-2", "Process item two", stable.id),
            completedRun("run-3", "Process item three", stable.id, oneOff.id)
        )
        val manifest = AgentConversationSkillCompiler(runtime) { listOf(stable, oneOff) }.compile(runs)

        assertEquals(listOf(stable.id), manifest.steps.map(AgentSkillStep::toolId))
        assertEquals(3, manifest.tests.size)
    }

    @Test
    fun feature06OpenSkillIsLocallySignedBeforeInstallAndCanRollback() {
        GalaxySSICrypto.initialize(context)
        val runtime = AgentSkillRuntime(availableNativeToolIds = setOf(AGENT_ORCHESTRATION_TOOL_ID))
        val manifest = skill("pr2670-signed-skill", "1.0.0", "Use the verified workflow")
        val installer = AgentSkillMarkdownInstaller(runtime)
        val installed = installer.approveSignAndInstall(AgentSkillMarkdownCodec.encode(manifest))

        assertTrue(installed.enabled)
        val signed = AgentSkillMarkdownSigner.sign(AgentSkillMarkdownCodec.encode(manifest))
        val inspection = installer.inspect(signed)
        assertTrue(inspection.signed)
        assertTrue(inspection.signatureValid)

        runtime.install(skill(manifest.id, "1.1.0", "Updated workflow"))
        val restored = AgentSkillVersionManager(runtime).rollback(manifest.id, "1.1.0")
        assertEquals("1.0.0", restored.version)
        assertFalse(runtime.get(manifest.id, "1.1.0")?.enabled ?: true)
    }

    @Test
    fun feature07MemoryTrustExcludesPrivateAndSupersededItems() {
        val store = InMemoryAgentMemoryStore()
        val current = store.remember(AgentMemoryItem(
            id = "current",
            kind = AgentMemoryKind.IDENTITY,
            value = "My name is Test User",
            key = "user.name"
        )).item!!
        store.remember(AgentMemoryItem(
            id = "private",
            kind = AgentMemoryKind.PREFERENCE,
            value = "Private preference",
            key = "user.private",
            privateMemory = true
        ))

        assertEquals(listOf(current.id), store.recall("Test User").map(AgentMemoryItem::id))
        assertTrue(store.recall("Private preference").isEmpty())
        assertTrue(store.deprecateById(current.id))
        assertTrue(store.recall("Test User").isEmpty())
    }

    @Test
    fun feature08QualityRoutingNeedsVerifiedEvidenceBeforeSwitching() {
        val actual = candidate("actual", 400)
        val better = candidate("better", 500)
        val samples = (1..6).map { index -> sample("sample-$index", "better", true, index.toLong()) }
        val recommendation = AgentQualityAwareRoutingPolicy.recommend(
            goal = "Answer this general question",
            requirements = AgentTaskRequirementAnalyzer.analyze("Answer this general question"),
            candidates = listOf(actual, better),
            samples = samples,
            actualResourceId = "actual",
            settings = AgentEvalOpsSettings(
                shadowRoutingEnabled = true,
                automaticQualityRoutingEnabled = true,
                minimumAutomaticRoutingSamples = 6
            )
        )

        assertEquals("better", recommendation?.recommendedResourceId)
        assertTrue(recommendation?.shouldAutoSwitch == true)
    }

    @Test
    fun feature09OutcomeBoardDoesNotCountPartialEvidenceAsPass() {
        val passed = sample("passed", "agent", true, 1L)
        val partial = passed.copy(
            runId = "partial",
            verdict = AgentEvalVerdict.PARTIAL,
            contractSatisfied = false,
            failureReasons = listOf("missing_evidence:artifact_digest")
        )
        val dashboard = AgentEvalStatistics.dashboard(listOf(passed, partial), 2)

        assertEquals(0.5, dashboard.passAt1, 0.0001)
        assertEquals(0.0, dashboard.passPowerK, 0.0001)
    }

    @Test
    fun feature10AttentionBudgetSeparatesInsightFromNoise() {
        val useful = AgentAttentionBudgetPolicy.evaluate(
            AgentAttentionCandidate(0.98, 0.96, 0.96, 0.96, 0.05, 0.05, 0.05),
            0.58
        )
        val noise = AgentAttentionBudgetPolicy.evaluate(
            AgentAttentionCandidate(0.20, 0.20, 0.30, 0.20, 0.90, 0.80, 0.80),
            0.58
        )

        assertEquals(AgentAttentionDisposition.NOTIFY_NOW, useful.disposition)
        assertEquals(AgentAttentionDisposition.DISCARD, noise.disposition)
    }

    @Test
    fun feature11KnowledgeGapQueuesOnlyAuthorizedHighValueResearch() {
        val gap = AgentKnowledgeGap(
            topic = "Missing evidence",
            knownSummary = "A run was incomplete",
            unknownQuestions = listOf("Which primary source verifies it?"),
            missingEvidence = listOf("verified_source"),
            priority = 0.80
        )

        assertTrue(AgentKnowledgeGapResearchPolicy.shouldQueue(gap, true, false))
        assertFalse(AgentKnowledgeGapResearchPolicy.shouldQueue(gap, false, false))
        assertFalse(AgentKnowledgeGapResearchPolicy.shouldQueue(gap, true, true))
    }

    @Test
    fun feature12AcpAndA2aRejectWrongProtocolOrIdentity() {
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
            endpointId = "endpoint",
            protocol = AgentStandardProtocol.A2A,
            displayName = "Endpoint",
            identityFingerprint = "ABC123",
            allowedCapabilities = setOf(AgentCapability.CODE),
            enabled = true
        )
        assertNull(AgentProtocolAuthorizationPolicy.denialReason(grant, "abc123", request))
        assertEquals("endpoint_identity_mismatch", AgentProtocolAuthorizationPolicy.denialReason(grant, "other", request))
    }

    @Test
    fun feature13AgentLabRecoveryAndBlindReviewHideProviderIdentity() {
        val campaign = AgentLabCampaign(
            task = "Compare implementations",
            outcomeContract = AgentOutcomeContractCompiler.compile("lab", "Compare implementations"),
            trials = listOf(AgentLabTrial(
                agentId = "codex-agent-desktop",
                blindAlias = "Agent A",
                repetition = 1,
                runId = "interrupted",
                status = AgentLabTrialStatus.RUNNING
            )),
            status = AgentLabCampaignStatus.RUNNING
        )
        val recovered = AgentLabRecoveryPolicy.resetInterrupted(campaign, AgentEvalCondition.PROCESS_DEATH)
        val redacted = AgentBlindReviewSanitizer.redact(
            "Codex used codex-agent-desktop",
            listOf("codex-agent-desktop")
        )

        assertEquals("interrupted", recovered.trials.single().previousRunId)
        assertEquals(AgentLabTrialStatus.PENDING, recovered.trials.single().status)
        assertFalse(redacted.contains("Codex", ignoreCase = true))
    }

    @Test
    fun feature14ShadowReleaseRequiresShadowCanaryAndApprovalStages() {
        val decision = AgentShadowReleaseDecision(promote = true, rollback = false, reasons = emptyList())
        val regression = AgentShadowReleaseDecision(promote = false, rollback = true, reasons = listOf("crash_regression"))

        assertEquals(
            AgentShadowReleaseStage.CANARY,
            AgentShadowReleaseTransitionPolicy.afterComparison(AgentShadowReleaseStage.DEVICE_SHADOW, decision)
        )
        assertEquals(AgentShadowReleaseStage.WAITING_APPROVAL, AgentShadowReleaseTransitionPolicy.afterCanary(decision))
        assertEquals(AgentShadowReleaseStage.ROLLED_BACK, AgentShadowReleaseTransitionPolicy.afterCanary(regression))
    }

    private fun descriptor(id: String) = AgentNativeToolDescriptor(
        id = id,
        version = "1.0.0",
        title = id,
        description = "Acceptance tool",
        location = AgentNativeToolLocation.APPLICATION,
        inputSchema = AgentNativeJsonSchema.any(),
        outputSchema = AgentNativeJsonSchema.any(),
        risk = AgentNativeToolRisk.LOW
    )

    private fun completedRun(id: String, request: String, vararg tools: String) = AgentRecordedRun(
        runId = id,
        conversationId = "acceptance",
        taskThreadId = "thread",
        originalRequest = request,
        toolCalls = tools.mapIndexed { index, tool ->
            AgentToolCallRecord(
                id = "$id-$index",
                toolName = tool,
                status = AgentToolCallStatus.SUCCEEDED,
                argumentsJson = "{\"request\":\"$request\"}"
            )
        },
        status = AgentRecordedRunStatus.COMPLETED
    )

    private fun skill(id: String, version: String, instructions: String) = AgentSkillManifest(
        id = id,
        version = version,
        title = "PR 2670 Skill",
        instructions = instructions,
        nativeTools = setOf(AGENT_ORCHESTRATION_TOOL_ID),
        steps = listOf(AgentSkillStep("run", AGENT_ORCHESTRATION_TOOL_ID))
    )

    private fun candidate(id: String, score: Int) = AgentResourceCandidate(
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

    private fun sample(id: String, resourceId: String, passed: Boolean, completedAt: Long) = AgentEvalSample(
        runId = id,
        scenarioId = "scenario",
        taskClass = AgentEvalTaskClass.GENERAL,
        resourceId = resourceId,
        verdict = if (passed) AgentEvalVerdict.PASSED else AgentEvalVerdict.FAILED,
        contractSatisfied = passed,
        verified = true,
        durationMillis = 500L,
        completedAtMillis = completedAt
    )

    private companion object {
        const val DAY_MILLIS = 86_400_000L
    }
}
