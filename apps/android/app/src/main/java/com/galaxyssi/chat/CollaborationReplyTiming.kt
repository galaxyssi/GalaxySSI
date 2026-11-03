package com.galaxyssi.chat

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

internal object CollaborationReplyTiming {
    fun executionStart(events: List<AgentSubagentEvent>, result: AgentSubagentChildResult?): Long =
        events.filter { it.kind == AgentSubagentEventKinds.CHILD_RUNNING && it.timestampMillis > 0L }
            .maxByOrNull(AgentSubagentEvent::sequence)?.timestampMillis
            ?: result?.startedAtMillis?.coerceAtLeast(0L) ?: 0L

    fun replyAt(metadata: CollaborationTranscriptMetadata, entryTimestamp: Long): Long =
        if (metadata.result) metadata.completedAtMillis.takeIf { it > 0L } ?: entryTimestamp.coerceAtLeast(0L) else 0L

    fun isTicking(metadata: CollaborationTranscriptMetadata): Boolean =
        metadata.startedAtMillis > 0L && metadata.completedAtMillis <= 0L && metadata.clockStoppedAtMillis <= 0L &&
            metadata.status == AgentSubagentStatus.RUNNING && !metadata.result && !metadata.paused

    /** Elapsed time includes transport waits, but never borrows another member's start time. */
    fun elapsedMillis(metadata: CollaborationTranscriptMetadata, entryTimestamp: Long, nowMillis: Long): Long? {
        if (metadata.startedAtMillis <= 0L) return null
        val end = when {
            metadata.completedAtMillis > 0L -> metadata.completedAtMillis
            metadata.result -> entryTimestamp.takeIf { it > 0L } ?: return null
            metadata.clockStoppedAtMillis > 0L -> metadata.clockStoppedAtMillis
            isTicking(metadata) -> nowMillis
            else -> return null
        }
        return (end - metadata.startedAtMillis).coerceAtLeast(0L)
    }

    fun formatReplyTime(timestampMillis: Long, nowMillis: Long, zone: ZoneId = ZoneId.systemDefault(),
        locale: Locale = Locale.getDefault()): String {
        if (timestampMillis <= 0L) return ""
        val reply = Instant.ofEpochMilli(timestampMillis).atZone(zone)
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone)
        val pattern = when {
            reply.toLocalDate() == now.toLocalDate() -> "HH:mm"
            reply.year == now.year -> "MM-dd HH:mm"
            else -> "yyyy-MM-dd HH:mm"
        }
        return reply.format(DateTimeFormatter.ofPattern(pattern, locale))
    }
}
