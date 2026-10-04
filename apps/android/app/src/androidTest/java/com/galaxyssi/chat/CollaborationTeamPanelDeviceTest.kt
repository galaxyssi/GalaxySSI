package com.galaxyssi.chat

import android.app.UiAutomation
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollaborationTeamPanelDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val automation get() = instrumentation.getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)

    @Test fun topPanelShowsActionsTimersAndFullWidthSettingsWithoutDuplicatingReplies() = fixture { scenario, id ->
        val group = CollaborationGroupStore(context).update(id) { it.copy(members = listOf("Euclid", "Curie", "Hopper", "Lovelace", "Turing")
            .map { name -> CollaborationMember(id = "$id-$name", name = name, agentId = "fixture", providerLabel = "Codex",
                role = if (name == "Turing") "Coordinator" else "Researcher", modelId = "gpt-6-astra") }, coordinatorId = "$id-Turing") }
        val now = System.currentTimeMillis()
        val snapshot = AgentTeamExecutionSnapshot("panel-$id", "team-$id", id, "task-$id", "$id-Turing",
            "Display-only team panel acceptance", AgentTeamVisibilityMode.VISIBLE, AgentTeamExecutionState.RUNNING,
            group.members.mapIndexed { index, member -> AgentTeamMemberSnapshot(member.agentId, member.role,
                AgentDeliveryMode.OBSERVE, when (index) { 3 -> AgentSubagentStatus.RUNNING; 4 -> AgentSubagentStatus.QUEUED; else -> AgentSubagentStatus.SUCCEEDED },
                output = if (index == 0) "Panel fixture: published result remains unchanged." else "",
                instanceId = member.id, personId = member.id, displayName = member.name, providerLabel = member.providerLabel,
                collaborationGroupId = id, researchStage = listOf("REVISE", "CHALLENGE", "EXECUTE", "VERIFY", "DELIVER")[index],
                executionStartedAtMillis = if (index == 4) 0 else now - 30_000,
                completedAtMillis = if (index < 3) now - 5_000 else 0,
                waitingForDependencies = index == 4, pendingDependencyNames = if (index == 4) listOf("Lovelace") else emptyList(),
                updatedAtMillis = now) }, createdAtMillis = now - 40_000, updatedAtMillis = now)
        CollaborationTranscriptPublisher(context).publish(snapshot)
        scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
        waitUntil("collapsed summary") { texts(scenario, R.id.collaborationMemberStrip).any {
            it == context.getString(R.string.collaboration_team_counts, 1, 1) } }
        waitUntil("published reply retained") { texts(scenario, R.id.collaborationOutputList).any {
            it.contains("Panel fixture: published result remains unchanged.") } }
        scenario.onActivity { activity ->
            val panel = activity.findViewById<ViewGroup>(R.id.collaborationMemberStrip)
            assertEquals(View.GONE, panel.findViewWithTag<View>("collaboration-team-members").visibility)
            assertEquals(activity.findViewById<View>(R.id.agentOutputViewport).width, panel.width)
        }
        screenshot("collaboration-team-panel-collapsed.png")
        scenario.onActivity { it.findViewById<ViewGroup>(R.id.collaborationMemberStrip)
            .findViewWithTag<View>("collaboration-team-toggle").performClick() }
        waitUntil("current action") { texts(scenario, R.id.collaborationMemberStrip).contains(context.getString(R.string.collaboration_stage_revise)) }
        scenario.onActivity { activity ->
            val list = activity.findViewById<ViewGroup>(R.id.collaborationMemberStrip).findViewWithTag<RecyclerView>("collaboration-team-members")
            assertEquals(5, list.adapter!!.itemCount)
            list.scrollToPosition(3)
        }
        waitUntil("verify action") { texts(scenario, R.id.collaborationMemberStrip).contains(context.getString(R.string.collaboration_stage_verify)) }
        val before = clock(scenario, "Lovelace")
        SystemClock.sleep(2_100)
        assertNotEquals(before, clock(scenario, "Lovelace"))
        assertFalse("Running members must not be repeated below replies", texts(scenario, R.id.collaborationOutputList).any { it.contains("Lovelace") })
        screenshot("collaboration-team-panel-expanded.png")
        val revision = group.revision
        scenario.onActivity { it.findViewById<ViewGroup>(R.id.collaborationMemberStrip)
            .findViewWithTag<View>("collaboration-team-settings").performClick() }
        waitUntil("settings opened") { windowTexts().contains(context.getString(R.string.collaboration_add)) }
        assertSheetWidth()
        clickText("Euclid")
        waitUntil("member configuration") { windowTexts().contains(context.getString(R.string.collaboration_independent)) }
        assertSheetWidth()
        screenshot("collaboration-team-panel-settings.png")
        clickText(context.getString(R.string.collaboration_done))
        waitUntil("settings saved") { CollaborationGroupStore(context).load(id)?.revision == revision + 1 }
        val completedAt = System.currentTimeMillis()
        CollaborationTranscriptPublisher(context).publish(snapshot.copy(state = AgentTeamExecutionState.SUCCEEDED, updatedAtMillis = completedAt,
            members = snapshot.members.map { it.copy(status = AgentSubagentStatus.SUCCEEDED, completedAtMillis = completedAt) }))
        scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
        waitUntil("completion") { texts(scenario, R.id.collaborationMemberStrip).contains(context.getString(R.string.collaboration_team_counts, 0, 0)) }
        val completed = clock(scenario, "Lovelace")
        SystemClock.sleep(1_500)
        assertEquals(completed, clock(scenario, "Lovelace"))
        scenario.recreate()
        ready(scenario)
        scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
        waitUntil("restored summary") { texts(scenario, R.id.collaborationMemberStrip).contains(context.getString(R.string.collaboration_team_counts, 0, 0)) }
        scenario.onActivity { activity ->
            val panel = activity.findViewById<ViewGroup>(R.id.collaborationMemberStrip)
            if (panel.findViewWithTag<View>("collaboration-team-members").visibility == View.GONE)
                panel.findViewWithTag<View>("collaboration-team-toggle").performClick()
            panel.findViewWithTag<RecyclerView>("collaboration-team-members").scrollToPosition(3)
        }
        waitUntil("restored completed clock") { clock(scenario, "Lovelace") == completed }
    }

    @Test fun thousandMemberPanelRecyclesRowsAndKeepsComposerReachable() = fixture { scenario, id ->
        val names = CollaborationGroupStore.names(context)
        CollaborationGroupStore(context).update(id) { it.copy(members = names.take(1024).mapIndexed { index, name ->
            CollaborationMember("$id-$index", name, "fixture", "Codex", "Researcher") }, coordinatorId = "$id-0") }
        scenario.onActivity { it.refreshCollaborationStrip() }
        scenario.onActivity { activity ->
            val panel = activity.findViewById<ViewGroup>(R.id.collaborationMemberStrip)
            panel.findViewWithTag<View>("collaboration-team-toggle").performClick()
        }
        instrumentation.waitForIdleSync()
        scenario.onActivity { activity ->
            val panel = activity.findViewById<ViewGroup>(R.id.collaborationMemberStrip)
            val list = panel.findViewWithTag<RecyclerView>("collaboration-team-members")
            assertEquals(1024, list.adapter!!.itemCount)
            assertTrue("Only visible rows should be inflated", list.childCount in 1..20)
            assertTrue("Conversation must retain space", activity.findViewById<View>(R.id.agentOutputViewport).height > activity.dp(80))
            assertTrue(activity.agentGoalInput.isShown)
            list.scrollToPosition(1023)
        }
        waitUntil("last member") { texts(scenario, R.id.collaborationMemberStrip).any { it.contains(names[1023]) } }
        scenario.onActivity { activity ->
            activity.agentGoalInput.requestFocus()
            activity.getSystemService(android.view.inputmethod.InputMethodManager::class.java)
                .showSoftInput(activity.agentGoalInput, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
        }
        waitUntil("keyboard shown") {
            var shown = false
            scenario.onActivity { shown = it.window.decorView.rootWindowInsets?.isVisible(android.view.WindowInsets.Type.ime()) == true }
            shown
        }
        scenario.onActivity { activity ->
            val location = IntArray(2)
            activity.agentGoalInput.getLocationOnScreen(location)
            val visible = android.graphics.Rect()
            activity.window.decorView.getWindowVisibleDisplayFrame(visible)
            assertTrue("Composer must stay above the keyboard", location[1] + activity.agentGoalInput.height <= visible.bottom)
            activity.getSystemService(android.view.inputmethod.InputMethodManager::class.java)
                .hideSoftInputFromWindow(activity.agentGoalInput.windowToken, 0)
        }
        scenario.onActivity { activity ->
            val panel = activity.findViewById<ViewGroup>(R.id.collaborationMemberStrip)
            panel.findViewWithTag<View>("collaboration-team-toggle").performClick()
            assertEquals(0, panel.findViewWithTag<RecyclerView>("collaboration-team-members").adapter!!.itemCount)
        }
    }

    private fun fixture(block: (ActivityScenario<MainActivity>, String) -> Unit) {
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        val transcript = AgentTranscriptStore(context)
        var id = ""; var previous = ""
        try {
            ready(scenario)
            scenario.onActivity {
                previous = it.agentTranscriptStore.activeConversation().id
                it.createAgentConversation(); id = it.agentTranscriptStore.activeConversation().id
                it.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
            transcript.append(AgentTranscriptRole.PROCESS, "Team panel display fixture", conversationId = id,
                dedupeKey = "collaboration-created:$id")
            transcript.renameConversation(id, "Team panel acceptance")
            block(scenario, id)
        } finally {
            if (id.isNotBlank()) { transcript.deleteConversation(id); CollaborationGroupStore(context).remove(id) }
            if (previous.isNotBlank()) transcript.switchConversation(previous)
            scenario.close()
        }
    }

    private fun clock(scenario: ActivityScenario<MainActivity>, name: String): String {
        var value = ""
        scenario.onActivity { activity ->
            value = descendants(activity.findViewById(R.id.collaborationMemberStrip)).filterIsInstance<TextView>()
                .firstOrNull { it.tag == "collaboration-process-time" && (it.parent as View).contentDescription.toString().startsWith("$name:") }
                ?.text?.toString().orEmpty()
        }
        return value
    }
    private fun texts(scenario: ActivityScenario<MainActivity>, id: Int): List<String> {
        var result = emptyList<String>()
        scenario.onActivity { result = descendants(it.findViewById(id)).filterIsInstance<TextView>().filter { it.isShown }.map { it.text.toString() } }
        return result
    }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
    private fun nodes(node: android.view.accessibility.AccessibilityNodeInfo): List<android.view.accessibility.AccessibilityNodeInfo> =
        listOf(node) + (0 until node.childCount).flatMap { node.getChild(it)?.let(::nodes).orEmpty() }
    private fun windowTexts() = automation.rootInActiveWindow?.let(::nodes).orEmpty().mapNotNull { it.text?.toString() }
    private fun clickText(prefix: String) {
        val node = automation.rootInActiveWindow?.let(::nodes).orEmpty().first { it.text?.toString()?.startsWith(prefix) == true }
        var target = node
        while (!target.isClickable && target.parent != null) target = target.parent
        assertTrue(target.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK))
    }
    private fun assertSheetWidth() {
        val bounds = android.graphics.Rect()
        automation.rootInActiveWindow.getBoundsInScreen(bounds)
        assertTrue("Settings sheet must fill the available width", bounds.width() >= context.resources.displayMetrics.widthPixels - 8)
    }
    private fun ready(scenario: ActivityScenario<MainActivity>) = waitUntil("activity ready", 60_000) {
        var ready = false
        scenario.onActivity { ready = !it.initialAgentHydrationPending && it.findViewById<View>(R.id.startupConnectingView).visibility != View.VISIBLE }
        ready
    }
    private fun waitUntil(label: String, timeout: Long = 15_000, condition: () -> Boolean) {
        val end = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < end) { if (condition()) return; SystemClock.sleep(200) }
        fail("Timed out: $label")
    }
    private fun screenshot(name: String) {
        instrumentation.waitForIdleSync()
        SystemClock.sleep(400)
        val bitmap = automation.takeScreenshot() ?: return
        try { File(context.getExternalFilesDir(null), name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) } }
        finally { bitmap.recycle() }
    }
}
