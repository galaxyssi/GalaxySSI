package com.galaxyssi.chat

import java.io.IOException
import java.util.concurrent.TimeUnit

internal object AgentWebRendererProcessPolicy {
    const val DIRECTORY_SUFFIX = "agent_web_renderer"
    fun isRenderer(packageName: String, processName: String): Boolean =
        processName == "$packageName:web_renderer"
}

internal class AgentWebRendererUnavailableException(reason: String) : IOException(reason)

/** A broken process should not be restarted for every URL in the same research pass. */
internal class AgentWebRendererHealth(
    private val nowNs: () -> Long = System::nanoTime,
    private val cooldownNs: Long = TimeUnit.SECONDS.toNanos(30)
) {
    private var failedAt: Long? = null

    @Synchronized fun checkAvailable() {
        failedAt?.let {
            if (nowNs() - it < cooldownNs) {
                throw AgentWebRendererUnavailableException("renderer_temporarily_unavailable")
            }
            failedAt = null
        }
    }

    @Synchronized fun failed() { failedAt = nowNs() }
    @Synchronized fun succeeded() { failedAt = null }
}
