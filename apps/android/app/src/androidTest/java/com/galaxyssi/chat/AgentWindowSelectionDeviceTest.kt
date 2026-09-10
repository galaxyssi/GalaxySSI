package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentWindowSelectionDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun selectionIsDurableBeforeAnyWindowControllerOrHydrationCallback() {
        val key = "selection-immediate-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val a = store.createConversation("Window selection A", privateMode = true)
        store.append(AgentTranscriptRole.PROCESS, "A", conversationId = a.id)
        val b = store.createConversation("Window selection B", privateMode = true)
        store.append(AgentTranscriptRole.PROCESS, "B", conversationId = b.id)
        try {
            val states = AgentWindowStateStore(context)
            states.select(key, a.id)
            assertTrue(store.switchConversation(b.id))
            assertEquals("A cold Activity must not restore the stale controller selection", b.id, states.selected(key))
            assertEquals(b.id, AgentTranscriptStore(context, key).activeConversation().id)
        } finally { store.deleteConversation(a.id); store.deleteConversation(b.id) }
    }

    @Test fun unsentDraftClearsPreviousWindowSelectionAndSurvivesReopen() {
        val key = "selection-draft-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val previous = store.createConversation("Previous selection", privateMode = true)
        store.append(AgentTranscriptRole.PROCESS, "Previous", conversationId = previous.id)
        val states = AgentWindowStateStore(context)
        states.select(key, previous.id)
        val draft = store.createConversation("Unsent window draft", privateMode = true)
        try {
            assertEquals("A stale selection must not override an unsent draft", "", states.selected(key))
            assertEquals(draft.id, AgentTranscriptStore(context, key).activeConversation().id)
        } finally { store.deleteConversation(draft.id); store.deleteConversation(previous.id) }
    }

    @Test fun legacySelectionWinsOnceAndCannotResurrectAfterNewSelection() {
        val key = "selection-migrate-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val a = store.createConversation("Legacy window A", privateMode = true)
        store.append(AgentTranscriptRole.PROCESS, "A", conversationId = a.id)
        val b = store.createConversation("Legacy window B", privateMode = true)
        store.append(AgentTranscriptRole.PROCESS, "B", conversationId = b.id)
        val preferences = AgentEncryptedDatabase(context, AgentTranscriptStore.PREFS)
        val legacyKey = "${AgentTranscriptStore.KEY_ACTIVE_CONVERSATION}:$key"
        try {
            val states = AgentWindowStateStore(context)
            states.select(key, a.id)
            preferences.writeString(legacyKey, b.id)
            val migrated = AgentTranscriptStore(context, key)
            assertEquals(b.id, migrated.activeConversation().id)
            assertEquals(b.id, states.selected(key))
            assertEquals("", preferences.readString(legacyKey, ""))
            assertTrue(migrated.switchConversation(a.id))
            assertEquals(a.id, AgentTranscriptStore(context, key).activeConversation().id)
        } finally {
            preferences.remove(legacyKey)
            store.deleteConversation(a.id); store.deleteConversation(b.id)
        }
    }

    @Test fun selectionChangesDoNotCopyAnotherWindowsDraftOrSelection() {
        val key = "selection-isolation-${UUID.randomUUID()}"
        val first = AgentTranscriptStore(context, "$key-a")
        val second = AgentTranscriptStore(context, "$key-b")
        val a = first.createConversation("Isolated window A", privateMode = true)
        first.append(AgentTranscriptRole.PROCESS, "A", conversationId = a.id)
        val b = second.createConversation("Isolated window B", privateMode = true)
        second.append(AgentTranscriptRole.PROCESS, "B", conversationId = b.id)
        try {
            val states = AgentWindowStateStore(context)
            states.save("$key-a", a.id, AgentWindowDraft("draft A"))
            states.save("$key-b", b.id, AgentWindowDraft("draft B"))
            assertTrue(first.switchConversation(b.id))
            assertEquals(b.id, states.selected("$key-a"))
            assertEquals(b.id, second.activeConversation().id)
            assertEquals("draft A", states.load("$key-a", a.id).text)
            assertEquals("draft B", states.load("$key-b", b.id).text)
            assertTrue(first.switchConversation(a.id))
            assertEquals(b.id, AgentTranscriptStore(context, "$key-b").activeConversation().id)
        } finally { first.deleteConversation(a.id); second.deleteConversation(b.id) }
    }
}
