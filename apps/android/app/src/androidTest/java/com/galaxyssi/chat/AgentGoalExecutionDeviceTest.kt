package com.galaxyssi.chat

import android.content.ContextWrapper
import android.content.Intent
import android.os.SystemClock
import android.graphics.Bitmap
import android.graphics.pdf.PdfDocument
import java.io.File
import java.security.MessageDigest
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentGoalExecutionDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun scope() = "goal-execution-fixture-${UUID.randomUUID()}"
    private fun clean(id: String) = AgentRunEventStore(context).removeRuns(setOf("device-operation:" + AgentNativeJsonCodec.sha256(id)))
    private fun action(id: String, seconds: Int?, operation: String = "start") = AgentDeviceIntent.action(seconds, operation)
        .copy(id = UUID.randomUUID().toString(), parameters = AgentDeviceIntent.action(seconds, operation).parameters +
            mapOf(INTERNAL_CONVERSATION_ID to id))

    @Test fun modelPermissionGateSurvivesReloadAndContinuesOriginalActionOnce() {
        val id = scope()
        var granted = false
        var calls = 0
        val permission = "android.permission.CAMERA"
        val guarded = object : ContextWrapper(context) {
            override fun getApplicationContext() = this
            override fun checkSelfPermission(value: String) = if (value == permission && !granted)
                android.content.pm.PackageManager.PERMISSION_DENIED else android.content.pm.PackageManager.PERMISSION_GRANTED
        }
        val sessions = SharedPreferencesAgentSessionStore(context, id)
        val screen = ScreenContext("Permission fixture", pageTitle = "No actual camera or network access")
        val taskRows = mutableMapOf<String, AgentTaskRecord>()
        val tasks = object : AgentTaskStore {
            override fun upsert(record: AgentTaskRecord) { taskRows[record.taskId] = record }
            override fun recent(limit: Int) = taskRows.values.take(limit)
            override fun forSession(sessionId: String, limit: Int) = taskRows.values.filter { it.sessionId == sessionId }.take(limit)
            override fun find(taskId: String) = taskRows[taskId]
            override fun search(query: String, limit: Int) = emptyList<AgentTaskRecord>()
            override fun rebindSession(sourceSessionId: String, targetSessionId: String) = 0
            override fun delete(taskIds: Set<String>) { taskIds.forEach(taskRows::remove) }
            override fun clear() { taskRows.clear() }
        }
        val settings = object : AgentSafetySettingsStore {
            private var value = AgentSafetySettings(memoryCapture = false, screenObservationAllowed = false)
            override fun load() = value
            override fun save(settings: AgentSafetySettings) { value = settings }
        }
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(AgentNativeToolDescriptor(
            "fixture.permission", "1.0.0", "Permission fixture", "Synthetic counter only", AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW,
            requiredPermissions = listOf(AgentNativePermissionRequirement(permission, "Fixture"))), AgentNativeToolExecutor {
                calls++
                AgentNativeToolExecutionResult.success(mapOf("fixture" to true))
            }))
        fun runtime() = MobileNativeAgent(guarded, sessionStore = sessions, taskStore = tasks,
            safetySettingsStore = settings, memoryStore = InMemoryAgentMemoryStore(), nativeToolRegistryProvider = { registry },
            connectorRegistry = object : AgentConnectorRegistry { override fun availableTargets() = emptyList<AgentCallableTarget>() },
            perceptionProvider = object : ScreenPerceptionProvider {
                override fun capture() = screen
                override fun capture(foregroundApp: String, pageTitle: String) = screen
            })
        try {
            val action = AgentAction("action-$id", AgentActionKind.CALL_NATIVE_TOOL, "Fixture", AgentRisk.LOW,
                AgentActionStatus.PROPOSED, "Synthetic permission test", mapOf("tool_id" to "fixture.permission", "input_json" to "{}",
                    INTERNAL_CONVERSATION_ID to id, INTERNAL_TURN_ID to id))
            val first = runtime().also {
                it.sessionId = id
                it.currentGoal = "Synthetic permission test"
                it.currentScreen = screen
                it.currentPlan = AgentPlan(it.currentGoal, screen, emptyList(), listOf(action))
                it.activeConversationContext = AgentConversationContext(id, "", emptyList(), true)
                it.activeConversationTurnId = id
                it.phase = AgentPhase.PLANNING
                it.executionLoop.start(id, AgentExecutionLoopBudget())
            }
            val blocked = first.reconcileExecutionLoop(first.executeFirstPendingAction())
            assertEquals(AgentPhase.BLOCKED, blocked.phase)
            assertEquals(0, calls)
            val pending = requireNotNull(AgentRuntimePermissionContinuation.parse(blocked.lastActionResult))
            val restored = runtime()
            assertEquals(pending, AgentRuntimePermissionContinuation.parse(restored.snapshot().lastActionResult))
            restored.continueAfterAndroidPermission(pending)
            assertEquals(0, calls)
            granted = true
            restored.continueAfterAndroidPermission(pending.copy(turnId = "wrong-turn"))
            assertEquals(0, calls)
            val completed = restored.continueAfterAndroidPermission(pending)
            assertEquals(completed.toString(), AgentPhase.COMPLETED, completed.phase)
            assertEquals(1, calls)
            restored.continueAfterAndroidPermission(pending)
            assertEquals(1, calls)
        } finally { sessions.clear() }
    }

    @Test fun exportedPdfAndImageMustActuallyOpenAndMatchTheirHashes() {
        val directory = File(context.cacheDir, scope()).apply { mkdirs() }
        val inspector = AgentArtifactOpenability(context)
        fun inspect(file: File) = inspector.inspect(file, MessageDigest.getInstance("SHA-256")
            .digest(file.readBytes()).joinToString("") { "%02x".format(it) })
        try {
            val pdf = File(directory, "report.pdf")
            val document = PdfDocument()
            try {
                val page = document.startPage(PdfDocument.PageInfo.Builder(200, 200, 1).create())
                page.canvas.drawText("Goal evidence fixture", 10f, 30f, android.graphics.Paint())
                document.finishPage(page)
                pdf.outputStream().use(document::writeTo)
            } finally { document.close() }
            val pdfResult = inspect(pdf)
            assertEquals(pdfResult.toString(), "verified", pdfResult["status"])
            assertEquals("pdf_document_open", pdfResult["scope"])
            pdf.writeText("not a PDF")
            assertEquals("unverified", inspect(pdf)["status"])
            val image = File(directory, "preview.png")
            val bitmap = Bitmap.createBitmap(16, 16, Bitmap.Config.ARGB_8888)
            try { image.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) } }
            finally { bitmap.recycle() }
            val imageResult = inspect(image)
            assertEquals(imageResult.toString(), "verified", imageResult["status"])
            image.writeText("not an image")
            assertEquals("unverified", inspect(image)["status"])
        } finally { directory.deleteRecursively() }
    }

    @Test fun operationAndGenericContractSurviveReloadWithoutCrossConversationBinding() {
        val id = scope()
        try {
            val original = AgentDeviceOperationStore(context).save(AgentDeviceOperation(id, seconds = 60,
                dispatched = true, status = "waiting_accessibility"))
            assertEquals(original, AgentDeviceOperationStore(context).get(id))
            assertNull(AgentDeviceOperationStore(context).get("other-$id"))
            assertTrue(AgentDeviceOperationStore(context).claimContinuation(original))
            assertFalse(AgentDeviceOperationStore(context).claimContinuation(original))
            val requirements = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false,
                outcomes = listOf(AgentObservedOutcome("file", "galaxyssi.workspace.file.sha256",
                    mapOf("/path" to "result.txt"), mapOf("/algorithm" to "SHA-256"), "galaxyssi.workspace.file.write.text")))
            AgentDeviceOperationStore(context).recordPlan(id, "Create and verify a document", requirements)
            val restored = requireNotNull(AgentDeviceOperationStore(context).get(id))
            assertEquals("agent", restored.kind)
            assertEquals(requirements, AgentCompletionRequirements.parse(org.json.JSONObject(restored.completionJson)))
            assertTrue(restored.context().contains("Create and verify a document"))
        } finally { clean(id) }
    }

    @Test fun pendingOperationOffersAccessOnlyInItsConversationAndDoesNotRepeat() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_access_prompt") == "true")
        assumeTrue(!GalaxySSIAccessibilityService.isActive())
        instrumentation.runOnMainSync {
            context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        val ready = SystemClock.elapsedRealtime() + 30_000
        var foreground = false
        while (!foreground && SystemClock.elapsedRealtime() < ready) {
            instrumentation.runOnMainSync {
                foreground = AgentConversationWindows.screenAssistantRunner()?.let(AppForegroundTracker::isActivityForeground) == true
            }
            if (!foreground) SystemClock.sleep(100)
        }
        assertTrue("Keep GalaxySSI visible and the selected phone awake for UI acceptance", foreground)
        fun ui(block: (MainActivity) -> Unit) = instrumentation.runOnMainSync {
            block(requireNotNull(AgentConversationWindows.screenAssistantRunner()))
        }
        run {
            lateinit var transcript: AgentTranscriptStore
            var previous = ""
            var windowKey = ""
            ui { activity ->
                transcript = activity.agentTranscriptStore
                previous = transcript.activeConversation().id
                windowKey = activity.conversationWindow.key
                activity.showMainTab(PAGE_AGENT)
            }
            val conversation = transcript.createAgentConversation("Goal access fixture")
            transcript.append(AgentTranscriptRole.USER, "Access entry fixture; no action is executed.", conversationId = conversation.id)
            val pending = AgentDeviceOperationStore(context).save(AgentDeviceOperation(conversation.id,
                seconds = 60, status = "waiting_accessibility"))
            try {
                ui { activity ->
                    activity.offerPendingDeviceOperationAccess(conversation.id)
                    assertNull(activity.deviceOperationAccessDialog)
                }
                ui { activity ->
                    activity.openAgentConversation(conversation.id)
                    assertEquals(conversation.id, activity.agentTranscriptStore.activeConversation().id)
                    assertTrue(AppForegroundTracker.isActivityForeground(activity))
                    assertFalse(activity.runtimePlaintextCleared)
                    assertEquals(PAGE_AGENT, activity.activeMainTab)
                }
                val deadline = SystemClock.elapsedRealtime() + 10_000
                var shown = false
                while (!shown && SystemClock.elapsedRealtime() < deadline) {
                    ui { shown = it.deviceOperationAccessDialog?.isShowing == true }
                    if (!shown) SystemClock.sleep(50)
                }
                var diagnostic = ""
                ui { activity ->
                    diagnostic = "foreground=${AppForegroundTracker.isActivityForeground(activity)}, " +
                        "scopeMatches=${activity.agentTranscriptStore.activeConversation().id == conversation.id}, " +
                        "cleared=${activity.runtimePlaintextCleared}, tab=${activity.activeMainTab}, " +
                        "alreadyOffered=${pending.id in activity.offeredDeviceOperationAccessIds}"
                }
                assertTrue("Pending model operation should expose the same access entry: $diagnostic", shown)
                ui { activity ->
                    val dialog = activity.deviceOperationAccessDialog
                    activity.offerDeviceOperationAccess(AgentActionResult(pending.id, false, "", mapOf(
                        "required_capability" to "accessibility", "operation_id" to pending.id)), conversation.id)
                    assertSame(dialog, activity.deviceOperationAccessDialog)
                    dialog?.dismiss()
                    activity.offerPendingDeviceOperationAccess(conversation.id)
                }
                SystemClock.sleep(500)
                ui { assertNull(it.deviceOperationAccessDialog) }
                assertEquals("waiting_accessibility", AgentDeviceOperationStore(context).get(conversation.id)?.status)
                assertFalse(requireNotNull(AgentDeviceOperationStore(context).get(conversation.id)).dispatched)
            } finally {
                clean(conversation.id)
                if (transcript.activeConversation().id == conversation.id) transcript.switchConversation(previous)
                val windows = AgentWindowStateStore(context)
                if (windows.selected(windowKey) == conversation.id) windows.select(windowKey, previous)
                transcript.deleteConversation(conversation.id)
                runCatching { ui {
                    it.deviceOperationAccessDialog?.dismiss()
                    if (it.conversationWindow.conversationId == conversation.id) it.openAgentConversation(previous)
                } }
            }
        }
    }

    @Test fun removeOnlyAbandonedAccessTestFixtures() {
        val transcript = AgentTranscriptStore(context, "main")
        val operations = AgentDeviceOperationStore(context)
        val fixtures = transcript.conversations(includeArchived = true).filter { conversation ->
            conversation.createdByAgent && conversation.title == "Goal access fixture" &&
                transcript.list(conversation.id).all { it.text == "Access entry fixture; no action is executed." } &&
                operations.get(conversation.id)?.let { it.kind == "timer" && it.status == "waiting_accessibility" && !it.dispatched } == true
        }
        fixtures.forEach { clean(it.id); transcript.deleteConversation(it.id) }
        println("GOAL_ACCESS abandoned_fixtures_removed=${fixtures.size}")
    }

    @Test fun invalidParametersNeverLaunchClockOrMutatePriorGoal() {
        val id = scope()
        var launched = 0
        val guarded = object : ContextWrapper(context) {
            override fun startActivity(intent: Intent) { launched++ }
        }
        try {
            val executor = AndroidAgentActionExecutor(guarded)
            val invalid = action(id, 60).copy(parameters = action(id, 60).parameters + ("timer_seconds" to "oops"))
            assertFalse(executor.execute(invalid, ScreenContext(foregroundApp = "", pageTitle = "")).success)
            assertFalse(executor.execute(action(id, null, "replace"), ScreenContext(foregroundApp = "", pageTitle = "")).success)
            assertEquals(0, launched)
            assertNull(AgentDeviceOperationStore(context).get(id))
        } finally { clean(id) }
    }

    @Test fun unobservedDispatchDoesNotClaimCompletionOrRecreateTimer() {
        assumeTrue(!GalaxySSIAccessibilityService.isActive())
        val id = scope()
        var launches = 0
        val guarded = object : ContextWrapper(context) {
            override fun startActivity(intent: Intent) { launches++ }
        }
        try {
            val executor = AndroidAgentActionExecutor(guarded)
            val first = executor.execute(action(id, 60), ScreenContext(foregroundApp = "", pageTitle = ""))
            assertEquals("dispatched", first.metadata["goal_status"])
            assertEquals("false", first.metadata["business_success_verified"])
            val identity = AgentDeviceOperationStore(context).get(id)?.id
            val repeated = executor.execute(action(id, null), ScreenContext(foregroundApp = "", pageTitle = ""))
            assertEquals("dispatched", repeated.metadata["goal_status"])
            assertEquals(identity, AgentDeviceOperationStore(context).get(id)?.id)
            assertEquals(1, launches)
        } finally { clean(id) }
    }

    @Test fun realTimerStartRepeatChangePauseResumeCancel() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_timer") == "true")
        val ready = SystemClock.elapsedRealtime() + 15_000
        while (!GalaxySSIAccessibilityService.isActive() && SystemClock.elapsedRealtime() < ready) SystemClock.sleep(100)
        assertTrue("Enable GalaxySSI accessibility on the selected phone before this acceptance test", GalaxySSIAccessibilityService.isActive())
        val id = scope()
        val executor = AndroidAgentActionExecutor(context)
        fun perform(seconds: Int?, op: String): AgentActionResult = executor.execute(action(id, seconds, op), ScreenContext(foregroundApp = "", pageTitle = ""))
        try {
            val started = perform(AgentDeviceIntent.exactTimerSeconds("设置一分钟倒计时"), "start")
            assertEquals(started.toString(), "verified", started.metadata["goal_status"])
            val identity = requireNotNull(AgentDeviceOperationStore(context).get(id)).id
            val repeated = perform(null, "start")
            assertEquals(repeated.toString(), "verified", repeated.metadata["goal_status"])
            assertEquals(identity, AgentDeviceOperationStore(context).get(id)?.id)
            val changed = perform(AgentDeviceIntent.seconds("改成两分钟"), "replace")
            assertEquals(changed.toString(), "verified", changed.metadata["goal_status"])
            assertNotEquals(identity, AgentDeviceOperationStore(context).get(id)?.id)
            assertEquals(120, AgentDeviceOperationStore(context).get(id)?.seconds)
            for (op in listOf("pause", "resume", "cancel")) {
                val result = perform(null, op)
                println("GOAL_EXECUTION $op ${result.metadata}")
                assertEquals(result.toString(), "verified", result.metadata["goal_status"])
            }
            assertEquals("cancelled", AgentDeviceOperationStore(context).get(id)?.status)
        } finally {
            if (AgentDeviceOperationStore(context).get(id)?.status != "cancelled") perform(null, "cancel")
            if (AgentDeviceOperationStore(context).get(id)?.status == "cancelled") clean(id)
            else println("GOAL_EXECUTION cleanup_unverified checkpoint_retained=$id")
        }
    }

    @Test fun configuredModelRepairsTypoAsExecutablePhoneIntent() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_intent_model") == "true")
        instrumentation.startActivitySync(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val ready = SystemClock.elapsedRealtime() + 30_000
        while (AgentConversationWindows.screenAssistantRunner() == null && SystemClock.elapsedRealtime() < ready) SystemClock.sleep(100)
        val runner = requireNotNull(AgentConversationWindows.screenAssistantRunner())
        val transcript = runner.agentTranscriptStore
        val old = transcript.activeConversation().id
        val conversation = transcript.createAgentConversation("Goal execution typo acceptance")
        val turn = UUID.randomUUID().toString()
        try {
            transcript.append(AgentTranscriptRole.USER, "设置三分钟导计时", conversationId = conversation.id, turnId = turn, taskId = turn)
            instrumentation.runOnMainSync { runner.continueAgentGoalSubmission("设置三分钟导计时", conversation.id, turn) }
            val deadline = SystemClock.elapsedRealtime() + 180_000
            while (SystemClock.elapsedRealtime() < deadline) {
                val operation = AgentDeviceOperationStore(context).get(conversation.id)
                if (operation?.kind == "timer" && operation.status == "running") break
                SystemClock.sleep(250)
            }
            val operation = AgentDeviceOperationStore(context).get(conversation.id)
            assertEquals(operation.toString(), "timer", operation?.kind)
            assertEquals(operation.toString(), "running", operation?.status)
            assertEquals(180, operation?.seconds)
        } finally {
            ScreenAssistantTaskCancellation.cancel(context, conversation.id, turn, runner)
            AndroidAgentActionExecutor(context).execute(action(conversation.id, null, "cancel"), ScreenContext(foregroundApp = "", pageTitle = ""))
            val cancelled = AgentDeviceOperationStore(context).get(conversation.id)?.status == "cancelled"
            if (cancelled) {
                clean(conversation.id)
                val restore = transcript.activeConversation().id == conversation.id
                transcript.deleteConversation(conversation.id)
                if (restore) transcript.switchConversation(old)
            } else println("GOAL_EXECUTION cleanup_unverified conversation_retained=${conversation.id}")
        }
    }
}
