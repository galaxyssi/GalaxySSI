package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSessionPersistencePolicyTest {
    @Test
    fun oversizedLegacyCheckpointIsRejectedBeforeDecryption() {
        assertFalse(AgentSessionPersistencePolicy.shouldDiscardEncodedValue(128 * 1024))
        assertTrue(AgentSessionPersistencePolicy.shouldDiscardEncodedValue(256 * 1024))
    }

    @Test
    fun screenCheckpointKeepsSummaryAndDropsTransientPayloads() {
        val screen = ScreenContext(
            foregroundApp = "SignalASI",
            activityName = "MainActivity",
            pageTitle = "Agent",
            visibleTextCount = 400,
            clickableNodeCount = 80,
            visibleTexts = List(400) { "visible-$it" },
            selectedText = "selected",
            clickableElements = List(80) {
                ScreenElement("button-$it", "id-$it", "Button", "0,0,1,1")
            },
            inputFields = listOf(ScreenElement("message", "input", "EditText", "0,0,1,1")),
            scrollableRegions = listOf(ScreenElement("list", "list", "List", "0,0,1,1")),
            clipboard = ClipboardContext(hasText = true, textLength = 50, preview = "private"),
            notifications = AgentNotificationContext(
                hasAccess = true,
                items = listOf(AgentNotificationItem(title = "private")),
                totalCount = 12
            ),
            installedApps = List(300) { InstalledAppInfo("App $it", "app.$it") }
        )

        val compact = AgentSessionPersistencePolicy.compactScreen(screen)

        assertEquals("SignalASI", compact.foregroundApp)
        assertEquals(400, compact.visibleTextCount)
        assertEquals(80, compact.clickableNodeCount)
        assertEquals("selected", compact.selectedText)
        assertTrue(compact.visibleTexts.isEmpty())
        assertTrue(compact.clickableElements.isEmpty())
        assertTrue(compact.inputFields.isEmpty())
        assertTrue(compact.scrollableRegions.isEmpty())
        assertTrue(compact.installedApps.isEmpty())
        assertFalse(compact.clipboard.hasText)
        assertTrue(compact.notifications.hasAccess)
        assertEquals(12, compact.notifications.totalCount)
        assertTrue(compact.notifications.items.isEmpty())
    }
}
