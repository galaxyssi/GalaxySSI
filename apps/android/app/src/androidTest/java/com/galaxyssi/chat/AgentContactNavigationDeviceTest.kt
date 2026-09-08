package com.galaxyssi.chat

import android.view.View
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentContactNavigationDeviceTest {
    @Test fun registeredAgentContactsCannotEnterPeerChatThroughEitherEntry() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val contacts = AppStore.contacts(context)
        val agents = (0 until contacts.length()).mapNotNull(contacts::optJSONObject)
            .filter { AgentContactNavigationPolicy.opensAgentConversation(it) && !it.optBoolean("deleted") }
        assertTrue("Device must have at least one configured Agent contact", agents.isNotEmpty())
        lateinit var store: AgentTranscriptStore
        var previous = ""
        val created = mutableSetOf<String>()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                store = activity.agentTranscriptStore
                previous = store.activeConversation().id
            }
            try {
                agents.forEach { raw ->
                    val contact = Contact(raw.optString("id"), raw.optString("name"), "")
                    for (directEntry in listOf(true, false)) {
                        scenario.onActivity { activity ->
                            if (directEntry) activity.showChatPage(contact) else activity.openContactMessaging(contact)
                            created += store.activeConversation().id
                            assertEquals(contact.id, View.GONE, activity.chatPage.visibility)
                            assertEquals(contact.id, View.VISIBLE, activity.mainPage.visibility)
                            assertEquals(contact.id, View.VISIBLE, activity.agentPage.visibility)
                            assertEquals(contact.id, PAGE_AGENT, activity.activeMainTab)
                            val selection = AgentModelSelectionSettings.selection(activity, store.activeConversation().id)
                            assertEquals(contact.id, contact.id, selection.targetId)
                        }
                    }
                }
            } finally {
                store.switchConversation(previous)
                created.filter { it != previous }.forEach(store::deleteConversation)
            }
        }
    }
}
