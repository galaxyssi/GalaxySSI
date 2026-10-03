package com.galaxyssi.chat

import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic member events only; no model, network faults, or real research replay. */
@RunWith(AndroidJUnit4::class)
class CollaborationCurrentMemberStateDeviceTest {
    @Test fun oneCurrentStatusRetainsHistoryAndRestoresAfterRecreation() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        val transcript = AgentTranscriptStore(context)
        var id = ""
        var previous = ""
        try {
            ready(scenario)
            scenario.onActivity {
                previous = it.agentTranscriptStore.activeConversation().id
                it.createAgentConversation()
                id = it.agentTranscriptStore.activeConversation().id
            }
            val member = CollaborationMember(name = "Recovery Fixture", agentId = "fixture", providerLabel = "Codex", role = "Researcher")
            CollaborationGroupStore(context).update(id) { it.copy(members = listOf(member), coordinatorId = member.id) }
            val now = System.currentTimeMillis()
            fun row(key: String, text: String, meta: CollaborationTranscriptMetadata, at: Long) = transcript.upsert(
                AgentTranscriptRole.PROCESS, text, dedupeKey = key, timestampMillis = at, conversationId = id,
                taskId = "fixture-task", collaborationJson = meta.encode())
            val current = CollaborationTranscriptMetadata(member.id, member.name, "Codex", member.role,
                AgentSubagentStatus.RUNNING, "current-$id", startedAtMillis = now)
            repeat(22) { index -> row("old-$index-$id", "Archived failure $index", current.copy(runId = "old-$index-$id",
                status = AgentSubagentStatus.FAILED, startedAtMillis = now - 100_000 + index, completedAtMillis = now - 99_000 + index),
                now - 100_000 + index) }
            row("current-$id", "Current assignment", current, now)
            row("connection-$id", "waiting", current.copy(activity = true, connectionState = "waiting"), now + 1)
            scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
            waitUntil { labels(scenario).contains(context.getString(R.string.collaboration_connection_lost)) }
            assertEquals(1, clocks(scenario))
            assertFalse(labels(scenario).contains(context.getString(R.string.collaboration_failed_status)))
            scenario.onActivity {
                val clock = descendants(it.findViewById(R.id.collaborationOutputList)).filterIsInstance<TextView>()
                    .single { view -> view.tag == "collaboration-process-time" }
                assertTrue((clock.parent as View).performClick())
            }
            assertTrue(labels(scenario).any { it.contains("Archived failure 0") && it.contains("Archived failure 21") })
            row("connection-$id", "reconciling", current.copy(activity = true, connectionState = "reconciling"), now + 2)
            scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
            waitUntil { labels(scenario).contains(context.getString(R.string.collaboration_connection_reconciling)) }
            row("current-$id", "Current assignment", current.copy(status = AgentSubagentStatus.SUCCEEDED, completedAtMillis = now + 3), now)
            row("result-$id", "Recovered original result", current.copy(status = AgentSubagentStatus.SUCCEEDED,
                result = true, completedAtMillis = now + 3), now + 3)
            scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
            waitUntil { labels(scenario).contains(context.getString(R.string.collaboration_view_process)) }
            assertEquals(1, clocks(scenario))
            scenario.recreate()
            ready(scenario)
            scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
            waitUntil { clocks(scenario) == 1 }
            assertFalse(labels(scenario).contains(context.getString(R.string.collaboration_connection_lost)))
            assertEquals(25, AgentTranscriptStore(context).list(id).count { it.collaborationJson.isNotBlank() })
        } finally {
            if (id.isNotBlank()) { transcript.deleteConversation(id); CollaborationGroupStore(context).remove(id) }
            if (previous.isNotBlank()) transcript.switchConversation(previous)
            scenario.close()
        }
    }

    private fun labels(scenario: ActivityScenario<MainActivity>): List<String> {
        var values = emptyList<String>()
        scenario.onActivity { values = descendants(it.findViewById(R.id.collaborationOutputList)).filterIsInstance<TextView>()
            .filter { view -> view.visibility == View.VISIBLE }.map { view -> view.text.toString() } }
        return values
    }
    private fun clocks(scenario: ActivityScenario<MainActivity>): Int {
        var count = 0
        scenario.onActivity { count = descendants(it.findViewById(R.id.collaborationOutputList)).count { view ->
            view.tag == "collaboration-process-time" } }
        return count
    }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
    private fun ready(scenario: ActivityScenario<MainActivity>) = waitUntil(60_000) {
        var done = false
        scenario.onActivity { done = !it.initialAgentHydrationPending && it.findViewById<View>(R.id.startupConnectingView).visibility != View.VISIBLE }
        done
    }
    private fun waitUntil(timeout: Long = 15_000, predicate: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < until) {
            if (predicate()) return
            SystemClock.sleep(200)
        }
        fail("Timed out waiting for member projection")
    }
}
