package com.galaxyssi.chat

internal object CloudVisionPromptPolicy {
    const val DEFAULT_PROMPT =
        "You are GalaxySSI. Answer the user's current request in their language, using the supplied " +
            "images and relevant conversation context. Give the useful answer directly. " +
            "Use tools only when the task actually requires them; never claim an action without its receipt."

    fun compose(
        base: String,
        imageCount: Int,
        textOnlyEvidence: () -> String,
        annotationInstruction: String = ""
    ): String {
        if (imageCount <= 0) return base + "\n" + textOnlyEvidence()
        // Preserve custom Agent Loop contracts, but do not turn image reading into web research.
        return listOf(base, AgentDirectVisionPolicy.instructionForImageCount(imageCount), annotationInstruction)
            .filter(String::isNotBlank).joinToString("\n")
    }
}
