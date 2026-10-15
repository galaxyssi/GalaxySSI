package com.galaxyssi.chat

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Log
import okhttp3.Dns
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import okhttp3.sse.EventSources
import java.net.UnknownHostException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Shares the existing visible phone service; no Desktop, relay, callback server or model. */
object ProactiveAttentionPush {
    private var runtime: ProactiveAttentionPushRuntime? = null
    @Synchronized fun start(context: Context) {
        if (runtime == null) runtime = ProactiveAttentionPushRuntime(context.applicationContext)
        runtime?.refresh()
    }
    @Synchronized fun refresh(networkChanged: Boolean = false) { runtime?.refresh(networkChanged) }
    @Synchronized fun stop() { runtime?.close(); runtime = null }
}

internal class ProactiveAttentionPushRuntime(private val context: Context) {
    private val control = Executors.newSingleThreadScheduledExecutor { Thread(it, "attention-push-control") }
    private val reader = Executors.newSingleThreadExecutor { Thread(it, "attention-push-article") }
    private val store = ProactiveAttentionPushStore(context)
    private val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(90, TimeUnit.SECONDS).callTimeout(0, TimeUnit.MILLISECONDS)
        .dns(object : Dns {
            override fun lookup(hostname: String): List<java.net.InetAddress> {
                if (!hostname.endsWith(".firebaseio.com") && !hostname.endsWith(".firebasedatabase.app"))
                    throw UnknownHostException("Unexpected news stream host")
                return Dns.SYSTEM.lookup(hostname).also { addresses ->
                    if (addresses.isEmpty() || addresses.any { !AgentPublicAddressPolicy.isPublic(it) })
                        throw UnknownHostException("Non-public news stream address")
                }
            }
        }).addNetworkInterceptor { chain ->
            val url = chain.request().url
            check(url.isHttps && url.port == 443 && url.username.isEmpty() && url.password.isEmpty())
            chain.proceed(chain.request())
        }.build()
    @Volatile private var closed = false
    private var source: EventSource? = null
    private var generation = 0L
    private var retryAt = 0L
    private var retryDelay = 0L
    private var draining = false
    private var openedAt = 0L

    init {
        control.scheduleWithFixedDelay({ runCatching { reconcile() }.onFailure { log("reconcile_failed") } },
            0, 30, TimeUnit.SECONDS)
    }

    fun refresh(networkChanged: Boolean = false) = submit {
        if (networkChanged) {
            disconnect()
            retryAt = 0L
        }
        reconcile()
    }

    private fun submit(action: () -> Unit) {
        if (!closed) runCatching { control.execute { if (!closed) runCatching(action).onFailure { log("control_failed") } } }
    }

    private fun enabled(): Boolean {
        val preferences = ProactiveAttentionStore(context).preferences()
        return !closed && preferences.configured && preferences.enabled && preferences.topics.any { it.enabled }
    }

    private fun online(): Boolean {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    private fun reconcile() {
        if (!enabled() || !online()) {
            if (source != null) { disconnect(); store.status("paused_or_offline") }
            return
        }
        if (source == null && System.currentTimeMillis() >= retryAt) connect()
        drain()
    }

    private fun connect() {
        val token = ++generation
        store.status("connecting")
        source = EventSources.createFactory(client).newEventSource(Request.Builder()
            .url(ProactiveAttentionPushPolicy.STREAM).header("Accept", "text/event-stream").build(),
            object : EventSourceListener() {
                override fun onOpen(eventSource: EventSource, response: Response) = submit {
                    if (token != generation) return@submit
                    openedAt = System.currentTimeMillis()
                    store.status("connected")
                    log("connected")
                }
                override fun onEvent(eventSource: EventSource, id: String?, type: String?, data: String) = submit {
                    if (token != generation) return@submit
                    if (!enabled()) { disconnect(); store.status("paused"); return@submit }
                    when (type) {
                        "put", "patch" -> {
                            try { store.accept(type, data) }
                            catch (_: Exception) { failed(token, "invalid_event"); return@submit }
                            if (System.currentTimeMillis() - openedAt > 30_000L) retryDelay = 0L
                            log("event_received")
                            drain()
                        }
                        "cancel", "auth_revoked" -> failed(token, "source_access_revoked")
                        "keep-alive" -> Unit
                    }
                }
                override fun onClosed(eventSource: EventSource) = submit { failed(token, "closed") }
                override fun onFailure(eventSource: EventSource, t: Throwable?, response: Response?) = submit {
                    failed(token, "connection_failed_" + (response?.code ?: 0))
                }
            })
    }

    private fun failed(token: Long, reason: String) {
        if (token != generation) return
        disconnect()
        retryDelay = ProactiveAttentionPushPolicy.retryDelay(retryDelay)
        retryAt = System.currentTimeMillis() + retryDelay + (0..1_000).random()
        store.status(reason)
        log(reason)
        control.schedule({ runCatching { reconcile() } }, retryDelay + 1_000, TimeUnit.MILLISECONDS)
        ProactiveAttentionFeedScheduler.request(context)
    }

    private fun drain() {
        if (draining || !enabled() || !online()) return
        val id = store.next() ?: return
        draining = true
        reader.execute {
            try {
                val json = AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(
                    ProactiveAttentionPushPolicy.itemUrl(id), maxBytes = 128 * 1024L,
                    checkpoint = { check(!closed && !Thread.currentThread().isInterrupted) }).body.toString(Charsets.UTF_8)
                // Pausing while a download is in flight must not create a late notification.
                if (!enabled()) return@execute
                val article = ProactiveAttentionPushPolicy.article(json, id, System.currentTimeMillis())
                var created = 0
                if (article != null) {
                    val preferences = ProactiveAttentionStore(context).preferences()
                    val topic = preferences.topics.firstOrNull { it.enabled && ProactiveAttentionFeedSources.matches(article, it) }
                    if (topic != null && ProactiveAttentionFeedStore(context).ingest(article.copy(topicId = topic.id), topic)) created++
                }
                store.complete(id)
                ProactiveAttentionFeedDelivery.published(context, created)
            } catch (_: Exception) {
                if (!closed) store.defer(id)
            } finally {
                submit { draining = false; drain() }
            }
        }
    }

    private fun disconnect() { generation++; source?.cancel(); source = null }
    fun close() {
        closed = true
        reader.shutdownNow()
        // Serialize cleanup after an in-progress connect so it cannot leave a new orphan stream.
        control.execute {
            disconnect()
            client.dispatcher.cancelAll()
            client.connectionPool.evictAll()
            client.dispatcher.executorService.shutdown()
            control.shutdownNow()
        }
        control.shutdown()
    }
    private fun log(status: String) = Log.i("GalaxySSIAttention", "phone_push_hn $status")
}
