package com.galaxyssi.chat

import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real MainActivity views, with isolated conversations and no paid model requests. */
@RunWith(AndroidJUnit4::class)
class ScreenAssistantChatDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun usesTheActualMainComposerAndTranscriptAdapter() = withChat { scenario, _ ->
        scenario.onActivity { activity ->
            assertTrue(activity is MainActivity)
            assertSame(activity.agentGoalInput, activity.findViewById(R.id.agentGoalInput))
            assertSame(activity.agentSubmitButton, activity.findViewById(R.id.agentSubmitButton))
            assertSame(activity.agentAttachButton, activity.findViewById(R.id.agentAttachButton))
            val list = activity.findViewById<RecyclerView>(R.id.agentOutputList)
            assertSame(activity.agentTranscriptAdapter, list.adapter)
            assertTrue(list.adapter is AgentTranscriptRecyclerAdapter)
            assertEquals(View.GONE, activity.findViewById<View>(R.id.agentFixedHeader).visibility)
            val title = Rect()
            val model = Rect()
            assertTrue(activity.findViewById<View>(R.id.agentSessionTitleTap).getGlobalVisibleRect(title))
            assertTrue(activity.findViewById<View>(R.id.agentModelSelectionTap).getGlobalVisibleRect(model))
            assertFalse("Session and model touch targets overlap", Rect.intersects(title, model))
        }
    }

    @Test fun emptyComposerDoesNotStartAnalysisAndRemainsNonModal() = withChat { scenario, id ->
        scenario.onActivity { activity ->
            assertTrue(activity.pendingAgentReplyIndicators.isEmpty())
            assertTrue(activity.agentInputAttachments.isEmpty())
            assertTrue(activity.agentGoalInput.text.isNullOrBlank())
            assertEquals(View.GONE, activity.findViewById<View>(R.id.agentOutputViewport).visibility)
            val attrs = activity.window.attributes
            assertEquals(Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL, attrs.gravity)
            assertTrue(attrs.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL != 0)
            assertEquals(0, attrs.flags and WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            assertEquals(WindowInsets.Type.systemBars() or WindowInsets.Type.ime(), attrs.fitInsetsTypes)
            assertFalse(attrs.isFitInsetsIgnoringVisibility)
            assertEquals(id, activity.agentTranscriptStore.activeConversation().id)
        }
    }

    @Test fun typingUsesTheExistingSendAndMoreActions() = withChat { scenario, _ ->
        scenario.onActivity { activity ->
            activity.agentGoalInput.setText("\u8bf7\u603b\u7ed3\u5f53\u524d\u9875\u9762")
            assertEquals(View.VISIBLE, activity.agentSubmitButton.visibility)
            activity.setAgentActionTrayExpanded(true)
            assertFalse(activity.agentActionTrayExpanded)
            activity.agentGoalInput.setText("")
            activity.setAgentActionTrayExpanded(true)
            listOf(R.id.agentActionNewSession, R.id.agentActionSessions, R.id.agentActionScan,
                R.id.agentActionCamera, R.id.agentActionAddFile).forEach {
                assertNotNull(activity.findViewById<View>(it))
            }
            assertTrue(activity.agentActionTrayExpanded)
            activity.setAgentActionTrayExpanded(false)
        }
    }

    @Test fun keyboardDoesNotCoverTheRealSendControl() = withChat { scenario, _ ->
        scenario.onActivity {
            it.agentGoalInput.setText("\u8bf7\u603b\u7ed3\u5f53\u524d\u9875\u9762")
            it.enterAgentComposerTextMode()
        }
        SystemClock.sleep(800)
        scenario.onActivity { activity ->
            val send = Rect()
            assertTrue(activity.agentSubmitButton.getGlobalVisibleRect(send))
            assertEquals(activity.agentSubmitButton.height, send.height())
            assertTrue(activity.window.decorView.systemUiVisibility and View.SYSTEM_UI_FLAG_HIDE_NAVIGATION == 0)
            activity.exitAgentComposerTextMode(hideKeyboard = true)
        }
    }

    @Test fun expandedTranscriptKeepsComposerAboveRealKeyboard() = verifyTranscriptKeyboard(expanded = true)

    @Test fun compactTranscriptKeepsComposerAboveRealKeyboard() = verifyTranscriptKeyboard(expanded = false)

    private fun verifyTranscriptKeyboard(expanded: Boolean) = withChat { scenario, id ->
        val draft = "Keyboard layout fixture\nSecond line"
        scenario.onActivity {
            it.toggleExpanded()
            if (!expanded) it.toggleExpanded()
            it.agentGoalInput.setText(draft)
        }
        instrumentation.waitForIdleSync()
        var originalHeight = 0
        scenario.onActivity { originalHeight = it.window.attributes.height }
        repeat(2) {
            scenario.onActivity { it.enterAgentComposerTextMode() }
            awaitKeyboard(scenario, true)
            scenario.onActivity { activity ->
                val metrics = activity.windowManager.currentWindowMetrics
                val imeTop = metrics.bounds.bottom - metrics.windowInsets.getInsets(WindowInsets.Type.ime()).bottom
                val windowPosition = IntArray(2)
                activity.window.decorView.getLocationOnScreen(windowPosition)
                assertEquals("Background leaks between composer and keyboard", imeTop,
                    windowPosition[1] + activity.window.decorView.height)
                assertEquals(0, activity.window.attributes.y)
                listOf(activity.agentGoalInput, activity.agentSubmitButton).forEach { view ->
                    val rect = Rect()
                    assertTrue("Composer control is not visible", view.getGlobalVisibleRect(rect))
                    assertEquals("Composer control is clipped", view.height, rect.height())
                    val location = IntArray(2)
                    view.getLocationOnScreen(location)
                    assertTrue("Composer control is behind IME", location[1] + view.height <= imeTop)
                }
                assertEquals(draft, activity.agentGoalInput.text.toString())
                assertEquals(id, activity.agentTranscriptStore.activeConversation().id)
            }
            val screenshot = instrumentation.uiAutomation.takeScreenshot()
            if (screenshot != null) {
                val file = java.io.File(instrumentation.targetContext.getExternalFilesDir(null),
                    "floating-keyboard-${if (expanded) "expanded" else "compact"}.png")
                file.outputStream().use { screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                screenshot.recycle()
            }
            scenario.onActivity { it.exitAgentComposerTextMode(hideKeyboard = true) }
            awaitKeyboard(scenario, false)
            scenario.onActivity {
                assertEquals("Window height did not restore", originalHeight, it.window.attributes.height)
                assertEquals("Floating bottom margin did not restore", it.dp(8), it.window.attributes.y)
            }
        }
    }

    private fun awaitKeyboard(scenario: ActivityScenario<ScreenAssistantChatActivity>, visible: Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 10_000
        var matched = false
        while (!matched && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity {
                matched = it.window.decorView.rootWindowInsets?.isVisible(WindowInsets.Type.ime()) == visible
            }
            SystemClock.sleep(100)
        }
        assertTrue("Keyboard visibility did not become $visible", matched)
        SystemClock.sleep(500)
        instrumentation.waitForIdleSync()
    }

    @Test fun floatingWindowDoesNotBecomeTheHomeRoutingSource() = withChat { scenario, _ ->
        scenario.onActivity { activity ->
            assertNotSame(activity, AgentConversationWindows.screenAssistantRunner(allowInitializing = true))
        }
    }

    @Test fun readsAndCapturesTheCompleteUnderlyingWindowNotTheMiniChat() {
        instrumentation.context.startActivity(Intent().setClassName(instrumentation.context.packageName,
            PhoneUiFixtureActivity::class.java.name).putExtra("page_capture", true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        SystemClock.sleep(500)
        withChat { scenario, _ ->
            scenario.onActivity { it.toggleExpanded() }
            val snapshot = requireNotNull(GalaxySSIAccessibilityService.readTargetUi())
            assertEquals(instrumentation.context.packageName, snapshot.packageName)
            assertTrue(snapshot.nodes.any { it.text == "Fixture idle" })
            assertFalse(snapshot.nodes.any { it.text.contains("Floating Agent UI fixture") })
            val file = PhoneUiScreenshot.capture(instrumentation.targetContext, snapshot.windowId)
            try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.path, bounds)
                assertTrue(bounds.outHeight > bounds.outWidth)
                assertTrue(bounds.outHeight > instrumentation.targetContext.resources.displayMetrics.heightPixels * 0.8f)
            } finally { file.delete() }
        }
    }

    @Test fun resizePreservesDraftConversationAndTheSameRenderer() = withChat { scenario, id ->
        scenario.onActivity { activity ->
            val adapter = activity.agentTranscriptAdapter
            activity.agentGoalInput.setText("\u4fdd\u7559\u8fd9\u4e2a\u8349\u7a3f\n\u7b2c\u4e8c\u6bb5")
            val compactHeight = activity.window.attributes.height
            activity.toggleExpanded()
            assertTrue(activity.window.attributes.height > compactHeight)
            activity.toggleExpanded()
            assertSame(adapter, activity.agentTranscriptAdapter)
            assertEquals(id, activity.agentTranscriptStore.activeConversation().id)
            assertEquals("\u4fdd\u7559\u8fd9\u4e2a\u8349\u7a3f\n\u7b2c\u4e8c\u6bb5", activity.agentGoalInput.text.toString())
        }
    }

    @Test fun recreationRestoresTheNormalWindowDraft() = withChat { scenario, id ->
        scenario.onActivity { activity ->
            activity.agentGoalInput.setText("\u91cd\u5efa\u540e\u4fdd\u7559\u8349\u7a3f")
            activity.conversationWindow.save()
        }
        scenario.recreate()
        awaitReady(scenario)
        scenario.onActivity { activity ->
            assertEquals(id, activity.agentTranscriptStore.activeConversation().id)
            assertEquals("\u91cd\u5efa\u540e\u4fdd\u7559\u8349\u7a3f", activity.agentGoalInput.text.toString())
        }
    }

    @Test fun receivesRichOutputThroughTheSharedTranscript() = withChat { scenario, id ->
        val store = AgentTranscriptStore(instrumentation.targetContext, ScreenAssistantChatActivity.WINDOW_KEY)
        val rich = AgentRichContentCodec.encode(listOf(AgentRichBlock("fixture-table", AgentRichBlockType.TABLE,
            columns = listOf("Item", "Status"), rows = listOf(listOf("Shared renderer", "OK")))))
        store.append(AgentTranscriptRole.ASSISTANT, "**Result**\n[Source](https://example.com/)",
            conversationId = id, turnId = "fixture-rich", taskId = "fixture-rich", richOutputJson = rich)
        scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
        val deadline = SystemClock.elapsedRealtime() + 10_000
        var rendered = false
        var diagnostic = ""
        while (!rendered && SystemClock.elapsedRealtime() < deadline) {
            SystemClock.sleep(100)
            scenario.onActivity {
                rendered = it.agentTranscriptAdapter.itemCount > 0 &&
                    it.findViewById<View>(R.id.agentOutputViewport).visibility == View.VISIBLE
                diagnostic = "adapter=${it.agentTranscriptAdapter.itemCount} window=${it.agentTranscriptWindow.entries.size}" +
                    " viewport=${it.findViewById<View>(R.id.agentOutputViewport).visibility} cleared=${it.runtimePlaintextCleared}"
            }
        }
        assertTrue("Shared transcript did not render: $diagnostic", rendered)
    }

    @Test fun collapseSavesDraftWithoutCancellingAnAuthorizedRequest() = withChat { scenario, id ->
        val turn = "fixture-collapse-$id"
        val request = ScreenAssistantAnalysisRequest().apply { turnId = turn; automation = true }
        PhoneAssistantTaskControl.bind(turn, request)
        try {
            scenario.onActivity {
                it.agentGoalInput.setText("\u6536\u8d77\u4fdd\u7559")
                it.collapse()
            }
            assertFalse(request.isCancelled)
            assertEquals("\u6536\u8d77\u4fdd\u7559", AgentWindowStateStore(instrumentation.targetContext)
                .load(ScreenAssistantChatActivity.WINDOW_KEY, id).text)
        } finally { PhoneAssistantTaskControl.finish(turn) }
    }

    private fun withChat(test: (ActivityScenario<ScreenAssistantChatActivity>, String) -> Unit) {
        val context = instrumentation.targetContext
        val settings = context.getSharedPreferences("screen_assistant_v1", 0)
        val previous = settings.getString("conversation", "").orEmpty()
        val states = AgentWindowStateStore(context)
        val previousSelected = states.selected(ScreenAssistantChatActivity.WINDOW_KEY)
        val store = AgentTranscriptStore(context, ScreenAssistantChatActivity.WINDOW_KEY)
        val id = store.createAgentConversation("Floating Agent UI fixture").id
        states.select(ScreenAssistantChatActivity.WINDOW_KEY, id)
        val intent = Intent(context, ScreenAssistantChatActivity::class.java)
            .putExtra(AgentConversationWindows.WINDOW_KEY, ScreenAssistantChatActivity.WINDOW_KEY)
            .putExtra(AgentConversationWindows.CONVERSATION, id)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        try {
            ActivityScenario.launch<ScreenAssistantChatActivity>(intent).use { scenario ->
                awaitReady(scenario)
                test(scenario, id)
            }
        } finally {
            states.select(ScreenAssistantChatActivity.WINDOW_KEY, previousSelected)
            settings.edit().putString("conversation", previous).commit()
            store.deleteConversation(id)
        }
    }

    private fun awaitReady(scenario: ActivityScenario<ScreenAssistantChatActivity>) {
        val deadline = SystemClock.elapsedRealtime() + 30_000
        var ready = false
        while (!ready && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { ready = !it.initialAgentHydrationPending }
            SystemClock.sleep(100)
        }
        assertTrue("Agent page hydration did not finish", ready)
        instrumentation.waitForIdleSync()
        SystemClock.sleep(300)
    }
}
