package com.galaxyssi.chat

import android.app.UiAutomation
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollaborationGroupDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val automation get() = instrumentation.getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)

    @Test fun rosterPickerSettingsAndHistoryUseTheExistingConversation() = withConversation { scenario, activity, id ->
        val members = listOf(CollaborationMember(name = "Turing", agentId = "fixture:codex", providerLabel = "Codex",
            role = "Coordinator"), CollaborationMember(name = "Curie", agentId = "fixture:deepseek", providerLabel = "DeepSeek",
            role = "Independent review", independentReview = true))
        val store = CollaborationGroupStore(context)
        val saved = store.update(id) { it.copy(members = members, coordinatorId = members.first().id) }
        assertEquals(saved, store.load(id))
        scenario.onActivity {
            it.refreshCollaborationStrip()
            assertEquals("active=${it.agentTranscriptStore.activeConversation().id}, rendered=${it.agentRenderedConversationId}, fixture=$id",
                View.VISIBLE, it.findViewById<View>(R.id.collaborationMemberStrip).visibility)
            it.agentGoalInput.requestFocus()
            it.getSystemService(android.view.inputmethod.InputMethodManager::class.java)
                .showSoftInput(it.agentGoalInput, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
            it.agentGoalInput.setText("@")
            it.agentGoalInput.setSelection(1)
            it.maybeShowAgentMentionPicker(it.agentGoalInput.text)
        }
        waitUntil("member picker") { windowTexts().contains("Turing  AI") }
        screenshot("collaboration-members.png")
        assertTrue(windowTexts().any { it.contains("Curie") })
        clickTextStarting(context.getString(R.string.collaboration_settings))
        waitUntil("member manager") { windowTexts().contains(context.getString(R.string.collaboration_add)) }
        clickTextStarting("Turing")
        waitUntil("member settings") { windowTexts().contains(context.getString(R.string.collaboration_independent)) }
        screenshot("collaboration-settings.png")
        clickTextStarting(context.getString(R.string.collaboration_done))
        waitUntil("saved member settings") { store.load(id)?.revision == saved.revision + 1 }
        waitUntil("settings closed after save") { !windowTexts().contains(context.getString(R.string.collaboration_independent)) }
        scenario.onActivity { it.agentGoalInput.setText("") }
        val metadata = CollaborationTranscriptMetadata(members[0].id, "Turing", "Codex", "Coordinator",
            AgentSubagentStatus.RUNNING, "fixture-run")
        activity.agentTranscriptStore.upsert(AgentTranscriptRole.PROCESS, "Check the test evidence",
            dedupeKey = "collaboration:fixture:status", conversationId = id, collaborationJson = metadata.encode())
        scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
        waitUntil("member progress row") { windowTexts().contains(context.getString(R.string.collaboration_running)) }
        screenshot("collaboration-progress.png")
        scenario.recreate()
        ready(scenario)
        assertEquals(saved.copy(revision = saved.revision + 1), store.load(id))
    }

    @Test fun realCodexAndDeepSeekDeliverSeparateMemberResults() {
        assumeTrue("Real model calls require explicit invocation", InstrumentationRegistry.getArguments()
            .getString("collaborationReal") == "true")
        withConversation { scenario, _, id ->
            val targets = AppStoreAgentConnectorRegistry(context).availableTargets()
                .filter { it.status == AgentConnectorStatus.AVAILABLE }
            val codex = requireNotNull(targets.firstOrNull { it.id.contains("codex", true) && ':' in it.id }) { "Paired Codex unavailable" }
            val deepseek = requireNotNull(targets.firstOrNull { it.title.contains("deepseek", true) || it.id.contains("deepseek", true) }) { "DeepSeek unavailable" }
            val members = listOf(CollaborationMember(name = "Turing", agentId = codex.id, providerLabel = codex.title,
                role = "Coordinate and combine the verified result"),
                CollaborationMember(name = "Curie", agentId = deepseek.id, providerLabel = deepseek.title,
                    role = "Independently check the arithmetic", independentReview = true))
            CollaborationGroupStore(context).update(id) { it.copy(members = members, coordinatorId = members.first().id) }
            scenario.onActivity {
                it.refreshCollaborationStrip()
                it.agentGoalInput.setText("协作验收：请两位成员分别按职责核对 17 × 23 的结果，每位在回复开头写自己的成员名字，协调员汇总为一句中文。无需联网，不调用手机操作工具。")
                it.submitAgentGoal()
            }
            val runtime = GlobalSuperAgentRuntime.get(context)
            var snapshot: AgentTeamExecutionSnapshot? = null
            waitUntil("real collaboration completion", 360_000) {
                snapshot = runtime.agentTeamSnapshots().firstOrNull { it.conversationId == id }
                snapshot?.state?.isTerminal == true
            }
            val result = requireNotNull(snapshot)
            val report = "state=${result.state}\n" + result.members.joinToString("\n") {
                "${it.displayName}: ${it.status}, chars=${it.output.length}, error=${it.errorMessage.take(200)}"
            }
            File(context.getExternalFilesDir(null), "collaboration-real-result.txt").writeText(report)
            assertEquals(report, AgentTeamExecutionState.SUCCEEDED, result.state)
            assertEquals(2, result.members.size)
            assertTrue(report, result.members.all { it.status == AgentSubagentStatus.SUCCEEDED && it.output.contains("391") })
            assertTrue("Each real model must receive its own member identity", result.members.all {
                it.output.contains(it.displayName, ignoreCase = true)
            })
            val transcript = AgentTranscriptStore(context).list(id)
            assertEquals(2, transcript.count { CollaborationTranscriptMetadata.decode(it.collaborationJson)?.result == true })
            waitUntil("canonical final answer", 30_000) {
                AgentTranscriptStore(context).list(id).any { it.role == AgentTranscriptRole.ASSISTANT && it.text.contains("391") }
            }
            scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
            screenshot("collaboration-real-result.png")
        }
    }

    private fun withConversation(block: (ActivityScenario<MainActivity>, MainActivity, String) -> Unit) {
        automation.serviceInfo = automation.serviceInfo.apply {
            flags = flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        val reference = AtomicReference<MainActivity>()
        var id = ""
        var previous = ""
        try {
            ready(scenario)
            scenario.onActivity {
                reference.set(it)
                it.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                previous = it.agentTranscriptStore.activeConversation().id
                it.createAgentConversation()
                id = it.agentTranscriptStore.activeConversation().id
            }
            reference.get().agentTranscriptStore.append(AgentTranscriptRole.PROCESS, "Collaboration acceptance fixture",
                dedupeKey = "collaboration-created:$id", conversationId = id)
            reference.get().agentTranscriptStore.renameConversation(id, "Collaboration acceptance")
            block(scenario, reference.get(), id)
        } catch (error: Throwable) {
            screenshot("collaboration-failure.png")
            File(context.getExternalFilesDir(null), "collaboration-failure.txt").writeText(
                error.toString() + "\n" + windowTexts().joinToString("\n"))
            throw error
        } finally {
            if (id.isNotBlank()) {
                val runtime = GlobalSuperAgentRuntime.get(context)
                runtime.agentTeamSnapshots().filter { it.conversationId == id && !it.state.isTerminal }
                    .forEach { runtime.cancelAgentTeam(it.supervisorRunId) }
                reference.get()?.agentTranscriptStore?.deleteConversation(id)
            }
            if (previous.isNotBlank()) reference.get()?.agentTranscriptStore?.switchConversation(previous)
            scenario.close()
        }
    }

    private fun ready(scenario: ActivityScenario<MainActivity>) = waitUntil("activity ready", 60_000) {
        var ready = false
        scenario.onActivity { ready = !it.initialAgentHydrationPending &&
            it.findViewById<View>(R.id.startupConnectingView).visibility != View.VISIBLE &&
            it.conversationWindow.conversationId.isNotBlank() }
        ready
    }

    private fun waitUntil(label: String, timeout: Long = 15_000, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < until) {
            if (condition()) return
            SystemClock.sleep(200)
        }
        fail("Timed out: $label")
    }

    private fun windowTexts(): List<String> = buildList {
        fun visit(node: android.view.accessibility.AccessibilityNodeInfo?) {
            if (node == null || node.packageName?.toString() != context.packageName) return
            node.text?.toString()?.let(::add)
            repeat(node.childCount) { visit(node.getChild(it)) }
        }
        automation.windows.forEach { visit(it.root) }
        visit(automation.rootInActiveWindow)
    }

    private fun clickTextStarting(prefix: String) {
        fun visit(node: android.view.accessibility.AccessibilityNodeInfo?): Boolean {
            if (node == null || node.packageName?.toString() != context.packageName) return false
            if (node.text?.toString()?.startsWith(prefix) == true) {
                var candidate: android.view.accessibility.AccessibilityNodeInfo? = node
                repeat(4) {
                    if (candidate?.isClickable == true) return candidate!!.performAction(
                        android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)
                    candidate = candidate?.parent
                }
            }
            return (0 until node.childCount).any { visit(node.getChild(it)) }
        }
        assertTrue("No clickable member $prefix", automation.windows.any { visit(it.root) } || visit(automation.rootInActiveWindow))
    }

    private fun screenshot(name: String) {
        instrumentation.waitForIdleSync()
        SystemClock.sleep(600)
        automation.takeScreenshot()?.let { bitmap ->
            try { File(context.getExternalFilesDir(null), name).outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            } } finally { bitmap.recycle() }
        }
    }
}
