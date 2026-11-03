package com.galaxyssi.chat

import android.app.NotificationManager
import android.content.Context
import android.os.FileObserver
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** File callbacks only schedule bounded work; decryption, persistence and Run wakeup stay off that thread. */
internal class AgentBrowserSessionWatch(context: Context,
    private val store: AgentBrowserUserRequestStore = AgentBrowserUserRequestStore(context.applicationContext),
    private val enqueue: (AgentBrowserUserRequest) -> Unit = { record ->
        AgentLongTaskRecoveryScheduler.enqueueBrowserEvent(context.applicationContext, record)?.result?.get()
        Unit
    },
    private val dispatch: (() -> Unit) -> Unit = AgentBrowserSessionEvents::dispatch,
    private val onSettled: (AgentBrowserUserRequest) -> Unit = {}) : AutoCloseable {
    private val app = context.applicationContext
    private val subscriptions = mutableMapOf<String, Subscription>()

    @Synchronized fun watch(record: AgentBrowserUserRequest) {
        if (record.state != "active" || record.handoffId.isBlank() ||
            record.hostProcessId != AgentProcessIdentity.instanceId || store.load(record.key) != record) return
        val key = "${record.key}:${record.generation}"
        if (key in subscriptions) return
        AgentBrowserSessionEventCodec.prepare(app, record)
        val subscription = Subscription(record)
        subscriptions[key] = subscription
        subscription.observer.startWatching()
        // Covers exit before subscription or before the active handoff record was committed.
        subscription.scan()
    }

    @Synchronized fun unwatch(record: AgentBrowserUserRequest) {
        subscriptions.remove("${record.key}:${record.generation}")?.close()
        if (store.load(record.key) != record) AgentBrowserSessionEventCodec.file(app, record).delete()
    }

    @Synchronized override fun close() {
        subscriptions.values.forEach(Subscription::close)
        subscriptions.clear()
    }

    private inner class Subscription(val record: AgentBrowserUserRequest) : AutoCloseable {
        val closed = AtomicBoolean()
        val dirty = AtomicBoolean()
        val queued = AtomicBoolean()
        val file = AgentBrowserSessionEventCodec.file(app, record)
        @Suppress("DEPRECATION")
        val observer = object : FileObserver(file.parentFile!!.absolutePath, CLOSE_WRITE or MOVED_TO) {
            override fun onEvent(event: Int, path: String?) { if (path == file.name) scan() }
        }

        fun scan() {
            if (closed.get()) return
            dirty.set(true)
            if (!queued.compareAndSet(false, true)) return
            dispatch {
                try {
                    while (!closed.get() && dirty.getAndSet(false)) {
                        val interrupted = AgentBrowserSessionEventCodec.consume(app, record, store)
                        if (interrupted != null) {
                            unwatch(record)
                            onSettled(record)
                            if (interrupted.pendingRunWake) runCatching { enqueue(interrupted) }.onFailure {
                                android.util.Log.w("GalaxySSIBrowserRecovery", "Browser session interruption enqueue deferred", it)
                            }
                            app.getSystemService(NotificationManager::class.java).cancel(record.key, 1)
                        } else if (store.load(record.key) != record) unwatch(record)
                    }
                } catch (_: Exception) {
                    android.util.Log.w("GalaxySSIBrowserRecovery", "Browser session event observation deferred")
                } finally {
                    queued.set(false)
                    if (dirty.get() && !closed.get()) scan()
                }
            }
        }

        override fun close() {
            closed.set(true)
            observer.stopWatching()
        }
    }
}

internal object AgentBrowserSessionEvents {
    private val executor = Executors.newSingleThreadExecutor { work ->
        Thread(work, "galaxyssi-browser-events").apply { isDaemon = true }
    }
    private var watcher: AgentBrowserSessionWatch? = null
    fun dispatch(work: () -> Unit) { executor.execute(work) }
    @Synchronized fun forContext(context: Context): AgentBrowserSessionWatch = watcher
        ?: AgentBrowserSessionWatch(context.applicationContext,
            onSettled = { AgentBrowserRuntimeEvents.forContext(context).unwatch(it) }).also { watcher = it }
}
