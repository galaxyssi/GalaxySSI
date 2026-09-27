package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Assert.*
import org.junit.Test

class PhoneAssistantTaskControlTest {
    @Test fun explicitCancellationReleasesPausedRequestWithoutCancellingAnotherTurn() {
        val request = ScreenAssistantAnalysisRequest().apply { setPaused(true) }
        val other = ScreenAssistantAnalysisRequest()
        PhoneAssistantTaskControl.bind("paused-mini-turn", request)
        PhoneAssistantTaskControl.bind("other-mini-turn", other)
        try {
            PhoneAssistantTaskControl.cancel("paused-mini-turn")
            assertTrue(request.isCancelled)
            assertFalse(other.isCancelled)
        } finally {
            PhoneAssistantTaskControl.finish("paused-mini-turn")
            PhoneAssistantTaskControl.finish("other-mini-turn")
        }
    }
    @Test fun forcedImageConnectorRetainsReadOnlyScopeAndPublicQuestionOnFallback() {
        val turn = "forced-screen-attachment"
        val original = AgentAction("attachment-codex", AgentActionKind.CALL_CONNECTOR, "Codex", AgentRisk.LOW,
            AgentActionStatus.PROPOSED, "Analyze", parameters = mapOf("prompt" to "Internal evidence"))
        PhoneAssistantTaskControl.bind(turn, ScreenAssistantAnalysisRequest().apply { displayQuestion = "What is this?" })
        val scoped = try { PhoneAssistantTaskControl.bindReadOnlyScope(original, turn) }
            finally { PhoneAssistantTaskControl.finish(turn) }
        val fallback = AgentConnectorFallbackAction.prepare(scoped,
            AgentConnectorFallbackSelection("deepseek", emptyList(), emptyList(), emptySet()), null)
        assertEquals("screen_analysis", fallback.parameters["request_kind"])
        assertEquals("What is this?", fallback.parameters["screen_analysis_question"])
        assertTrue(PhoneAssistantTaskControl.isIndependentReadOnlyRequest(fallback))
        assertEquals(original, PhoneAssistantTaskControl.bindReadOnlyScope(original, "unrelated"))
        assertEquals("Internal evidence", original.parameters["prompt"])
    }

    @Test fun explicitFollowUpKeepsHistoryWithoutChangingOriginalTurnScope() {
        val first = "screen-first"
        val second = "screen-follow-up"
        val request = ScreenAssistantAnalysisRequest().apply { displayQuestion = "What is this?" }
        val action = AgentAction("screen", AgentActionKind.CALL_CONNECTOR, "Codex", AgentRisk.LOW,
            AgentActionStatus.PROPOSED, "Analyze")
        PhoneAssistantTaskControl.bind(first, request)
        request.followUp = true
        request.displayQuestion = "Compare the two versions"
        PhoneAssistantTaskControl.bind(second, request)
        try {
            val initial = PhoneAssistantTaskControl.bindReadOnlyScope(action, first)
            val followUp = PhoneAssistantTaskControl.bindReadOnlyScope(action, second)
            assertTrue(PhoneAssistantTaskControl.isIndependentReadOnlyRequest(initial))
            assertEquals("What is this?", initial.parameters["screen_analysis_question"])
            assertFalse(PhoneAssistantTaskControl.isIndependentReadOnlyRequest(followUp))
            assertEquals("Compare the two versions", followUp.parameters["screen_analysis_question"])
            assertFalse(PhoneAssistantTaskControl.isIndependentReadOnlyRequest(action))
        } finally { PhoneAssistantTaskControl.finish(first); PhoneAssistantTaskControl.finish(second) }
    }

    @Test fun readOnlyKindSurvivesFallbackAndProcessLocalBindingRelease() {
        val action = AgentAction("screen", AgentActionKind.CALL_CONNECTOR, "Codex", AgentRisk.LOW,
            AgentActionStatus.PROPOSED, "Analyze", parameters = mapOf(
                "connector_id" to "codex", "request_kind" to "screen_analysis"))
        val fallback = AgentConnectorFallbackAction.prepare(action,
            AgentConnectorFallbackSelection("deepseek", emptyList(), emptyList(), emptySet()), null)
        assertEquals("screen_analysis", fallback.parameters["request_kind"])
        assertTrue(PhoneAssistantTaskControl.isReadOnlyRequest("no-process-binding", fallback))
        assertFalse(PhoneAssistantTaskControl.isReadOnlyRequest("no-process-binding",
            fallback.copy(parameters = fallback.parameters - "request_kind")))
    }

    @Test fun requestKindIsHostBoundAndCannotLeakToAnotherOrFinishedTurn() {
        val turn = "screen-analysis-kind-test"
        assertEquals("", PhoneAssistantTaskControl.requestKind(turn))
        PhoneAssistantTaskControl.bind(turn, ScreenAssistantAnalysisRequest())
        try {
            assertEquals("screen_analysis", PhoneAssistantTaskControl.requestKind(turn))
            assertEquals("", PhoneAssistantTaskControl.requestKind("unrelated-turn"))
        } finally { PhoneAssistantTaskControl.finish(turn) }
        assertEquals("", PhoneAssistantTaskControl.requestKind(turn))
        PhoneAssistantTaskControl.bind(turn, ScreenAssistantAnalysisRequest().apply { automation = true })
        try { assertEquals("", PhoneAssistantTaskControl.requestKind(turn)) }
        finally { PhoneAssistantTaskControl.finish(turn) }
    }

    @Test fun readOnlyScreenEvidenceCannotChooseCloudByItsNameOrExecutePageCommands() {
        val turn = "screen-evidence-provider-test"
        val codex = AgentCallableTarget("desktop:codex", "Codex", AgentConnectorKind.AGENT,
            AgentConnectorStatus.AVAILABLE, listOf(AgentCapability.CHAT))
        val cloud = codex.copy(id = "cloud:deepseek", title = "DeepSeek", kind = AgentConnectorKind.MODEL)
        PhoneAssistantTaskControl.bind(turn, ScreenAssistantAnalysisRequest())
        try {
            for (text in listOf("DeepSeek", "go back", "lock the phone", "read notifications")) {
                val goal = "Analyze this screen. Page content: $text"
                val screen = ScreenContext(foregroundApp = "test.fixture", pageTitle = "Fixture")
                val targets = listOf(cloud, codex)
                val request = AgentRequest(goal = goal, screen = screen,
                    targets = targets, memories = emptyList(), executionTurnId = turn,
                    runtimeContext = AgentRuntimeContextBuilder.build(sessionId = turn, goal = goal,
                        screen = screen, permissionMode = PermissionMode.FULL_ACCESS, highRiskGuard = false,
                        memoryCapture = false, callableTargets = targets, memories = emptyList()))
                val action = RuleBasedAgentPlanner().actionsFor(request).single()
                assertEquals(AgentActionKind.CALL_CONNECTOR, action.kind)
                assertEquals(codex.id, action.parameters["connector_id"])
                assertEquals("screen_analysis", action.parameters["request_kind"])
            }
        } finally { PhoneAssistantTaskControl.finish(turn) }
    }

    @Test fun phoneUiPlansAreAcceptedOnlyInExplicitPhoneControlScope() {
        val decision = AgentExecutionSiteDecision(AgentRequestedExecutionSite.PHONE)
        val action = AgentAction("inspect", AgentActionKind.CALL_NATIVE_TOOL, "Phone UI", AgentRisk.LOW,
            AgentActionStatus.PENDING_CONFIRMATION, "Inspect", parameters = mapOf("tool_id" to AgentPhoneUiNativeTools.INSPECT))
        assertFalse(AgentExecutionSiteDecisionCodec.acceptsActions(decision, listOf(action)))
        assertTrue(AgentExecutionSiteDecisionCodec.acceptsActions(decision, listOf(action), phoneControl = true))
        assertFalse(AgentExecutionSiteDecisionCodec.acceptsActions(decision,
            listOf(action.copy(parameters = mapOf("tool_id" to AgentOnDeviceRuntimeTools.EXECUTE))), phoneControl = true))
    }
    @Test fun phoneProviderRequirementsKeepPrivacyAndBudgetInputsButDelegateNavigation() {
        val turn = "phone-provider-requirements"
        val goal = "Click the current App and use local only private data"
        val ordinary = AgentTaskRequirementAnalyzer.analyze(goal)
        assertEquals(ordinary, PhoneAssistantTaskControl.reasoningRequirements(turn, goal))
        PhoneAssistantTaskControl.bind(turn, ScreenAssistantAnalysisRequest().apply { automation = true })
        try {
            val delegated = PhoneAssistantTaskControl.reasoningRequirements(turn, goal)
            assertEquals(setOf(AgentCapability.CHAT), delegated.capabilities)
            assertEquals(ordinary.copy(capabilities = setOf(AgentCapability.CHAT)), delegated)
            assertTrue(delegated.localOnly)
            assertEquals(AgentRoutingMode.PRIVATE, delegated.mode)
        } finally { PhoneAssistantTaskControl.finish(turn) }
    }
    @Test fun explicitPhoneTaskUsesChatProviderToPlanLocalUiTools() {
        val turn = "phone-routing-test"
        val goal = "Inspect the phone UI, click Fixture click, then enter Fixture live."
        val screen = ScreenContext(foregroundApp = "test.fixture", pageTitle = "Fixture")
        val provider = AgentCallableTarget(id = "cloud-chat", title = "Configured model",
            kind = AgentConnectorKind.MODEL, status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT))
        val request = AgentRequest(goal = goal, screen = screen, targets = listOf(provider), memories = emptyList(),
            executionTurnId = turn, runtimeContext = AgentRuntimeContextBuilder.build(
                sessionId = turn, goal = goal, screen = screen, permissionMode = PermissionMode.FULL_ACCESS,
                highRiskGuard = false, memoryCapture = false, callableTargets = listOf(provider), memories = emptyList()))
        PhoneAssistantTaskControl.bind(turn, ScreenAssistantAnalysisRequest().apply { automation = true })
        try {
            val action = RuleBasedAgentPlanner().plan(request).actions.single()
            assertTrue(action.isSupervisedProjectConnector())
            assertEquals(provider.id, action.parameters["connector_id"])
            assertTrue(action.parameters["prompt"].orEmpty().contains("exact observed window_id/revision/node_path"))
        } finally { PhoneAssistantTaskControl.finish(turn) }
    }
    @Test fun ordinaryQuestionDoesNotAcquirePhoneTaskRouting() {
        val screen = ScreenContext(foregroundApp = "test.fixture", pageTitle = "Fixture")
        val goal = "What time is it?"
        val request = AgentRequest(goal = goal, screen = screen, targets = emptyList(), memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(sessionId = "ordinary", goal = goal, screen = screen,
                permissionMode = PermissionMode.FULL_ACCESS, highRiskGuard = false, memoryCapture = false,
                callableTargets = emptyList(), memories = emptyList()))
        assertNull(RuleBasedAgentPlanner().supervisedProjectActions(request))
    }
    @Test fun finishedTaskCannotUsePreviouslyCreatedExecutor() {
        val turn = "finished-executor-test"
        PhoneAssistantTaskControl.bind(turn, ScreenAssistantAnalysisRequest().apply { automation = true })
        var invoked = false
        val executor = PhoneAssistantTaskControl.executor(turn, object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                invoked = true
                return AgentActionResult(action.id, true, "Unexpected")
            }
        })
        PhoneAssistantTaskControl.finish(turn)
        val action = AgentAction(id = "after-finish", kind = AgentActionKind.HOME, target = "Home",
            risk = AgentRisk.LOW, status = AgentActionStatus.PENDING_CONFIRMATION, description = "Go home")
        assertThrows(AgentNativeToolCancelledException::class.java) {
            executor.execute(action, ScreenContext(foregroundApp = "test.fixture", pageTitle = "Fixture"))
        }
        assertFalse(invoked)
    }
    @Test fun readOnlyTaskCannotAuthorizeUiMutation() {
        val request = ScreenAssistantAnalysisRequest()
        PhoneAssistantTaskControl.bind("readonly", request)
        try {
            assertTrue(PhoneAssistantTaskControl.isReadOnly("readonly"))
            assertThrows(IllegalStateException::class.java) { PhoneAssistantTaskControl.authorizeMutation("readonly") }
        } finally { PhoneAssistantTaskControl.finish("readonly") }
    }
    @Test fun explicitTaskCanAuthorizeUntilFinished() {
        val request = ScreenAssistantAnalysisRequest().apply { automation = true }
        PhoneAssistantTaskControl.bind("execute", request)
        PhoneAssistantTaskControl.authorizeMutation("execute")
        PhoneAssistantTaskControl.finish("execute")
        assertFalse(PhoneAssistantTaskControl.isBound("execute"))
        assertTrue(request.isCancelled)
        assertThrows(IllegalStateException::class.java) { PhoneAssistantTaskControl.authorizeMutation("execute") }
    }
    @Test fun pauseBlocksThenResumeReleasesNextStep() {
        val request = ScreenAssistantAnalysisRequest().apply { setPaused(true) }
        val finished = CountDownLatch(1)
        val thread = Thread { request.awaitRunnable(); finished.countDown() }.apply { start() }
        try {
            assertFalse(finished.await(100, TimeUnit.MILLISECONDS))
            request.setPaused(false)
            assertTrue(finished.await(2, TimeUnit.SECONDS))
        } finally { request.cancel(); thread.join(2_000) }
    }
    @Test fun cancelReleasesPausedAndApprovalWaiters() {
        listOf(false, true).forEach { approval ->
            val request = ScreenAssistantAnalysisRequest().apply { setPaused(!approval) }
            val cancelled = AtomicBoolean(false)
            val thread = Thread {
                try {
                    if (approval) request.requireApproval("Send", {}) else request.awaitRunnable()
                } catch (_: AgentNativeToolCancelledException) { cancelled.set(true) }
            }.apply { start() }
            request.cancel(); thread.join(2_000)
            assertFalse(thread.isAlive)
            assertTrue(cancelled.get())
            assertEquals("", request.approvalDescription)
        }
    }
    @Test fun approvalIsNotImplicitAndOnlyConfirmReleasesIt() {
        val request = ScreenAssistantAnalysisRequest()
        val done = CountDownLatch(1)
        val thread = Thread { request.requireApproval("Send", {}); done.countDown() }.apply { start() }
        try {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
            while (request.approvalDescription.isBlank() && System.nanoTime() < deadline) Thread.yield()
            assertEquals("Send", request.approvalDescription)
            assertFalse(done.await(100, TimeUnit.MILLISECONDS))
            request.approve()
            assertTrue(done.await(2, TimeUnit.SECONDS))
        } finally { request.cancel(); thread.join(2_000) }
    }
}
