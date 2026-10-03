package com.galaxyssi.chat

import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import org.junit.Assert.*
import org.junit.Test

class CollaborationReplyTimingTest {
    private fun metadata() = CollaborationTranscriptMetadata("member", "Turing", "Codex", "Reviewer",
        AgentSubagentStatus.RUNNING, "run", startedAtMillis = 1_000L)
    private fun at(value: String) = Instant.parse(value).toEpochMilli()
    private fun format(reply: String, now: String, zone: String = "Asia/Shanghai") =
        CollaborationReplyTiming.formatReplyTime(at(reply), at(now), ZoneId.of(zone), Locale.US)

    @Test fun sameDayShowsHoursAndMinutes() {
        assertEquals("17:58", format("2026-10-03T09:58:00Z", "2026-10-03T10:00:00Z"))
    }

    @Test fun anotherDayIncludesDate() {
        assertEquals("10-02 17:58", format("2026-10-02T09:58:00Z", "2026-10-03T10:00:00Z"))
    }

    @Test fun anotherYearIncludesYear() {
        assertEquals("2025-12-31 23:58", format("2025-12-31T15:58:00Z", "2026-01-01T01:00:00Z"))
    }

    @Test fun dayComparisonUsesUsersTimezone() {
        assertEquals("16:30", format("2026-10-03T23:30:00Z", "2026-10-04T01:00:00Z", "America/Los_Angeles"))
        assertEquals("07:30", format("2026-10-03T23:30:00Z", "2026-10-04T01:00:00Z"))
    }

    @Test fun absentReplyTimeIsNotInvented() {
        assertEquals("", CollaborationReplyTiming.formatReplyTime(0L, 1_000L))
        assertEquals(0L, CollaborationReplyTiming.replyAt(metadata(), 9_000L))
    }

    @Test fun oldReplyUsesPersistedMessageTimestamp() {
        assertEquals(9_000L, CollaborationReplyTiming.replyAt(metadata().copy(result = true), 9_000L))
    }

    @Test fun explicitReplyTimeSurvivesCanonicalMessageRecreation() {
        val done = metadata().copy(result = true, completedAtMillis = 6_000L)
        assertEquals(6_000L, CollaborationReplyTiming.replyAt(done, 99_000L))
    }

    @Test fun runningElapsedUsesPersistedStartAcrossRebinding() {
        val saved = CollaborationTranscriptMetadata.decode(metadata().encode())!!
        assertTrue(CollaborationReplyTiming.isTicking(saved))
        assertEquals(4_000L, CollaborationReplyTiming.elapsedMillis(saved, 100L, 5_000L))
        assertEquals(9_000L, CollaborationReplyTiming.elapsedMillis(saved, 100L, 10_000L))
    }

    @Test fun completedDurationDoesNotChangeWithNowOrEntryTimestamp() {
        val done = metadata().copy(result = true, status = AgentSubagentStatus.SUCCEEDED, completedAtMillis = 6_000L)
        val restored = CollaborationTranscriptMetadata.decode(done.encode())!!
        assertFalse(CollaborationReplyTiming.isTicking(restored))
        assertEquals(5_000L, CollaborationReplyTiming.elapsedMillis(restored, 9_000L, 99_000L))
        assertEquals(5_000L, CollaborationReplyTiming.elapsedMillis(restored, 19_000L, 999_000L))
    }

    @Test fun oldReplyCanFreezeAtItsStoredTimestampButNeverInventStart() {
        assertEquals(5_000L, CollaborationReplyTiming.elapsedMillis(metadata().copy(result = true), 6_000L, 99_000L))
        assertNull(CollaborationReplyTiming.elapsedMillis(metadata().copy(result = true, startedAtMillis = 0L), 6_000L, 99_000L))
    }

    @Test fun pausedAndInterruptedClocksStayFrozen() {
        val paused = metadata().copy(paused = true, clockStoppedAtMillis = 7_000L)
        assertFalse(CollaborationReplyTiming.isTicking(paused))
        assertEquals(6_000L, CollaborationReplyTiming.elapsedMillis(paused, 100L, 99_000L))
        assertEquals(6_000L, CollaborationReplyTiming.elapsedMillis(paused.copy(paused = false), 100L, 999_000L))
    }

    @Test fun queuedFailedAndCancelledWithoutKnownEndNeverTick() {
        listOf(AgentSubagentStatus.QUEUED, AgentSubagentStatus.FAILED, AgentSubagentStatus.CANCELLED,
            AgentSubagentStatus.SKIPPED).forEach { status ->
            val value = metadata().copy(status = status)
            assertFalse(CollaborationReplyTiming.isTicking(value))
            assertNull(CollaborationReplyTiming.elapsedMillis(value, 100L, 99_000L))
        }
    }

    @Test fun clockSkewCannotProduceNegativeDuration() {
        assertEquals(0L, CollaborationReplyTiming.elapsedMillis(metadata(), 100L, 500L))
    }

    @Test fun metadataRetainsAllClockFields() {
        val value = metadata().copy(completedAtMillis = 6_000L, clockStoppedAtMillis = 5_000L)
        assertEquals(value, CollaborationTranscriptMetadata.decode(value.encode()))
    }

    @Test fun legacyMetadataDoesNotAssumeItStartedAtTheGroupCreation() {
        val json = org.json.JSONObject(metadata().encode()).apply {
            remove("started_at_millis"); remove("completed_at_millis"); remove("clock_stopped_at_millis")
        }
        val value = CollaborationTranscriptMetadata.decode(json.toString())!!
        assertEquals(0L, value.startedAtMillis)
        assertFalse(CollaborationReplyTiming.isTicking(value))
    }

    @Test fun executionStartComesFromLatestRunningEventNotQueueOrProgress() {
        fun event(sequence: Long, kind: String, timestamp: Long) = AgentSubagentEvent(sequence, "run", "member",
            kind, timestampMillis = timestamp)
        val events = listOf(event(1L, "queued", 500L), event(2L, AgentSubagentEventKinds.CHILD_RUNNING, 1_000L),
            event(3L, AgentSubagentEventKinds.CHILD_RUNNING, 7_000L), event(4L, "progress", 9_000L))
        assertEquals(7_000L, CollaborationReplyTiming.executionStart(events, null))
        assertEquals(0L, CollaborationReplyTiming.executionStart(emptyList(), null))
    }
}
