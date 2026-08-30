package com.signalasi.chat

import android.text.Annotation
import android.text.Editable
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.graphics.Typeface
import java.util.concurrent.ConcurrentHashMap

internal const val AGENT_MENTION_ANNOTATION_KEY = "signalasi_agent_id"

data class AgentRequestedMember(
    val agentId: String,
    val displayName: String,
    val occurrence: Int = 1,
    val roleHint: String = ""
) {
    val instanceId: String
        get() = "$agentId:mention-$occurrence".take(96)
}

internal object AgentMentionText {
    fun insert(
        editable: Editable,
        start: Int,
        end: Int,
        agentId: String,
        displayName: String,
        color: Int
    ): AgentRequestedMember {
        require(start in 0..end && end <= editable.length)
        val occurrence = selections(editable).count { it.agentId == agentId } + 1
        val visibleName = displayName.trim().ifBlank { agentId }
        val token = if (occurrence == 1) "@$visibleName" else "@$visibleName #$occurrence"
        val styled = SpannableString("$token ").apply {
            setSpan(
                Annotation(AGENT_MENTION_ANNOTATION_KEY, agentId),
                0,
                token.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            setSpan(
                ForegroundColorSpan(color),
                0,
                token.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            setSpan(
                StyleSpan(Typeface.BOLD),
                0,
                token.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        editable.replace(start, end, styled)
        return AgentRequestedMember(agentId, visibleName, occurrence)
    }

    fun selections(text: Spanned): List<AgentRequestedMember> {
        val occurrences = linkedMapOf<String, Int>()
        val annotations = text.getSpans(0, text.length, Annotation::class.java)
            .filter { annotation -> annotation.key == AGENT_MENTION_ANNOTATION_KEY }
            .sortedBy(text::getSpanStart)
        return annotations.mapIndexedNotNull { index, annotation ->
                val start = text.getSpanStart(annotation)
                val end = text.getSpanEnd(annotation)
                val agentId = annotation.value.trim()
                if (start < 0 || end <= start || agentId.isBlank()) return@mapIndexedNotNull null
                val occurrence = (occurrences[agentId] ?: 0) + 1
                occurrences[agentId] = occurrence
                val label = text.subSequence(start, end).toString()
                    .removePrefix("@")
                    .replace(Regex("\\s+#\\d+$"), "")
                    .trim()
                    .ifBlank { agentId }
                val roleEnd = annotations.getOrNull(index + 1)
                    ?.let(text::getSpanStart)
                    ?.takeIf { it > end }
                    ?: text.length
                val roleHint = text.subSequence(end, roleEnd).toString()
                    .trim(' ', '\n', '\r', '\t', ',', '，', ':', '：', ';', '；')
                    .take(MAX_ROLE_HINT_CHARACTERS)
                AgentRequestedMember(agentId, label, occurrence, roleHint)
            }
    }
}

internal object AgentTurnMentionRegistry {
    private val selections = ConcurrentHashMap<String, List<AgentRequestedMember>>()

    fun put(turnId: String, members: List<AgentRequestedMember>) {
        if (turnId.isBlank() || members.isEmpty()) return
        selections[turnId] = members.take(MAX_MEMBERS)
    }

    fun peek(turnId: String): List<AgentRequestedMember> = selections[turnId].orEmpty()

    fun take(turnId: String): List<AgentRequestedMember> = selections.remove(turnId).orEmpty()

    fun remove(turnId: String) {
        selections.remove(turnId)
    }

    private const val MAX_MEMBERS = 12
}

private const val MAX_ROLE_HINT_CHARACTERS = 240
