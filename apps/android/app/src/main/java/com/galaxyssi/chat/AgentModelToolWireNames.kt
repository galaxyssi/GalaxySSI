package com.galaxyssi.chat

/** HTTP function names are representations; native IDs remain the journal and execution identity. */
internal object AgentModelToolWireNames {
    const val MAX_CHARACTERS = 64

    fun name(nativeId: String): String {
        require(AgentNativeToolDescriptor.isValidId(nativeId)) { "Invalid native tool identifier" }
        val escaped = buildString {
            nativeId.forEach { character ->
                when (character) {
                    '.' -> append("__")
                    '_' -> append("_u")
                    else -> append(character)
                }
            }
        }
        if (escaped.length <= MAX_CHARACTERS) return escaped
        // Short escaped names cannot contain `_h`, keeping this fallback namespace disjoint.
        return "gssi_h_" + AgentNativeJsonCodec.sha256(nativeId).take(56)
    }
}
