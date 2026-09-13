package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchConversationVisibilityTest {
    private val task = WatchTask.create("api", "profile", "model", "Hello")

    @Test fun suppressesAnyTurnOfOnlyTheVisibleConversation() {
        val visibility = WatchConversationVisibility()
        visibility.show(Any(), task)
        assertTrue(visibility.isViewing(task))
        assertTrue(visibility.isViewing(task.copy(id = "next", turnId = "next-turn")))
        for (other in listOf(task.copy(conversationId = "other"), task.copy(routeId = "other"),
            task.copy(desktopId = "other"), task.copy(agentId = "other"))) {
            assertFalse(visibility.isViewing(other))
        }
    }

    @Test fun backgroundAndOtherPagesAllowNotifications() {
        val visibility = WatchConversationVisibility()
        val screen = Any()
        assertFalse(visibility.isViewing(task))
        visibility.show(screen, task)
        visibility.hide(screen)
        assertFalse(visibility.isViewing(task))
        visibility.show(screen, task)
        visibility.show(screen, null)
        assertFalse(visibility.isViewing(task))
    }

    @Test fun previousActivityCannotClearReplacementActivity() {
        val visibility = WatchConversationVisibility()
        val previous = Any(); val current = Any()
        visibility.show(previous, task)
        visibility.show(current, task)
        visibility.hide(previous)
        assertTrue(visibility.isViewing(task))
        visibility.hide(current)
        assertFalse(visibility.isViewing(task))
    }
}
