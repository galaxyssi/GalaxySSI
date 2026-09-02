package com.signalasi.chat

internal data class AgentConversationVisualReference(
    val turnId: String,
    val blocks: List<AgentRichBlock>
)

/** Keeps recent user images available to a multimodal follow-up without duplicating its chat bubble. */
internal object AgentConversationVisualContext {
    fun latest(context: AgentConversationContext?): AgentConversationVisualReference? =
        latest(context?.turns.orEmpty())

    fun latest(entries: List<AgentTranscriptEntry>): AgentConversationVisualReference? = entries
        .asReversed()
        .asSequence()
        .filter { entry -> entry.role == AgentTranscriptRole.USER && entry.turnId.isNotBlank() }
        .mapNotNull { entry ->
            val images = AgentRichContentCodec.decode(entry.richOutputJson)
                .filter { block ->
                    block.type == AgentRichBlockType.IMAGE &&
                        block.metadata["source"].orEmpty() == "user_attachment"
                }
            images.takeIf { it.isNotEmpty() }?.let { blocks ->
                AgentConversationVisualReference(entry.turnId, blocks)
            }
        }
        .firstOrNull()
}
