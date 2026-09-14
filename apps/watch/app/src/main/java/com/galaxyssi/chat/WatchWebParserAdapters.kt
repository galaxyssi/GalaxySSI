package com.galaxyssi.chat

/** Small dependencies for the shared phone parser without the phone's agent runtime. */
internal class AgentWebMediaException(code: String, message: String, val retryable: Boolean) : Exception("$code: $message")
internal object AgentWebIntelligenceText {
    // Preserve the destination hostname; source links are displayed, never fetched automatically.
    fun canonicalUrl(value: String): String = java.net.URI(value).normalize().toString()
}
