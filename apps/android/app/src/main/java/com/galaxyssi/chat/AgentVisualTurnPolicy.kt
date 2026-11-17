package com.galaxyssi.chat

/** Keep transport replay separate from what the user actually supplied in this turn. */
internal object AgentVisualTurnPolicy {
    const val ATTACHED_INPUT_HEADER = "Attached input:"
    const val HISTORICAL_INPUT_HEADER = "Historical visual context (no new attachment in this turn):"

    const val ANSWER_STYLE =
        "Check image orientation internally when needed. Do not prefix replies with image orientation, " +
            "rotation angles, or a reading/transcription report. Mention them only when the user asks " +
            "or a specific ambiguity matters to the answer. Answer the current question directly."

    const val HISTORICAL_CONTEXT =
        "These are historical image references from earlier user turns, not newly uploaded images. " +
            "Use them only if relevant to the current request. A text follow-up does not restart the " +
            "earlier image task. Do not repeat an earlier reading or answer format; resolve references " +
            "from the conversation and answer the latest request. If the topic changes, ignore unrelated images."

    private const val CHECK_HISTORICAL_PIXELS =
        "If a question requires the original image, inspect its native pixels rather than trusting an earlier assistant guess."

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
                add(CHECK_HISTORICAL_PIXELS)
                if (currentImages == 0) add(ANSWER_STYLE)
            }
        }.joinToString("\n")
    }

    fun goalWithAttachmentEvidence(
        userGoal: String,
        attachments: List<AgentInputAttachment>,
        evidence: String
    ): String = buildString {
        val historicalOnly = attachments.all { it.isHistoricalReference }
        append(userGoal).append("\n\n")
        append(if (historicalOnly) HISTORICAL_INPUT_HEADER else ATTACHED_INPUT_HEADER).append('\n')
        append(evidence)
        instruction(attachments).takeIf(String::isNotBlank)?.let { append("\n\n").append(it) }
        if (!historicalOnly) {
            append("\nInspect the newly attached content in light of the user's current request. ")
            append("If only a new image was sent, infer and complete the most helpful relevant task.")
        }
    }

    // Older checkpoints placed the visual guide immediately before the attachment header.
    fun userGoalBeforeAttachmentEvidence(prefix: String): String {
        val header = when {
            prefix.endsWith(HISTORICAL_INPUT_HEADER) -> HISTORICAL_INPUT_HEADER
            prefix.endsWith(ATTACHED_INPUT_HEADER) -> ATTACHED_INPUT_HEADER
            else -> return prefix
        }
        val goal = prefix.removeSuffix(header).trimEnd()
        if (!goal.endsWith(ANSWER_STYLE) && !goal.endsWith(CHECK_HISTORICAL_PIXELS)) return goal
        val historical = "$HISTORICAL_CONTEXT\n$CHECK_HISTORICAL_PIXELS"
        val current = AgentDirectVisionPolicy.instructionForImageCount(1)
        return goal.removeSuffix("\n\n$current\n$historical")
            .removeSuffix("\n\n$historical\n$ANSWER_STYLE")
            .removeSuffix("\n\n$current")
    }
}
