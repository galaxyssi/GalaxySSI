package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.CommittedSpeechChunk
import com.galaxyssi.chat.voice.modelstream.DefaultSentenceCommitter
import com.galaxyssi.chat.voice.modelstream.SpeechTextNormalizer

internal data class AgentReplySpeechTarget(
    val responseId: String,
    val entryId: String,
    val text: String,
    val complete: Boolean
)

internal data class AgentReplySpeechCommand(
    val cancelSessionId: String = "",
    val beginSessionId: String = "",
    val chunks: List<CommittedSpeechChunk> = emptyList(),
    val finishSessionId: String = "",
    val scheduleCommitSessionId: String = "",
    val changedEntryIds: Set<String> = emptySet()
)

internal object AgentReplySpeechPresentationPolicy {
    fun latestTarget(entries: List<AgentTranscriptEntry>): AgentReplySpeechTarget? = entries
        .asReversed()
        .asSequence()
        .filter { entry -> entry.role == AgentTranscriptRole.ASSISTANT }
        .mapNotNull(::target)
        .firstOrNull()

    fun target(entry: AgentTranscriptEntry): AgentReplySpeechTarget? {
        if (entry.role != AgentTranscriptRole.ASSISTANT ||
            entry.dedupeKey.startsWith("approval:") ||
            entry.dedupeKey.startsWith("agent-recovery:")
        ) return null
        val text = speakableText(entry)
        if (text.isBlank()) return null
        return AgentReplySpeechTarget(
            responseId = responseId(entry),
            entryId = entry.id,
            text = text,
            complete = !entry.id.startsWith("agent-stream-")
        )
    }

    fun speakableText(entry: AgentTranscriptEntry): String {
        val plain = CodexStyleResponsePolicy.sanitizeAssistantText(entry.text)
        if (plain.isNotBlank()) return plain
        return AgentRichContentCodec.decode(entry.richOutputJson)
            .mapNotNull { block ->
                when (block.type) {
                    AgentRichBlockType.TEXT,
                    AgentRichBlockType.HEADING,
                    AgentRichBlockType.QUOTE -> block.text.ifBlank { block.title }
                    AgentRichBlockType.LIST -> block.rows.joinToString("\n") { row ->
                        row.getOrNull(1).orEmpty()
                    }
                    else -> null
                }?.takeIf(String::isNotBlank)
            }
            .joinToString("\n\n")
    }

    private fun responseId(entry: AgentTranscriptEntry): String = sequenceOf(
        entry.turnId,
        entry.taskId,
        entry.dedupeKey,
        entry.id
    ).map(String::trim).first(String::isNotBlank)
}

internal class AgentReplySpeechController {
    private data class Session(
        var target: AgentReplySpeechTarget,
        var playbackSessionId: String = "",
        val committer: DefaultSentenceCommitter = DefaultSentenceCommitter(),
        var enabled: Boolean = false,
        var observedText: String = target.text,
        var deltaSequence: Long = 0L,
        var inputClosed: Boolean = false
    )

    private var active: Session? = null
    private var playbackSequence = 0L

    fun observe(target: AgentReplySpeechTarget?): AgentReplySpeechCommand {
        val previous = active
        if (target == null) {
            active = null
            return AgentReplySpeechCommand(
                cancelSessionId = previous?.takeIf(Session::enabled)?.playbackSessionId.orEmpty(),
                changedEntryIds = setOfNotNull(previous?.target?.entryId)
            )
        }
        if (previous == null || previous.target.responseId != target.responseId) {
            active = Session(target)
            return AgentReplySpeechCommand(
                cancelSessionId = previous?.takeIf(Session::enabled)?.playbackSessionId.orEmpty(),
                changedEntryIds = setOfNotNull(previous?.target?.entryId, target.entryId)
            )
        }

        val oldEntryId = previous.target.entryId
        val wasComplete = previous.target.complete
        val delta = appendedText(previous.observedText, target.text)
        previous.target = target
        previous.observedText = target.text
        val chunks = if (previous.enabled && delta.isNotEmpty() && !previous.inputClosed) {
            previous.committer.acceptDelta(previous.deltaSequence++, delta)
        } else {
            emptyList()
        }.toMutableList()
        val shouldFinish = previous.enabled && target.complete && !wasComplete && !previous.inputClosed
        if (shouldFinish) {
            chunks += previous.committer.flush()
            previous.inputClosed = true
        }
        return AgentReplySpeechCommand(
            chunks = chunks,
            finishSessionId = previous.playbackSessionId.takeIf { shouldFinish }.orEmpty(),
            scheduleCommitSessionId = previous.playbackSessionId.takeIf {
                previous.enabled && !target.complete && delta.isNotEmpty()
            }.orEmpty(),
            changedEntryIds = setOfNotNull(
                oldEntryId.takeIf { it != target.entryId },
                target.entryId.takeIf { it != oldEntryId }
            )
        )
    }

    fun toggle(target: AgentReplySpeechTarget): AgentReplySpeechCommand {
        val session = sessionFor(target)
        if (session.enabled) {
            session.enabled = false
            session.inputClosed = false
            return AgentReplySpeechCommand(
                cancelSessionId = session.playbackSessionId,
                changedEntryIds = setOf(session.target.entryId)
            )
        }
        return begin(session, target.text, target.complete)
    }

    fun readFromParagraph(
        target: AgentReplySpeechTarget,
        paragraph: String,
        sourceText: String = target.text,
        startOffset: Int = sourceText.indexOf(paragraph)
    ): AgentReplySpeechCommand {
        val speech = SpeechTextNormalizer.normalize(
            continuationFromParagraph(target.text, paragraph, sourceText, startOffset)
        )
        if (speech.isBlank()) return AgentReplySpeechCommand()
        val session = sessionFor(target)
        session.observedText = target.text
        return begin(session, speech, target.complete)
    }

    fun stop(): AgentReplySpeechCommand {
        val session = active?.takeIf(Session::enabled) ?: return AgentReplySpeechCommand()
        session.enabled = false
        session.inputClosed = false
        return AgentReplySpeechCommand(
            cancelSessionId = session.playbackSessionId,
            changedEntryIds = setOf(session.target.entryId)
        )
    }

    fun isPlaying(): Boolean = active?.enabled == true

    fun commitDue(sessionId: String): AgentReplySpeechCommand {
        val session = active?.takeIf {
            it.playbackSessionId == sessionId && it.enabled && !it.inputClosed
        } ?: return AgentReplySpeechCommand()
        val chunks = session.committer.commitDue()
        return AgentReplySpeechCommand(chunks = chunks)
    }

    fun disable(sessionId: String): Set<String> {
        val session = active?.takeIf { it.playbackSessionId == sessionId } ?: return emptySet()
        session.enabled = false
        session.inputClosed = false
        return setOf(session.target.entryId)
    }

    fun isEnabled(target: AgentReplySpeechTarget): Boolean = active?.let { session ->
        session.target.responseId == target.responseId && session.enabled
    } == true

    fun isActive(target: AgentReplySpeechTarget): Boolean =
        active?.target?.responseId == target.responseId

    private fun sessionFor(target: AgentReplySpeechTarget): Session {
        val current = active
        if (current != null && current.target.responseId == target.responseId) {
            current.target = target
            current.observedText = target.text
            return current
        }
        return Session(target).also { active = it }
    }

    private fun begin(
        session: Session,
        initialText: String,
        complete: Boolean
    ): AgentReplySpeechCommand {
        val previousPlaybackSessionId = session.playbackSessionId.takeIf { session.enabled }.orEmpty()
        session.playbackSessionId = playbackSessionId(session.target.responseId, ++playbackSequence)
        session.enabled = true
        session.inputClosed = false
        session.deltaSequence = 0L
        session.committer.reset(session.playbackSessionId)
        val chunks = session.committer.acceptDelta(session.deltaSequence++, initialText).toMutableList()
        if (complete) {
            chunks += session.committer.flush()
            session.inputClosed = true
        }
        return AgentReplySpeechCommand(
            cancelSessionId = previousPlaybackSessionId,
            beginSessionId = session.playbackSessionId,
            chunks = chunks,
            finishSessionId = session.playbackSessionId.takeIf { complete }.orEmpty(),
            scheduleCommitSessionId = session.playbackSessionId.takeUnless { complete }.orEmpty(),
            changedEntryIds = setOf(session.target.entryId)
        )
    }

    private fun appendedText(previous: String, current: String): String = when {
        current == previous -> ""
        current.startsWith(previous) -> current.substring(previous.length)
        previous.startsWith(current) -> ""
        else -> ""
    }

    private fun continuationFromParagraph(
        targetText: String,
        paragraph: String,
        sourceText: String,
        requestedStartOffset: Int
    ): String {
        val startOffset = requestedStartOffset.takeIf { it in 0..sourceText.length }
        if (startOffset != null) {
            val sourceStart = if (sourceText == targetText) {
                0
            } else {
                targetText.indexOf(sourceText).takeIf { it >= 0 }
            }
            if (sourceStart != null) {
                return targetText.substring((sourceStart + startOffset).coerceAtMost(targetText.length))
            }
        }
        val paragraphStart = targetText.indexOf(paragraph)
        return if (paragraphStart >= 0) targetText.substring(paragraphStart) else paragraph
    }

    private fun playbackSessionId(responseId: String, sequence: Long): String =
        "agent-reply-${responseId.hashCode().toUInt().toString(16)}-$sequence"
}
