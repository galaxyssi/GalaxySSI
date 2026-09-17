package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchVoiceDraftTest {
    @Test fun finalResultWaitsTwoSecondsAndIsConsumedOnlyOnce() {
        val draft = WatchVoiceDraft()
        draft.recognized("  tomorrow weather  ", 100)
        assertNull(draft.takeDue(2099))
        assertEquals("tomorrow weather", draft.takeDue(2100))
        assertNull(draft.takeDue(5000))
        assertNull(draft.take())
    }
    @Test fun InteractionOrBackgroundingPreservesDraftWithoutSendingLater() {
        val draft = WatchVoiceDraft()
        draft.recognized("news", 0)
        draft.interrupt()
        assertNull(draft.takeDue(20000))
        assertEquals("news", draft.text)
        assertEquals("news", draft.take())
        assertNull(draft.take())
    }
    @Test fun EmptyResultsAndRetryNeverSendStaleText() {
        val draft = WatchVoiceDraft()
        draft.recognized("news", 0)
        draft.clear()
        assertNull(draft.takeDue(2000))
        draft.recognized(" ", 3000)
        assertNull(draft.deadline)
        assertNull(draft.take())
        draft.recognized("weather", 5000)
        assertNull(draft.takeDue(6999))
        assertEquals("weather", draft.takeDue(7000))
    }
}
