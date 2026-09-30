package com.galaxyssi.chat

import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Exercises the shared composer handoff without making paid model requests or touching real documents. */
@RunWith(AndroidJUnit4::class)
class ScreenAssistantContentDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun ordinaryConversationKeepsProductBrandInFloatingHeader() = withChat { scenario, id ->
        scenario.onActivity { activity ->
            val conversation = requireNotNull(activity.agentTranscriptStore.conversation(id))
            activity.refreshAgentConversationHeader(conversation.copy(title = "Summary", createdByAgent = false))
            assertTrue(activity.agentSessionTitle.text.toString().contains("GalaxySSI"))
            activity.refreshAgentConversationHeader(conversation.copy(title = "Summary", createdByAgent = true))
            assertEquals(1, Regex("GalaxySSI").findAll(activity.agentSessionTitle.text.toString()).count())
        }
    }

    @Test fun opaqueFixtureUsesRealReadingGesturesWithoutModelCalls() {
        instrumentation.getUiAutomation(android.app.UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
        val deadline = SystemClock.elapsedRealtime() + 20_000
        while (!GalaxySSIAccessibilityService.isActive() && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(100)
        assertTrue(GalaxySSIAccessibilityService.isActive())
        instrumentation.context.startActivity(Intent().setClassName(instrumentation.context.packageName,
            PhoneUiFixtureActivity::class.java.name).putExtra("page_capture", true).putExtra("opaque_page", true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        SystemClock.sleep(800)
        val target = requireNotNull(GalaxySSIAccessibilityService.readTargetUi())
        assertNull(ScreenAssistantPagePolicy.scrollNode(target))
        val request = ScreenAssistantAnalysisRequest()
        val session = ScreenAssistantPageCollection(request)
        assertTrue(ScreenAssistantContentCapture.acquire(target.packageName, session))
        withChat { _, _ ->
            var capture = ""
            try {
                capture = ScreenAssistantPageCollector(context).collect(session, renderHtml = false,
                    maxBytes = 16L * 1024 * 1024) { _, _ -> }
                val store = ScreenAssistantPageStore(context)
                val meta = store.manifest(capture)
                assertEquals(meta.toString(), "visual_scroll", meta.optString("capture_method"))
                assertTrue(meta.toString(), meta.optInt("pages") > 2)
                assertTrue(meta.toString(), meta.optBoolean("visual_traversal_finished"))
                assertFalse(meta.optBoolean("complete"))
                val text = File(store.directory(capture), "page.txt").readText()
                assertTrue(text, text.contains("row 1"))
                assertTrue(text, text.contains("row 80"))
            } finally {
                ScreenAssistantContentCapture.release(session)
                request.cancel()
                if (capture.isNotBlank()) ScreenAssistantPageStore(context).directory(capture).deleteRecursively()
            }
        }
    }

    @Test fun sourceMenuShowsAllFourChoicesAboveTheSharedComposer() {
        val automation = instrumentation.getUiAutomation(android.app.UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
        openLongFixture()
        withChat { scenario, _ ->
            scenario.onActivity {
                it.contentController.select(ScreenContentSource(ScreenContentKind.PAGE))
                it.findViewById<View>(R.id.screenAssistantChatCapture).performClick()
            }
            instrumentation.waitForIdleSync()
            SystemClock.sleep(300)
            val labels = mutableListOf<String>()
            fun visit(node: android.view.accessibility.AccessibilityNodeInfo?) {
                if (node == null) return
                node.text?.toString()?.let(labels::add)
                repeat(node.childCount) { visit(node.getChild(it)) }
            }
            visit(automation.rootInActiveWindow)
            listOf(R.string.screen_content_screen, R.string.screen_content_page,
                R.string.screen_content_file, R.string.screen_content_link).forEach {
                assertTrue("Missing menu item: ${context.getString(it)} in $labels", context.getString(it) in labels)
            }
            automation.takeScreenshot()?.let { bitmap ->
                try {
                    File(context.getExternalFilesDir(null), "content-analysis-source-menu.png").outputStream().use {
                        bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                    }
                } finally { bitmap.recycle() }
            }
            instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        }
    }

    @Test fun livePageCollectionHandsTheFirstAndLastRowsToTheSharedPipeline() {
        instrumentation.getUiAutomation(android.app.UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
        val serviceDeadline = SystemClock.elapsedRealtime() + 20_000
        while (!GalaxySSIAccessibilityService.isActive() && SystemClock.elapsedRealtime() < serviceDeadline) SystemClock.sleep(100)
        assertTrue("Screen access is not active", GalaxySSIAccessibilityService.isActive())
        openLongFixture()
        withChat { scenario, id ->
            val request = ScreenAssistantAnalysisRequest()
            val complete = CountDownLatch(1)
            val result = AtomicReference<List<AgentInputAttachment>>()
            val turn = "live-content-$id"
            try {
                scenario.onActivity {
                    it.contentController.select(ScreenContentSource(ScreenContentKind.PAGE))
                    it.contentController.onSubmitted(id, turn, request, false)
                    it.prepareAgentTurnContent(id, turn, "Summarize the fixture", emptyList()) { _, files, _ ->
                        result.set(files)
                        complete.countDown()
                    }
                }
                assertTrue("Collection did not reach the shared pipeline", complete.await(90, TimeUnit.SECONDS))
                val store = ScreenAssistantPageStore(context)
                val meta = store.manifest(request.pageCaptureId)
                val text = File(store.directory(request.pageCaptureId), "page.txt").readText()
                assertTrue(meta.toString(), meta.optBoolean("complete"))
                assertTrue(text.contains("Fixture row 1\n"))
                assertTrue(text.contains("Fixture row 80"))
                assertFalse(text.contains("test-secret-never-export"))
                assertEquals(2, result.get().size)
            } finally {
                request.cancel()
                AgentTurnAttachmentRegistry.remove(turn)
                request.pageCaptureId.takeIf(String::isNotBlank)?.let { capture ->
                    val dir = ScreenAssistantPageStore(context).directory(capture).canonicalFile
                    assertEquals(File(context.filesDir, "agent-rich-output-v2/screen-assistant/pages").canonicalFile, dir.parentFile)
                    dir.deleteRecursively()
                }
            }
        }
    }

    private fun openLongFixture() {
        instrumentation.context.startActivity(Intent().setClassName(instrumentation.context.packageName,
            PhoneUiFixtureActivity::class.java.name).putExtra("page_capture", true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        SystemClock.sleep(800)
    }

    @Test fun selectionSurvivesRecreationAndCanBeRemovedWithoutChangingTheDraft() = withChat { scenario, _ ->
        scenario.onActivity {
            it.agentGoalInput.setText("Summarize this document")
            it.contentController.select(ScreenContentSource(ScreenContentKind.PAGE))
            assertEquals(View.VISIBLE, it.findViewById<View>(R.id.screenContentSource).visibility)
        }
        scenario.recreate()
        ready(scenario)
        scenario.onActivity {
            assertEquals("Summarize this document", it.agentGoalInput.text.toString())
            assertEquals(View.VISIBLE, it.findViewById<View>(R.id.screenContentSource).visibility)
            it.findViewById<View>(R.id.screenContentRemove).performClick()
            assertEquals(View.GONE, it.findViewById<View>(R.id.screenContentSource).visibility)
            assertEquals("Summarize this document", it.agentGoalInput.text.toString())
            assertTrue(it.pendingAgentReplyIndicators.isEmpty())
        }
    }

    @Test fun linkUsesSameComposerPreservesQuestionAndHasTruthfulExpandableCoverage() = withChat { scenario, id ->
        scenario.onActivity {
            val request = ScreenAssistantAnalysisRequest()
            it.contentController.select(ScreenContentSource(ScreenContentKind.LINK, "https://example.org/report"))
            it.contentController.onSubmitted(id, "link-fixture", request, false)
            var called = false
            it.prepareAgentTurnContent(id, "link-fixture", "Summarize", emptyList()) { goal, attachments, cancelled ->
                called = true
                assertTrue(goal.startsWith("Summarize\n"))
                assertTrue(goal.contains("https://example.org/report"))
                assertTrue(attachments.isEmpty())
                assertFalse(cancelled())
                request.cancel()
                assertTrue(cancelled())
            }
            assertTrue(called)
            assertEquals(View.GONE, it.findViewById<View>(R.id.screenContentSource).visibility)
            val coverage = it.findViewById<LinearLayout>(R.id.screenContentCoverage)
            assertEquals(View.VISIBLE, coverage.visibility)
            coverage.getChildAt(0).performClick()
            assertEquals(View.VISIBLE, (coverage.getChildAt(1) as ScrollView).visibility)
        }
        scenario.recreate()
        ready(scenario)
        scenario.onActivity {
            assertEquals(View.VISIBLE, it.findViewById<View>(R.id.screenContentCoverage).visibility)
            val next = ScreenAssistantAnalysisRequest()
            it.contentController.onSubmitted(id, "follow-up", next, false)
            assertTrue(next.followUp)
            it.prepareAgentTurnContent(id, "follow-up", "Explain the caveats", emptyList()) { goal, _, _ ->
                assertTrue(goal.contains("https://example.org/report"))
            }
            it.contentController.select(null)
            it.contentController.onSubmitted(id, "source-removed", ScreenAssistantAnalysisRequest(), false)
            assertFalse(it.contentController.hasSource("source-removed"))
            it.prepareAgentTurnContent(id, "source-removed", "Hello", emptyList()) { goal, _, _ ->
                assertEquals("Hello", goal)
            }
        }
    }

    @Test fun ordinaryInputDoesNotAcquireContentOrRewriteTheGoal() = withChat { scenario, id ->
        scenario.onActivity {
            var called = false
            it.prepareAgentTurnContent(id, "normal", "Hello", emptyList()) { goal, attachments, cancelled ->
                called = true
                assertEquals("Hello", goal)
                assertTrue(attachments.isEmpty())
                assertFalse(cancelled())
            }
            assertTrue(called)
        }
    }

    @Test fun cancelledCollectionNeverInvokesTheModelAndFinishesTheWaitingState() = withChat { scenario, id ->
        val turn = "cancel-$id"
        scenario.onActivity {
            val request = ScreenAssistantAnalysisRequest().apply { cancel() }
            it.contentController.select(ScreenContentSource(ScreenContentKind.PAGE))
            it.contentController.onSubmitted(id, turn, request, false)
            it.pendingAgentReplyIndicators[turn] = PendingAgentReplyIndicator(id, turn, System.currentTimeMillis())
            it.prepareAgentTurnContent(id, turn, "Summarize", emptyList()) { _, _, _ -> fail("Cancelled capture submitted") }
        }
        val deadline = SystemClock.elapsedRealtime() + 10_000
        var finished = false
        while (!finished && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity {
                finished = !it.pendingAgentReplyIndicators.containsKey(turn) &&
                    it.agentTranscriptStore.entriesForTurn(turn).any { entry -> entry.role == AgentTranscriptRole.ASSISTANT }
            }
            SystemClock.sleep(100)
        }
        assertTrue("Cancelled capture left a waiting task", finished)
    }

    @Test fun savedDocumentHandoffIncludesPdfAndTextAndDoesNotRecaptureOnFollowup() = withChat { scenario, id ->
        val store = ScreenAssistantPageStore(context)
        val capture = store.create()
        try {
            store.checkpoint(capture, JSONObject().put("pages", 2).put("complete", false).put("reason", "user_finish"))
            repeat(2) { index ->
                File(store.directory(capture), "$index.json").writeText(JSONObject().put("text", "Fixture section $index").toString())
            }
            store.buildText(capture)
            val done = CountDownLatch(1)
            val output = AtomicReference<List<AgentInputAttachment>>()
            val request = ScreenAssistantAnalysisRequest()
            val turn = "document-$id"
            scenario.onActivity {
                it.contentController.select(ScreenContentSource(ScreenContentKind.PAGE, capture))
                it.contentController.onSubmitted(id, turn, request, false)
                it.prepareAgentTurnContent(id, turn, "Find the key point", emptyList()) { goal, attachments, _ ->
                    assertTrue(goal.startsWith("Find the key point\n"))
                    output.set(attachments)
                    done.countDown()
                }
            }
            assertTrue(done.await(20, TimeUnit.SECONDS))
            assertEquals(setOf("text/plain", "application/pdf"), output.get().map { it.mimeType }.toSet())
            assertEquals(capture, request.pageCaptureId)
            assertFalse(File(store.directory(capture), "page.html").exists())
            val followupDone = CountDownLatch(1)
            scenario.onActivity {
                val next = ScreenAssistantAnalysisRequest()
                it.contentController.onSubmitted(id, "next-$id", next, false)
                assertTrue(next.followUp)
                it.prepareAgentTurnContent(id, "next-$id", "And section 2?", emptyList()) { _, files, _ ->
                    assertEquals(capture, next.pageCaptureId)
                    assertEquals(2, files.size)
                    followupDone.countDown()
                }
            }
            assertTrue(followupDone.await(20, TimeUnit.SECONDS))
        } finally {
            AgentTurnAttachmentRegistry.remove("document-$id")
            AgentTurnAttachmentRegistry.remove("next-$id")
            val dir = store.directory(capture).canonicalFile
            assertEquals(File(context.filesDir, "agent-rich-output-v2/screen-assistant/pages").canonicalFile, dir.parentFile)
            dir.deleteRecursively()
        }
    }

    private fun withChat(test: (ActivityScenario<ScreenAssistantChatActivity>, String) -> Unit) {
        val settings = context.getSharedPreferences("screen_assistant_v1", 0)
        val previous = settings.getString("conversation", "").orEmpty()
        val previousCapture = ScreenAssistantSettings.lastPageCapture(context)
        val states = AgentWindowStateStore(context)
        val previousSelected = states.selected(ScreenAssistantChatActivity.WINDOW_KEY)
        val store = AgentTranscriptStore(context, ScreenAssistantChatActivity.WINDOW_KEY)
        val id = store.createAgentConversation("Content source fixture").id
        states.select(ScreenAssistantChatActivity.WINDOW_KEY, id)
        try {
            ActivityScenario.launch<ScreenAssistantChatActivity>(Intent(context, ScreenAssistantChatActivity::class.java)
                .putExtra(AgentConversationWindows.WINDOW_KEY, ScreenAssistantChatActivity.WINDOW_KEY)
                .putExtra(AgentConversationWindows.CONVERSATION, id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)).use {
                ready(it)
                test(it, id)
            }
        } finally {
            states.select(ScreenAssistantChatActivity.WINDOW_KEY, previousSelected)
            settings.edit().putString("conversation", previous).commit()
            ScreenAssistantSettings.saveLastPageCapture(context, previousCapture)
            context.getSharedPreferences("screen_assistant_content_v1", 0).edit()
                .remove("draft:$id").remove("coverage:$id").remove("context:$id").commit()
            store.deleteConversation(id)
        }
    }

    private fun ready(scenario: ActivityScenario<ScreenAssistantChatActivity>) {
        val deadline = SystemClock.elapsedRealtime() + 30_000
        var ready = false
        while (!ready && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { ready = !it.initialAgentHydrationPending }
            SystemClock.sleep(100)
        }
        assertTrue(ready)
        instrumentation.waitForIdleSync()
    }
}
