package com.galaxyssi.chat

import android.app.ActivityManager
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.view.View
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.delay
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentConversationWindowsInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val manager get() = context.getSystemService(ActivityManager::class.java)

    @Test fun brandHeaderSeparatesWindowAndConversationActions() {
        val key = "brand-header-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val seed = store.createConversation("Header actions", privateMode = true)
        store.append(AgentTranscriptRole.PROCESS, "Header action verification", conversationId = seed.id)
        val conversations = mutableSetOf(seed.id)
        val windows = mutableListOf<MainActivity>()
        val release = AtomicBoolean(false)
        var handle: AgentTaskHandle? = null
        var monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        try {
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$key"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, key)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            val root = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity
                ?: error("Header test window did not open")
            windows += root
            await("Header ready") { !root.initialAgentHydrationPending && root.conversationWindow.visible &&
                root.conversationWindow.conversationId == seed.id }
            instrumentation.removeMonitor(monitor)
            val taskId = root.taskId
            val running = AgentTaskRuntime.supervisor(context).submit(AgentWorkspace(
                workspaceId = key, sessionId = key, conversationId = seed.id, taskId = key, goal = "Header lifecycle test"
            )) { while (!release.get()) delay(100) }
            handle = running
            await("Background fixture started") { running.isActive }
            val brandText = root.findViewById<android.view.ViewGroup>(R.id.agentBrandNewConversation)
            val title = root.findViewById<View>(R.id.agentBrandTitle)
            val subtitle = descendants(brandText).filterIsInstance<android.widget.TextView>()
                .first { it.text.toString() == context.getString(R.string.agent_brand_subtitle) }
            instrumentation.runOnMainSync {
                assertTrue(root.agentBrandLogo.isClickable)
                assertTrue(brandText.isClickable)
                assertEquals(context.getString(R.string.conversation_window_open), root.agentBrandLogo.contentDescription)
                assertEquals(0, context.resources.getIdentifier("agentOpenWindowButton", "id", context.packageName))
                root.agentGoalInput.setText("Draft before title tap")
            }
            tapCenter(title)
            await("Title starts a new session") { root.agentTranscriptStore.activeConversation().id != seed.id }
            val second = root.agentTranscriptStore.activeConversation().id
            conversations += second
            instrumentation.runOnMainSync {
                assertEquals(taskId, root.taskId)
                assertEquals("", root.agentGoalInput.text.toString())
                assertTrue(running.isActive)
                assertEquals("Draft before title tap", AgentWindowStateStore(context).load(key, seed.id).text)
                root.agentTranscriptStore.append(AgentTranscriptRole.PROCESS, "Second session", conversationId = second)
                root.agentGoalInput.setText("Draft before subtitle tap")
            }
            tapCenter(subtitle)
            await("Subtitle starts a new session") { root.agentTranscriptStore.activeConversation().id != second }
            conversations += root.agentTranscriptStore.activeConversation().id
            instrumentation.runOnMainSync {
                assertEquals(taskId, root.taskId)
                assertTrue(running.isActive)
                assertEquals("Draft before subtitle tap", AgentWindowStateStore(context).load(key, second).text)
                root.openAgentConversation(seed.id)
                assertEquals("Draft before title tap", root.agentGoalInput.text.toString())
            }
            monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
            tapCenter(root.agentBrandLogo)
            val child = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity
                ?: error("Logo did not open a document window")
            windows += child
            await("Logo handoff ready") { !child.initialAgentHydrationPending && !root.conversationWindow.openingWindow }
            instrumentation.runOnMainSync {
                assertNotEquals(root.taskId, child.taskId)
                assertEquals(seed.id, child.agentTranscriptStore.activeConversation().id)
                assertEquals("Draft before title tap", child.agentGoalInput.text.toString())
                assertNotEquals(seed.id, root.agentTranscriptStore.activeConversation().id)
                conversations += root.agentTranscriptStore.activeConversation().id
                assertEquals("", root.agentGoalInput.text.toString())
                assertTrue(running.isActive)
            }
            capture("brand-header-actions.png")
        } finally {
            release.set(true)
            handle?.takeIf { it.isActive }?.cancel("Header test cleanup")
            handle?.let { await("Header fixture stopped") { !it.isActive } }
            instrumentation.runOnMainSync { windows.filterNot { it.isDestroyed }.forEach { it.finishAndRemoveTask() } }
            conversations.forEach(store::deleteConversation)
            if (handle != null) EncryptedAgentWorkspaceStore(context).delete(key)
            instrumentation.removeMonitor(monitor)
        }
    }

    private fun tapCenter(view: View) {
        val point = IntArray(2)
        instrumentation.runOnMainSync {
            view.getLocationOnScreen(point)
            point[0] += view.width / 2
            point[1] += view.height / 2
        }
        val down = SystemClock.uptimeMillis()
        for (action in listOf(android.view.MotionEvent.ACTION_DOWN, android.view.MotionEvent.ACTION_UP)) {
            val event = android.view.MotionEvent.obtain(down, SystemClock.uptimeMillis(), action,
                point[0].toFloat(), point[1].toFloat(), 0)
            try { instrumentation.sendPointerSync(event) } finally { event.recycle() }
        }
    }

    @Test fun recreatedDocumentUsesLastSelectionAndDraft() {
        val key = "window-recreate-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val a = store.createConversation("Original document", privateMode = true)
        store.append(AgentTranscriptRole.PROCESS, "A", conversationId = a.id)
        val b = store.createConversation("Selected later", privateMode = true)
        store.append(AgentTranscriptRole.PROCESS, "B", conversationId = b.id)
        var monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        var current: MainActivity? = null
        try {
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$key"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, key)
                .putExtra(AgentConversationWindows.CONVERSATION, a.id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            val original = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity
                ?: error("Original document did not open")
            current = original
            await("Original document ready") { !original.initialAgentHydrationPending && original.conversationWindow.conversationId.isNotBlank() }
            monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
            instrumentation.runOnMainSync {
                original.openAgentConversation(b.id)
                original.agentGoalInput.setText("Unsent draft after selection")
                original.conversationWindow.save()
                original.intent.putExtra(AgentConversationWindows.CONVERSATION, a.id)
                original.recreate()
            }
            val restored = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity
                ?: error("Document did not recreate")
            current = restored
            await("Restored document ready") { !restored.initialAgentHydrationPending && restored.conversationWindow.conversationId.isNotBlank() }
            instrumentation.runOnMainSync {
                assertEquals(b.id, restored.agentTranscriptStore.activeConversation().id)
                assertEquals("Unsent draft after selection", restored.agentGoalInput.text.toString())
            }
        } finally {
            instrumentation.runOnMainSync { current?.takeUnless { it.isDestroyed }?.finishAndRemoveTask() }
            store.deleteConversation(a.id)
            store.deleteConversation(b.id)
            instrumentation.removeMonitor(monitor)
        }
    }

    @Test fun liveAgentReplySurvivesWindowClosure() {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("run_live") == "true")
        val key = "window-live-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val conversation = store.createConversation("Window live verification", privateMode = true)
        store.append(AgentTranscriptRole.PROCESS, "Live window verification", conversationId = conversation.id)
        var monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        var activity: MainActivity? = null
        val marker = "WINDOW-OK-${UUID.randomUUID().toString().take(8)}"
        try {
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$key"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, key)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            val window = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity
                ?: error("Live verification window did not open")
            activity = window
            await("Live window ready") { !window.initialAgentHydrationPending && window.conversationWindow.conversationId.isNotBlank() }
            instrumentation.runOnMainSync {
                window.agentGoalInput.setText("Please reply with exactly $marker. Do not call tools.")
                window.agentSubmitButton.performClick()
            }
            await("Live task started") {
                AgentTaskRuntime.supervisor(context).activeWorkspaces().any { it.conversationId == conversation.id }
            }
            instrumentation.runOnMainSync { window.finishAndRemoveTask() }
            await("Live window destroyed") { window.isDestroyed }
            val deadline = SystemClock.elapsedRealtime() + 180_000
            fun durableReply() = store.list(conversation.id).any { it.role == AgentTranscriptRole.ASSISTANT && marker in it.text } ||
                AgentConnectorResponseStore.pending(context).any { it.conversationId == conversation.id && marker in it.content }
            while (SystemClock.elapsedRealtime() < deadline && !durableReply()) {
                SystemClock.sleep(1_000)
            }
            assertTrue("Live reply missing from durable inbox and transcript after close", durableReply())
            monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$key"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, key)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            val restored = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity
                ?: error("Live document did not reopen")
            activity = restored
            await("Live reply visible after reopen") {
                restored.agentTranscriptWindow.entries.any { it.role == AgentTranscriptRole.ASSISTANT && marker in it.text }
            }
            capture("live-reply-restored.png")
        } finally {
            instrumentation.runOnMainSync { activity?.takeUnless { it.isDestroyed }?.finishAndRemoveTask() }
            instrumentation.removeMonitor(monitor)
            // Leave the private live transcript available when diagnosing a failed transport.
        }
    }

    @Test fun windowSelectionsAndDraftsAreIndependentAndDurable() {
        val prefix = "window-test-${UUID.randomUUID()}"
        val first = AgentTranscriptStore(context, "$prefix-a")
        val second = AgentTranscriptStore(context, "$prefix-b")
        val a = first.createConversation("Window A", privateMode = true)
        val b = second.createConversation("Window B", privateMode = true)
        try {
            first.append(AgentTranscriptRole.PROCESS, "A", conversationId = a.id)
            second.append(AgentTranscriptRole.PROCESS, "B", conversationId = b.id)
            assertEquals(a.id, first.activeConversation().id)
            assertEquals(b.id, second.activeConversation().id)
            assertEquals(a.id, AgentTranscriptStore(context, "$prefix-a").activeConversation().id)
            val states = AgentWindowStateStore(context)
            states.save("$prefix-a", a.id, AgentWindowDraft("draft A", entryId = "entry-a", topOffset = -25, autoFollow = false))
            states.save("$prefix-b", a.id, AgentWindowDraft("draft B"))
            assertEquals("draft A", AgentWindowStateStore(context).load("$prefix-a", a.id).text)
            assertEquals(-25, states.load("$prefix-a", a.id).topOffset)
            assertFalse(states.load("$prefix-a", a.id).autoFollow)
            assertEquals("draft B", states.load("$prefix-b", a.id).text)
            assertTrue(second.renameConversation(a.id, "Renamed elsewhere"))
            assertEquals("Renamed elsewhere", first.activeConversation().title)
        } finally {
            first.deleteConversation(a.id)
            second.deleteConversation(b.id)
        }
    }

    @Test fun tenDocumentWindowsHandoffReuseAndBackgroundCompletion() {
        val prefix = "window-ui-${UUID.randomUUID()}"
        val requireSharedAsr = InstrumentationRegistry.getArguments().getString("require_shared_asr") == "true"
        val windows = mutableListOf<MainActivity>()
        val conversations = mutableListOf<String>()
        val handles = mutableListOf<AgentTaskHandle>()
        val release = AtomicBoolean(false)
        val store = AgentTranscriptStore(context, prefix)
        var monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        val cleanupTask = InstrumentationRegistry.getArguments().getString("cleanup_test_task_id")?.toIntOrNull()
        manager.appTasks.firstOrNull { it.taskInfo.taskId == cleanupTask }?.finishAndRemoveTask()
        val rootSeed = store.createConversation("Window test root", privateMode = true)
        store.append(AgentTranscriptRole.PROCESS, "Window root", conversationId = rootSeed.id)
        try {
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$prefix"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, prefix)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            val root = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity
                ?: error("Root window did not open")
            windows += root
            await("Root hydration") { !root.initialAgentHydrationPending && root.conversationWindow.conversationId.isNotBlank() }
            if (requireSharedAsr) {
                assertTrue("The real high-accuracy ASR profile must remain selected", root.isHighAccuracyQnnSelected())
                await("Shared high-accuracy model ready", 180_000) { root.highAccuracyAsrController.isReady() }
            }
            val sharedBefore = com.galaxyssi.chat.voice.asr.local.SharedHighAccuracyLocalAsrRuntime.snapshot()
            val baselinePss = android.os.Debug.getPss()
            android.util.Log.i("GalaxySSIWindowTest", "baseline_pss_kb=$baselinePss shared=$sharedBefore")
            for (index in 1..10) {
                manager.appTasks.first { it.taskInfo.taskId == root.taskId }.moveToFront()
                await("Root visible") { root.conversationWindow.visible }
                val conversation = store.createConversation("Window check $index", privateMode = true)
                conversations += conversation.id
                store.append(AgentTranscriptRole.PROCESS, "Window $index seed", conversationId = conversation.id)
                monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
                instrumentation.runOnMainSync {
                    root.openAgentConversation(conversation.id)
                    root.agentGoalInput.setText("Draft $index")
                    assertTrue(root.agentBrandLogo.performClick())
                }
                val window = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity
                    ?: error("Window $index did not open")
                windows += window
                await("Window $index ready", 120_000) {
                    !window.initialAgentHydrationPending && !root.conversationWindow.openingWindow
                }
                instrumentation.runOnMainSync {
                    assertEquals(conversation.id, window.agentTranscriptStore.activeConversation().id)
                    assertEquals("Draft $index", window.agentGoalInput.text.toString())
                    assertNotEquals(conversation.id, root.agentTranscriptStore.activeConversation().id)
                    assertEquals("", root.agentGoalInput.text.toString())
                    assertNotNull(window.findViewById<View>(R.id.agentSessionSummary))
                }
                val taskId = "$prefix-task-$index"
                handles += AgentTaskRuntime.supervisor(context).submit(AgentWorkspace(
                    workspaceId = taskId, sessionId = taskId, conversationId = conversation.id,
                    taskId = taskId, goal = "Window lifecycle test $index"
                )) {
                    while (!release.get()) {
                        progress("window-test", "Background task remains active")
                        delay(1_000)
                    }
                    store.append(AgentTranscriptRole.PROCESS, "Background completed $index", conversationId = conversation.id)
                }
                val shared = com.galaxyssi.chat.voice.asr.local.SharedHighAccuracyLocalAsrRuntime.snapshot()
                if (requireSharedAsr) {
                    assertEquals("Opening a window must not load another model", sharedBefore?.controllerCreations,
                        shared?.controllerCreations)
                    assertEquals(1, shared?.loadedControllers)
                }
                android.util.Log.i("GalaxySSIWindowTest", "opened=$index task=${window.taskId} " +
                    "pss_kb=${android.os.Debug.getPss()} shared=$shared")
            }
            val taskIds = windows.map { it.taskId }.toSet()
            assertEquals(11, taskIds.size)
            assertEquals(11, manager.appTasks.count { it.taskInfo.taskId in taskIds })
            assertTrue(handles.all { it.isActive })
            android.util.Log.i("GalaxySSIWindowTest", "ten_windows_pss_kb=${android.os.Debug.getPss()}")
            capture("ten-windows-current.png")
            instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_APP_SWITCH)
            SystemClock.sleep(2_000)
            capture("ten-windows-recents.png")

            manager.appTasks.first { it.taskInfo.taskId == root.taskId }.moveToFront()
            await("Root resumed") { root.conversationWindow.visible }
            val target = windows[1]
            instrumentation.runOnMainSync { root.showConversationHub() }
            store.renameConversation(conversations.first(), "Window renamed live")
            await("Shared list refresh") {
                val decor = root.agentSessionsDialog?.window?.decorView
                decor != null && descendants(decor).filterIsInstance<androidx.recyclerview.widget.RecyclerView>()
                    .mapNotNull { it.adapter as? ConversationHubListAdapter }
                    .any { adapter -> adapter.currentList.filterIsInstance<ConversationHubRow.Conversation>()
                        .any { it.item.title == "Window renamed live" } }
            }
            instrumentation.runOnMainSync {
                root.agentSessionsDialog?.dismiss()
                root.openAgentConversation(conversations.first())
                root.agentBrandLogo.performClick()
            }
            await("Existing window foreground") { target.conversationWindow.visible }
            assertEquals(11, manager.appTasks.count { it.taskInfo.taskId in taskIds })
            instrumentation.runOnMainSync {
                assertEquals("Draft 1", target.agentGoalInput.text.toString())
                target.finishAndRemoveTask()
            }
            await("Window closed") { target.isDestroyed }
            assertTrue("Window close must not cancel task", handles.first().isActive)
            release.set(true)
            await("Ten background tasks completed", 120_000) { handles.none { it.isActive } }
            conversations.forEachIndexed { index, id ->
                assertTrue(store.list(id).any { it.text == "Background completed ${index + 1}" })
            }
        } finally {
            release.set(true)
            handles.filter { it.isActive }.forEach { it.cancel("Window test cleanup") }
            instrumentation.runOnMainSync { windows.filterNot { it.isDestroyed }.forEach { it.finishAndRemoveTask() } }
            manager.appTasks.filter { it.taskInfo.baseIntent.getStringExtra(AgentConversationWindows.CONVERSATION) in conversations }
                .forEach { it.finishAndRemoveTask() }
            conversations.forEach(store::deleteConversation)
            store.deleteConversation(rootSeed.id)
            handles.filterNot { it.isActive }.forEach { EncryptedAgentWorkspaceStore(context).delete(it.workspaceId) }
            instrumentation.removeMonitor(monitor)
        }
        if (requireSharedAsr) {
            await("Shared ASR released after all windows close", 60_000) {
                val shared = com.galaxyssi.chat.voice.asr.local.SharedHighAccuracyLocalAsrRuntime.snapshot()
                shared?.clients == 0 && shared.loadedControllers == 0
            }
            android.util.Log.i("GalaxySSIWindowTest", "idle_release_pss_kb=${android.os.Debug.getPss()} " +
                "shared=${com.galaxyssi.chat.voice.asr.local.SharedHighAccuracyLocalAsrRuntime.snapshot()}")
        }
    }

    private fun await(label: String, timeout: Long = 60_000, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < deadline) {
            var ready = false
            instrumentation.runOnMainSync { ready = condition() }
            if (ready) return
            SystemClock.sleep(100)
        }
        error("Timed out: $label")
    }

    private fun capture(name: String) {
        val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: return
        val file = java.io.File(context.getExternalFilesDir("window-test"), name)
        file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }

    private fun descendants(view: View): Sequence<View> = sequence {
        yield(view)
        if (view is android.view.ViewGroup) for (index in 0 until view.childCount) yieldAll(descendants(view.getChildAt(index)))
    }
}
