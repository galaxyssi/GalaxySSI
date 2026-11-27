package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.EditText
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test

class AgentSessionRequirementDeviceTest {
    @Test fun userMessageMenuEditsAndRemovesTheRequirementWithoutChangingTheMessage() {
        val runner = InstrumentationRegistry.getInstrumentation()
        val target = runner.targetContext
        org.junit.Assume.assumeTrue(target.packageName.endsWith(".pairingqa"))
        val store = AgentTranscriptStore(target, "session-requirement-ui-test")
        val id = store.createConversation("Synthetic menu test").id
        val original = "Use the original units and show the calculation."
        assertTrue(store.append(AgentTranscriptRole.USER, original, conversationId = id))
        val entry = store.list(id).single { it.role == AgentTranscriptRole.USER }
        var activity: HealthAtlasDiscussionActivity? = null
        try {
            val chat = runner.startActivitySync(Intent(target, HealthAtlasDiscussionActivity::class.java)
                .putExtra("galaxyssi_agent_conversation_id", id).putExtra("galaxyssi_open_agent", true)
                .putExtra(AgentConversationWindows.WINDOW_KEY, "test:" + id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as HealthAtlasDiscussionActivity
            activity = chat
            fun open() {
                val row = chat.agentUserTranscriptRow(entry) as ViewGroup
                val body = row.getChildAt(0) as TextView
                val callback = requireNotNull(body.customSelectionActionModeCallback)
                val mode = requireNotNull(chat.startActionMode(callback))
                val action = (0 until mode.menu.size()).map(mode.menu::getItem)
                    .single { it.title == chat.getString(R.string.agent_session_requirement) }
                assertTrue(callback.onActionItemClicked(mode, action))
            }
            fun dialog() = WindowInspector.getGlobalWindowViews().single { it.findViewById<View>(android.R.id.button1) != null }
            fun field(view: View): EditText? = when (view) {
                is EditText -> view
                is ViewGroup -> (0 until view.childCount).firstNotNullOfOrNull { field(view.getChildAt(it)) }
                else -> null
            }
            runner.runOnMainSync { open() }
            runner.waitForIdleSync()
            runner.runOnMainSync {
                val pane = dialog()
                val input = requireNotNull(field(pane))
                assertEquals(original, input.text.toString())
                input.setText("Always show units.")
                pane.findViewById<View>(android.R.id.button1).performClick()
            }
            runner.waitForIdleSync()
            assertEquals("Always show units.", store.conversation(id)?.sessionRequirement)
            runner.runOnMainSync { open() }
            runner.waitForIdleSync()
            runner.runOnMainSync { dialog().findViewById<View>(android.R.id.button3).performClick() }
            runner.waitForIdleSync()
            assertEquals("", store.conversation(id)?.sessionRequirement)
            assertEquals(original, store.list(id).single { it.role == AgentTranscriptRole.USER }.text)
        } finally {
            activity?.let { runner.runOnMainSync { it.finish() } }
            store.deleteConversation(id)
        }
    }

    @Test fun editRemoveAndRestoreRemainScopedToTheOwningConversation() {
        val target = InstrumentationRegistry.getInstrumentation().targetContext
        val store = AgentTranscriptStore(target, "session-requirement-test")
        val a = store.createConversation("Synthetic A").id
        val goal = "Compare methods."
        assertTrue(store.append(AgentTranscriptRole.USER, goal, conversationId = a))
        val b = store.createConversation("Synthetic B").id
        try {
            val note = "Compare only offline methods."
            val changed = "Use the two public examples."
            store.context(a)
            assertTrue(store.setSessionRequirement(a, note))
            val first = store.context(a)
            assertTrue(first.asPromptBlock().contains(note))
            assertTrue(AgentConversationTransportCache.render(first, 2048, goal).contains(note))
            assertEquals(note, AgentPlanContinuationScope(a, "turn").context(first).sessionRequirement)
            assertEquals("", AgentPlanContinuationScope(b, "turn").context(first).sessionRequirement)
            assertFalse(store.context(b).asPromptBlock().contains(note))
            assertEquals("", store.context("missing-synthetic-id").sessionRequirement)
            assertTrue(store.setSessionRequirement(a, changed))
            val reopened = AgentTranscriptStore(target, "session-requirement-test")
            val edited = reopened.context(a)
            assertEquals(changed, edited.sessionRequirement)
            assertFalse(edited.asPromptBlock().contains(note))
            assertFalse(reopened.setSessionRequirement(a, "x".repeat(MAX_SESSION_REQUIREMENT + 1)))
            assertTrue(reopened.setSessionRequirement(a, ""))
            assertFalse(store.context(a).asPromptBlock().contains(changed))
            assertEquals(goal, reopened.list(a).single { it.role == AgentTranscriptRole.USER }.text)
        } finally {
            store.deleteConversation(a)
            store.deleteConversation(b)
        }
    }

    @Test fun desktopProjectionKeepsTheRequirementWithoutLeakingAnExcludedGlobalContext() {
        val projected = AgentConversationProjection.encode("a", emptyList(), 2048, 1, false,
            sessionRequirement = "Quote only public sources.")
        assertTrue(projected.contains("Quote only public sources."))
        assertFalse(projected.contains("global_context"))
        val context = AgentConversationContext("a", "", emptyList(), true, globalContext = "private-global-fixture",
            sessionRequirement = "Quote only public sources.")
        val compact = context.asTransportBlock(512, includeGlobalContext = true)
        assertTrue(compact.contains("Quote only public sources."))
        assertFalse(compact.contains("private-global-fixture"))
    }
}
