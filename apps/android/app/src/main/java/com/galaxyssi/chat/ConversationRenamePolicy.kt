package com.galaxyssi.chat

internal object ConversationRenamePolicy {
    // Agent transcript titles are stored with the same UTF-16 character limit.
    const val MAX_CHARACTERS = 72

    fun normalize(value: String): String? = value.trim().takeIf { name ->
        name.isNotBlank() && name.length <= MAX_CHARACTERS &&
            name.none { it.isISOControl() || it == '\u2028' || it == '\u2029' }
    }
}
