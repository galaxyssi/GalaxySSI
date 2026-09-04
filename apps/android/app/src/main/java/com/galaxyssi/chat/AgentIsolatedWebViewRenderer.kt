package com.galaxyssi.chat

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import java.io.File
import java.net.InetAddress
import java.net.URI
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

internal object AgentWebRenderContract {
    const val MSG_RENDER = 1
    const val MSG_CANCEL = 2
    const val KEY_REQUEST_ID = "request_id"
    const val KEY_URL = "url"
    const val KEY_TIMEOUT_MILLIS = "timeout_millis"
    const val KEY_MAX_BYTES = "max_bytes"
    const val KEY_STATUS = "status"
    const val KEY_FINAL_URL = "final_url"
    const val KEY_CONTENT_TYPE = "content_type"
    const val KEY_FILE_PATH = "file_path"
    const val KEY_DURATION_MILLIS = "duration_millis"
    const val KEY_ERROR = "error"
    const val STATUS_COMPLETED = "completed"
    const val STATUS_FAILED = "failed"
    const val CACHE_DIRECTORY = "agent-web-render"
}

/** Synchronous client for the private WebView renderer process. */
class AgentIsolatedWebViewRenderer(context: Context) : AgentDynamicWebRenderer {
    private val appContext = context.applicationContext

    override fun render(
        url: String,
        maxBytes: Long,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): AgentWebIntelligenceFetched {
        check(Looper.myLooper() != Looper.getMainLooper()) {
            "Dynamic rendering must run outside the Android main thread"
        }
        require(AgentWebRenderUrlPolicy.allows(url)) { "Dynamic rendering requires a public HTTPS URL" }
        require(AgentWebRenderUrlPolicy.resolvesToPublicAddress(url)) {
            "Dynamic rendering requires a public network destination"
        }
        val boundedTimeout = timeoutMillis.coerceIn(1_000L, 60_000L)
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(boundedTimeout)
        acquireRenderer(deadline, cancellationToken, checkpoint)
        val requestId = UUID.randomUUID().toString()
        val service = AtomicReference<Messenger?>()
        val connected = ArrayBlockingQueue<Boolean>(1)
        val result = ArrayBlockingQueue<Bundle>(1)
        val bound = AtomicBoolean(false)
        val reply = Messenger(Handler(Looper.getMainLooper()) { message ->
            result.offer(Bundle(message.data))
            true
        })
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                service.set(binder?.let(::Messenger))
                connected.offer(binder != null)
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                service.set(null)
                result.offer(Bundle().apply {
                    putString(AgentWebRenderContract.KEY_STATUS, AgentWebRenderContract.STATUS_FAILED)
                    putString(AgentWebRenderContract.KEY_ERROR, "renderer_process_disconnected")
                })
            }
        }
        try {
            val intent = Intent(appContext, AgentIsolatedWebRenderService::class.java)
            bound.set(appContext.bindService(intent, connection, Context.BIND_AUTO_CREATE))
            if (!bound.get()) error("renderer_bind_failed")
            awaitConnection(connected, deadline, cancellationToken, checkpoint)
            val remote = service.get() ?: error("renderer_connection_unavailable")
            val cancellation = cancellationToken.invokeOnCancellation {
                sendCancel(remote, requestId)
            }
            try {
                remote.send(Message.obtain(null, AgentWebRenderContract.MSG_RENDER).apply {
                    replyTo = reply
                    data = Bundle().apply {
                        putString(AgentWebRenderContract.KEY_REQUEST_ID, requestId)
                        putString(AgentWebRenderContract.KEY_URL, url)
                        putLong(AgentWebRenderContract.KEY_TIMEOUT_MILLIS, boundedTimeout)
                        putLong(AgentWebRenderContract.KEY_MAX_BYTES, maxBytes)
                    }
                })
                val response = awaitResult(result, deadline, cancellationToken, checkpoint)
                if (response.getString(AgentWebRenderContract.KEY_STATUS) != AgentWebRenderContract.STATUS_COMPLETED) {
                    error(response.getString(AgentWebRenderContract.KEY_ERROR).orEmpty().ifBlank { "renderer_failed" })
                }
                return readRenderedResult(response, maxBytes)
            } finally {
                cancellation.dispose()
                sendCancel(remote, requestId)
            }
        } finally {
            if (bound.get()) runCatching { appContext.unbindService(connection) }
            RENDER_GATE.release()
        }
    }

    private fun readRenderedResult(response: Bundle, maxBytes: Long): AgentWebIntelligenceFetched {
        val root = File(appContext.cacheDir, AgentWebRenderContract.CACHE_DIRECTORY).canonicalFile
        val file = File(response.getString(AgentWebRenderContract.KEY_FILE_PATH).orEmpty()).canonicalFile
        check(file.path.startsWith(root.path + File.separator)) { "renderer_result_outside_cache" }
        return try {
            check(file.isFile) { "renderer_result_missing" }
            check(file.length() in 1..maxBytes) { "renderer_result_too_large" }
            val bytes = file.readBytes()
            check(bytes.size.toLong() <= maxBytes) { "renderer_result_too_large" }
            AgentWebIntelligenceFetched(
                url = response.getString(AgentWebRenderContract.KEY_FINAL_URL).orEmpty(),
                contentType = response.getString(AgentWebRenderContract.KEY_CONTENT_TYPE)
                    .orEmpty().ifBlank { "text/html; charset=utf-8" },
                body = bytes,
                durationMillis = response.getLong(AgentWebRenderContract.KEY_DURATION_MILLIS)
            )
        } finally {
            file.delete()
        }
    }

    private fun acquireRenderer(
        deadline: Long,
        token: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ) {
        while (true) {
            if (token.isCancellationRequested) throw AgentNativeToolCancelledException()
            checkpoint()
            val remaining = remainingMillis(deadline)
            if (remaining <= 0L) throw AgentNativeToolTimeoutException()
            if (RENDER_GATE.tryAcquire(remaining.coerceAtMost(100L), TimeUnit.MILLISECONDS)) return
        }
    }

    private fun awaitConnection(
        queue: ArrayBlockingQueue<Boolean>,
        deadline: Long,
        token: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ) {
        while (true) {
            if (token.isCancellationRequested) throw AgentNativeToolCancelledException()
            checkpoint()
            val remaining = remainingMillis(deadline)
            if (remaining <= 0L) throw AgentNativeToolTimeoutException()
            queue.poll(remaining.coerceAtMost(100L), TimeUnit.MILLISECONDS)?.let { connected ->
                check(connected) { "renderer_connection_failed" }
                return
            }
        }
    }

    private fun awaitResult(
        queue: ArrayBlockingQueue<Bundle>,
        deadline: Long,
        token: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): Bundle {
        while (true) {
            if (token.isCancellationRequested) throw AgentNativeToolCancelledException()
            checkpoint()
            val remaining = remainingMillis(deadline)
            if (remaining <= 0L) throw AgentNativeToolTimeoutException()
            queue.poll(remaining.coerceAtMost(100L), TimeUnit.MILLISECONDS)?.let { return it }
        }
    }

    private fun sendCancel(remote: Messenger, requestId: String) {
        runCatching {
            remote.send(Message.obtain(null, AgentWebRenderContract.MSG_CANCEL).apply {
                data = Bundle().apply { putString(AgentWebRenderContract.KEY_REQUEST_ID, requestId) }
            })
        }
    }

    private fun remainingMillis(deadline: Long): Long = TimeUnit.NANOSECONDS
        .toMillis(deadline - System.nanoTime())
        .coerceAtLeast(0L)

    private companion object {
        val RENDER_GATE = Semaphore(1, true)
    }
}

internal object AgentWebRenderUrlPolicy {
    fun allows(value: String): Boolean = runCatching {
        val uri = URI(value.trim())
        if (!uri.scheme.equals("https", true)) return false
        if (!uri.userInfo.isNullOrBlank()) return false
        val host = uri.host?.lowercase().orEmpty()
        if (host.isBlank() || host == "localhost" || host.endsWith(".localhost") || host.endsWith(".local")) {
            return false
        }
        if (host.contains(':') || IPV4.matches(host)) {
            val address = InetAddress.getByName(host)
            return AgentPublicAddressPolicy.isPublic(address)
        }
        true
    }.getOrDefault(false)

    fun resolvesToPublicAddress(value: String): Boolean = runCatching {
        if (!allows(value)) return false
        val host = URI(value.trim()).host?.removePrefix("[")?.removeSuffix("]").orEmpty()
        val addresses = InetAddress.getAllByName(host)
        addresses.isNotEmpty() && addresses.all(AgentPublicAddressPolicy::isPublic)
    }.getOrDefault(false)

    fun allowsSubresource(value: String): Boolean = runCatching {
        when (URI(value.trim()).scheme?.lowercase()) {
            "data", "blob", "about" -> true
            "https" -> allows(value)
            else -> false
        }
    }.getOrDefault(false)

    fun sameOrigin(initial: String, candidate: String): Boolean = runCatching {
        val first = URI(initial)
        val second = URI(candidate)
        allows(candidate) && first.scheme.equals(second.scheme, true) &&
            first.host.equals(second.host, true) && normalizedPort(first) == normalizedPort(second)
    }.getOrDefault(false)

    private fun normalizedPort(uri: URI): Int = uri.port.takeIf { it >= 0 } ?: 443
    private val IPV4 = Regex("(?:\\d{1,3}\\.){3}\\d{1,3}")
}
