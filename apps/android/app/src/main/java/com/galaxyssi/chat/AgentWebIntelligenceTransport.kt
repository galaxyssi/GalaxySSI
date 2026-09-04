package com.galaxyssi.chat

data class AgentWebIntelligenceFetched(
    val url: String,
    val contentType: String,
    val body: ByteArray,
    val durationMillis: Long = 0L,
    val fetchTier: String = "",
    val dynamicFallbackReason: String = "",
    val dynamicFallbackError: String = ""
)

fun interface AgentWebIntelligenceFetcher {
    fun fetch(
        url: String,
        maxBytes: Long,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): AgentWebIntelligenceFetched
}

fun interface AgentWebIntelligenceRequestFetcher {
    fun fetch(
        url: String,
        maxBytes: Long,
        timeoutMillis: Long,
        headers: Map<String, String>,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): AgentWebIntelligenceFetched
}

fun interface AgentWebIntelligenceCredentialProvider {
    fun credential(key: String): String

    companion object {
        val NONE = AgentWebIntelligenceCredentialProvider { "" }
    }
}

class AgentBoundedWebIntelligenceFetcher(
    private val web: AgentBoundedWebService
) : AgentWebIntelligenceFetcher, AgentWebIntelligenceRequestFetcher {
    override fun fetch(
        url: String,
        maxBytes: Long,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): AgentWebIntelligenceFetched = fetch(
        url,
        maxBytes,
        timeoutMillis,
        emptyMap(),
        cancellationToken,
        checkpoint
    )

    override fun fetch(
        url: String,
        maxBytes: Long,
        timeoutMillis: Long,
        headers: Map<String, String>,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): AgentWebIntelligenceFetched {
        val started = System.currentTimeMillis()
        val resource = web.fetch(
            url = url,
            maxBytes = maxBytes,
            timeoutMillis = timeoutMillis,
            cancellationToken = cancellationToken,
            checkpoint = checkpoint,
            headers = headers
        )
        return AgentWebIntelligenceFetched(
            url = resource.finalUrl,
            contentType = resource.contentType,
            body = resource.body,
            durationMillis = System.currentTimeMillis() - started
        )
    }
}
