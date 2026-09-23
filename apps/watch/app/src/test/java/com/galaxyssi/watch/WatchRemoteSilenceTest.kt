package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchRemoteSilenceTest {
    private val sentAt = 1_800_000_000_000L
    private fun task() = WatchTask.create("desktop", "route", "agent", "hello").copy(sourceId = sentAt)

    @Test fun stopsOnlyAfterFiveMinutesAndThreeChecks() {
        val lease = WatchRemoteSilence()
        val task = task()
        assertFalse(lease.expired(task, sentAt))
        assertFalse(lease.expired(task, sentAt + 30_000))
        assertFalse(lease.expired(task, sentAt + 299_999))
        assertTrue(lease.expired(task, sentAt + 300_000))
    }

    @Test fun authenticatedProgressRenewsLease() {
        val lease = WatchRemoteSilence()
        val task = task()
        assertFalse(lease.expired(task, sentAt + 290_000))
        val updated = task.copy(state = TaskState.RUNNING, remoteObservedAt = sentAt + 299_000)
        assertFalse(lease.expired(updated, sentAt + 301_000))
        assertFalse(lease.expired(updated, sentAt + 331_000))
        assertFalse(lease.expired(updated, sentAt + 598_999))
        assertTrue(lease.expired(updated, sentAt + 600_000))
    }

    @Test fun timeoutFieldsSurviveHistoryReload() {
        val task = task().copy(state = TaskState.FAILED, localTimedOut = true,
            remoteObservedAt = sentAt + 100_000)
        assertEquals(task, WatchTask.fromJson(task.json()))
        assertFalse(WatchRemoteSilence().expired(task, sentAt + 1_000_000))
    }
}
