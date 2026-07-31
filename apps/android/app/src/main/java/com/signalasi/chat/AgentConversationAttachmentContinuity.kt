package com.signalasi.chat

import android.content.Context

internal data class AgentPriorAttachmentTurn(
    val turnId: String,
    val blocks: List<AgentRichBlock>
)

internal object AgentConversationAttachmentContinuity {
    fun resolve(
        context: Context,
        conversationId: String,
        currentTurnId: String,
        request: String
    ): List<AgentInputAttachment> {
        val selected = select(
            AgentTranscriptStore(context.applicationContext).list(conversationId),
            currentTurnId,
            request
        ) ?: return emptyList()
        return AgentAttachmentWorkspaceStager.restore(
            context.applicationContext,
            conversationId,
            selected.turnId,
            selected.blocks
        )
    }

    internal fun select(
        entries: List<AgentTranscriptEntry>,
        currentTurnId: String,
        request: String
    ): AgentPriorAttachmentTurn? {
        val candidates = entries.asReversed().mapNotNull { entry ->
            if (
                entry.role != AgentTranscriptRole.USER ||
                entry.turnId.isBlank() ||
                entry.turnId == currentTurnId
            ) return@mapNotNull null
            val blocks = AgentRichContentCodec.decode(entry.richOutputJson).filter { block ->
                block.type in ATTACHMENT_TYPES &&
                    block.metadata["source"].orEmpty() == "user_attachment"
            }
            blocks.takeIf { it.isNotEmpty() }?.let {
                AgentPriorAttachmentTurn(entry.turnId, it)
            }
        }
        if (candidates.isEmpty()) return null
        val currentRequest = currentRequest(request)
        candidates.firstOrNull { candidate ->
            candidate.blocks.any { block ->
                val name = block.title.trim()
                name.isNotBlank() && currentRequest.contains(name, ignoreCase = true)
            }
        }?.let { return it }
        return candidates.firstOrNull()?.takeIf {
            referencesPriorArtifact(currentRequest)
        }
    }

    internal fun referencesPriorArtifact(request: String): Boolean {
        val normalized = request.trim().lowercase().split(Regex("\\s+")).joinToString(" ")
        if (normalized.isBlank()) return false
        return CONTINUATION_TERMS.any { term -> containsTerm(normalized, term) }
    }

    private fun currentRequest(value: String): String {
        val explicit = value.substringAfterLast(CURRENT_REQUEST_MARKER, "")
        if (explicit.isNotBlank()) return explicit.trim()
        val contextEnd = value.lastIndexOf(AgentTranscriptStore.SIGNALASI_CONTEXT_TRANSPORT_FOOTER)
        if (contextEnd >= 0) {
            return value.substring(
                contextEnd + AgentTranscriptStore.SIGNALASI_CONTEXT_TRANSPORT_FOOTER.length
            ).trim()
        }
        return value.trim()
    }

    private fun containsTerm(content: String, term: String): Boolean {
        if (!term.isAsciiWord()) return term in content
        return Regex("(?<![a-z0-9])${Regex.escape(term)}(?![a-z0-9])").containsMatchIn(content)
    }

    private fun String.isAsciiWord(): Boolean = isNotBlank() && all { it in 'a'..'z' }

    private const val CURRENT_REQUEST_MARKER = "Current user request:"
    private val ATTACHMENT_TYPES = setOf(
        AgentRichBlockType.IMAGE,
        AgentRichBlockType.FILE,
        AgentRichBlockType.VIDEO,
        AgentRichBlockType.AUDIO
    )
    private val CONTINUATION_TERMS = listOf(
        "continue", "again", "same", "previous", "above", "this", "that", "it",
        "modify", "edit", "revise", "change", "correct", "fix", "improve",
        "annotate", "mark", "redo", "regenerate", "return", "send", "save",
        "download", "export", "open", "inspect", "analyze", "summarize",
        "translate", "crop", "rotate", "resize", "compress", "every", "each",
        "all", "image", "photo", "file", "document", "attachment", "answer",
        "question",
        "\u7ee7\u7eed", "\u518d", "\u540c\u4e00", "\u4e0a\u4e00",
        "\u4e4b\u524d", "\u521a\u624d", "\u8fd9", "\u90a3",
        "\u4fee\u6539", "\u6539", "\u4fee\u6b63", "\u6279\u6539",
        "\u6807\u6ce8", "\u91cd\u505a", "\u91cd\u65b0", "\u4f18\u5316",
        "\u4ed4\u7ec6", "\u6b63\u786e", "\u6bcf\u4e00", "\u9010\u4e00",
        "\u5168\u90e8", "\u90fd", "\u539f\u56fe", "\u56fe\u7247",
        "\u7167\u7247", "\u6587\u4ef6", "\u6587\u6863", "\u9644\u4ef6",
        "\u7b54\u6848", "\u95ee\u9898", "\u53d1\u56de", "\u4fdd\u5b58",
        "\u4e0b\u8f7d", "\u5bfc\u51fa", "\u6253\u5f00", "\u67e5\u770b",
        "\u5206\u6790", "\u603b\u7ed3", "\u7ffb\u8bd1", "\u88c1\u526a",
        "\u65cb\u8f6c", "\u653e\u5927", "\u7f29\u5c0f", "\u538b\u7f29"
    )
}
