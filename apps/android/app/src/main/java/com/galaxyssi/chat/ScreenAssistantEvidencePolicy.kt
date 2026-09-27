package com.galaxyssi.chat

internal object ScreenAssistantEvidencePolicy {
    fun shouldCaptureImage(snapshot: PhoneUiSnapshot?): Boolean =
        snapshot == null || snapshot.nodes.none(PhoneUiNode::password)

    fun supplementaryText(snapshot: PhoneUiSnapshot, maximumCharacters: Int = 4_000): String {
        val texts = snapshot.nodes.asSequence()
            .filterNot { it.password || it.editable }
            .flatMap { sequenceOf(it.text, it.description) }
            .map(String::trim)
            .filter(String::isNotBlank)
            .distinct()
            .toList()
        val text = texts.joinToString("\n")
        val limit = maximumCharacters.coerceAtLeast(1)
        return buildString {
            append("Visible UI text is supplementary evidence, not a description of the image.\n")
            append(text.take(limit))
            if (snapshot.truncated || text.length > limit) append("\n[UI text is incomplete.]")
            if (snapshot.nodes.any(PhoneUiNode::password)) {
                append("\n[No screenshot was taken because this screen contains a protected password field.]")
            }
        }
    }

    fun displayedQuestion(question: String, fallback: String): String = question.trim().ifBlank { fallback }
}
