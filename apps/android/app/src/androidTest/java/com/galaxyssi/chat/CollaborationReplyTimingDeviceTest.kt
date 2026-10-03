package com.galaxyssi.chat

import android.app.UiAutomation
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollaborationReplyTimingDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun replyDatesTickingCompletionAndRecreationUseStoredMemberTimes() {
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
                it.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
            val first = CollaborationMember(name = "Curie", agentId = "fixture", providerLabel = "DeepSeek", role = "Reviewer")
            val second = CollaborationMember(name = "Hopper", agentId = "fixture", providerLabel = "Codex", role = "Researcher")
            CollaborationGroupStore(context).update(id) { it.copy(members = listOf(first, second), coordinatorId = second.id) }
            transcript.append(AgentTranscriptRole.PROCESS, "Reply timing fixture", conversationId = id,
                dedupeKey = "collaboration-created:$id")
            transcript.renameConversation(id, "Reply timing acceptance")
            val now = System.currentTimeMillis()
            val previousDay = now - 86_400_000L
            fun member(value: CollaborationMember, result: Boolean) = AgentTeamMemberSnapshot(
                value.agentId, value.role, AgentDeliveryMode.OBSERVE,
                if (result) AgentSubagentStatus.SUCCEEDED else AgentSubagentStatus.RUNNING,
                output = if (result) "Verified the timing fixture. No model was called." else "",
                instanceId = value.id, displayName = value.name, providerLabel = value.providerLabel,
                collaborationGroupId = id, startedAtMillis = if (result) previousDay - 123_000L else now - 5_000L,
                completedAtMillis = if (result) previousDay else 0L)
            val snapshot = AgentTeamExecutionSnapshot("timing-$id", "team-$id", id, "task-$id", second.id,
                "Display-only timing acceptance", AgentTeamVisibilityMode.VISIBLE, AgentTeamExecutionState.RUNNING,
                listOf(member(first, true), member(second, false)), createdAtMillis = previousDay - 500_000L, updatedAtMillis = now)
            CollaborationTranscriptPublisher(context).publish(snapshot)
            scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
            waitUntil("both clocks visible") { labels(scenario, "collaboration-process-time").size == 2 }
            val initial = memberClocks(scenario)
            val expectedDate = CollaborationReplyTiming.formatReplyTime(previousDay, now)
            assertEquals(listOf(expectedDate), labels(scenario, "collaboration-reply-time"))
            SystemClock.sleep(2_200L)
            val later = memberClocks(scenario)
            assertEquals("Completed reply must not tick", initial.getValue("Curie"), later.getValue("Curie"))
            assertNotEquals("Running reply must tick", initial.getValue("Hopper"), later.getValue("Hopper"))
            scenario.onActivity { activity ->
                val list = activity.findViewById<ViewGroup>(R.id.collaborationOutputList)
                descendants(list).filterIsInstance<TextView>().filter { it.tag == "collaboration-reply-time" }.forEach {
                    assertTrue("Timestamp must fit the row", it.right <= (it.parent as View).width)
                    assertEquals("Timestamp cannot be clipped", 0, it.layout.getEllipsisCount(0))
                }
            }
            screenshot("collaboration-reply-time-running.png")

            val endedAt = System.currentTimeMillis()
            val finished = snapshot.copy(state = AgentTeamExecutionState.SUCCEEDED, updatedAtMillis = endedAt,
                members = snapshot.members.map { if (it.memberId == second.id)
                    it.copy(status = AgentSubagentStatus.SUCCEEDED, output = "Timing fixture completed.", completedAtMillis = endedAt)
                else it })
            CollaborationTranscriptPublisher(context).publish(finished)
            scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
            waitUntil("second reply timestamp") { labels(scenario, "collaboration-reply-time").size == 2 }
            val completed = memberClocks(scenario)
            scenario.recreate()
            ready(scenario)
            scenario.onActivity { it.refreshAgentTranscriptWindow(id) }
            waitUntil("restored clocks") { labels(scenario, "collaboration-process-time").size == 2 }
            SystemClock.sleep(2_200L)
            assertEquals("Recreation must not restart completed timers", completed, memberClocks(scenario))
            val restored = AgentTranscriptStore(context).list(id).mapNotNull { CollaborationTranscriptMetadata.decode(it.collaborationJson) }
                .single { it.result && it.memberId == second.id }
            assertEquals(endedAt, restored.completedAtMillis)
            assertEquals(now - 5_000L, restored.startedAtMillis)
            scenario.onActivity { activity ->
                val process = descendants(activity.findViewById(R.id.collaborationOutputList)).filterIsInstance<TextView>()
                    .first { it.tag == "collaboration-process-time" }
                val row = process.parent as ViewGroup
                val label = row.getChildAt(0)
                assertTrue("Completed duration stays beside the process label", process.left - label.right <= activity.dp(12))
                assertTrue("Existing process disclosure remains clickable", (process.parent as View).performClick())
            }
            screenshot("collaboration-reply-time-completed.png")
        } finally {
            if (id.isNotBlank()) {
                transcript.deleteConversation(id)
                CollaborationGroupStore(context).remove(id)
            }
            if (previous.isNotBlank()) transcript.switchConversation(previous)
            scenario.close()
        }
    }

    private fun labels(scenario: ActivityScenario<MainActivity>, tag: String): List<String> {
        var result = emptyList<String>()
        scenario.onActivity { activity ->
            result = descendants(activity.findViewById(R.id.collaborationOutputList)).filterIsInstance<TextView>()
                .filter { it.tag == tag }.map { it.text.toString() }
        }
        return result
    }

    private fun memberClocks(scenario: ActivityScenario<MainActivity>): Map<String, String> {
        var result = emptyMap<String, String>()
        scenario.onActivity { activity ->
            result = descendants(activity.findViewById(R.id.collaborationOutputList)).filterIsInstance<TextView>()
                .filter { it.tag == "collaboration-process-time" }.associate {
                    (it.parent as View).contentDescription.toString().substringBefore(":") to it.text.toString()
                }
        }
        return result
    }

    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    private fun ready(scenario: ActivityScenario<MainActivity>) = waitUntil("activity ready", 60_000L) {
        var ready = false
        scenario.onActivity { ready = !it.initialAgentHydrationPending &&
            it.findViewById<View>(R.id.startupConnectingView).visibility != View.VISIBLE }
        ready
    }

    private fun waitUntil(label: String, timeout: Long = 15_000L, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < until) {
            if (condition()) return
            SystemClock.sleep(200L)
        }
        fail("Timed out: $label")
    }

    private fun screenshot(name: String) {
        instrumentation.waitForIdleSync()
        val bitmap = instrumentation.getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES).takeScreenshot() ?: return
        try { File(context.getExternalFilesDir(null), name).outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
}
