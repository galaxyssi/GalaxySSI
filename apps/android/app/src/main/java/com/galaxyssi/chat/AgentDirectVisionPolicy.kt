package com.galaxyssi.chat

internal object AgentDirectVisionPolicy {
    fun instruction(attachments: List<AgentInputAttachment>): String {
        return instructionForMimeTypes(attachments.map(AgentInputAttachment::mimeType))
    }

    internal fun instructionForMimeTypes(mimeTypes: List<String>): String {
        return instructionForImageCount(mimeTypes.count { it.startsWith("image/", ignoreCase = true) })
    }

    internal fun instructionForImageCount(imageCount: Int): String {
        if (imageCount <= 0) return ""
        return """
            Use each attached image as native visual model input. Do not replace it with locally
            extracted text or use a text-extraction pipeline. Before answering, inspect the image twice:
            first determine its reading orientation and overall meaning; then verify the relevant details.
            Camera photos may be sideways or upside down even when their metadata says normal. Compare
            the plausible 0, 90, 180 and 270 degree reading orientations before declaring text unreadable.
            Read handwriting, equations, tables and diagrams as connected content, not isolated strokes
            or unrelated symbols. For a readable question or calculation, state what is actually written
            and answer or solve it; distinguish an existing written answer from a blank answer to fill in.
            Follow the user's requested task. If only an image is supplied, infer its most likely useful
            purpose from the current image and complete that task instead of merely describing marks.
            For object identification, verify claims against visible shape, logos, and readable text;
            do not infer a brand or model from packaging color or isolated words. Treat unrelated prior
            images, memories and earlier model guesses as non-evidence. If content remains ambiguous
            after checking orientation and context, state the specific uncertainty without inventing
            missing text or asserting that no meaningful content exists. Do not search the web when
            the supplied image alone suffices. Keep visual checking internal and answer concisely.
        """.trimIndent()
    }
}
