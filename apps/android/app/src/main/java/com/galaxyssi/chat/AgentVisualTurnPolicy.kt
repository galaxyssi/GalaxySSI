package com.galaxyssi.chat

/** Keep transport replay separate from what the user actually supplied in this turn. */
internal object AgentVisualTurnPolicy {
    const val ANSWER_STYLE =
        "Check image orientation internally when needed. Do not prefix replies with image orientation, " +
            "rotation angles, or a reading/transcription report. Mention them only when the user asks " +
            "or a specific ambiguity matters to the answer. Answer the current question directly."

    const val HISTORICAL_CONTEXT =
        "These are historical image references from earlier user turns, not newly uploaded images. " +
            "Use them only if relevant to the current request. A text follow-up does not restart the " +
            "earlier image task. Do not repeat an earlier reading or answer format; resolve references " +
            "from the conversation and answer the latest request. If the topic changes, ignore unrelated images."

    fun historyLabel(sourceTurnId: String): String =
        "Historical image reference (source user turn: ${sourceTurnId.filter { it.isLetterOrDigit() || it in "-_.:" }.take(128)}). " +
            HISTORICAL_CONTEXT

    fun instruction(attachments: List<AgentInputAttachment>): String {
        val currentImages = attachments.count { it.isImage && !it.isHistoricalReference }
        val historicalImages = attachments.any { it.isImage && it.isHistoricalReference }
        return buildList {
            if (currentImages > 0) add(AgentDirectVisionPolicy.instructionForImageCount(currentImages))
            if (historicalImages) {
                add(HISTORICAL_CONTEXT)
                add("If a question requires the original image, inspect its native pixels rather than trusting an earlier assistant guess.")
                if (currentImages == 0) add(ANSWER_STYLE)
            }
        }.joinToString("\n")
    }
}
