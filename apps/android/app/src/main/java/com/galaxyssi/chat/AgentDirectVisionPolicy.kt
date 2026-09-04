package com.galaxyssi.chat

internal object AgentDirectVisionPolicy {
    fun instruction(attachments: List<AgentInputAttachment>): String {
        return instructionForMimeTypes(attachments.map(AgentInputAttachment::mimeType))
    }

    internal fun instructionForMimeTypes(mimeTypes: List<String>): String {
        if (mimeTypes.none { it.startsWith("image/", ignoreCase = true) }) return ""
        return """
            Use each attached image as native visual model input. Do not replace it with locally
            extracted text or use a text-extraction pipeline to identify the object. Before answering,
            inspect the image twice: first determine the overall object and scene; then verify every
            category, brand, model, or product claim against the visible shape, logos, and readable
            text. Do not infer a product from packaging color or isolated words. Treat unrelated prior
            images and memories as non-evidence. If visible evidence conflicts or is insufficient,
            give only the supported broader identification and clearly state the uncertainty.
        """.trimIndent()
    }
}
