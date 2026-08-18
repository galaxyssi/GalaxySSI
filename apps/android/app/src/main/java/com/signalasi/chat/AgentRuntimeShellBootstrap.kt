package com.signalasi.chat

/** Prepares process-local directories before any shell tool runs in phone Linux. */
internal object AgentRuntimeShellBootstrap {
    fun wrap(source: String, guestToolBin: String): String = buildString {
        append("export PATH=")
        append(shellSingleQuote(guestToolBin))
        append(":${'$'}PATH\n")
        append("test -d \"${'$'}HOME\" || mkdir -p \"${'$'}HOME\"\n")
        append("test -d \"${'$'}TMPDIR\" || mkdir -p \"${'$'}TMPDIR\"\n")
        append(source)
    }
}
