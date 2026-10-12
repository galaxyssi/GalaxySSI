package com.galaxyssi.chat

import android.app.NotificationManager
import android.content.Context

/** Subscriptions only retain encrypted-record identities, never browser previews or credentials. */
internal class AgentBrowserRuntimeWatch(context: Context,
    private val events: AgentRuntimeInstanceEventHub = AgentRuntimeInstanceEvents.hub,
    private val store: AgentBrowserUserRequestStore = AgentBrowserUserRequestStore(context.applicationContext),
    private val onSettled: (AgentBrowserUserRequest) -> Unit = {},
    private val enqueue: (AgentBrowserUserRequest) -> Unit = { record ->
        AgentLongTaskRecoveryScheduler.enqueueBrowserEvent(context.applicationContext, record)?.result?.get()
        Unit
    }) : AutoCloseable {
    private val app = context.applicationContext
    private val subscriptions = mutableMapOf<String, AutoCloseable>()

    @Synchronized fun watch(record: AgentBrowserUserRequest) {
        if (record.state != "active" || record.runtimeInstanceId.isBlank() || record.handoffId.isBlank() ||
            record.hostProcessId != AgentProcessIdentity.instanceId || store.load(record.key) != record) return
        val key = "${record.key}:${record.generation}"
        if (key in subscriptions) return
        subscriptions[key] = events.observe(record.runtimeInstanceId) { event ->
            val interrupted = try { store.interruptRuntime(record, event) } finally { unwatch(record) }
            if (interrupted != null) {
                onSettled(record)
                if (interrupted.pendingRunWake) runCatching { enqueue(interrupted) }.onFailure {
                    android.util.Log.w("GalaxySSIBrowserRecovery", "Runtime interruption enqueue deferred", it)
                }
                app.getSystemService(NotificationManager::class.java).cancel(record.key, 1)
            }
        }
    }

    @Synchronized fun unwatch(record: AgentBrowserUserRequest) {
        subscriptions.remove("${record.key}:${record.generation}")?.close()
    }

    @Synchronized override fun close() {
        subscriptions.values.forEach(AutoCloseable::close)
        subscriptions.clear()
    }
}

internal object AgentBrowserRuntimeEvents {
    private var watch: AgentBrowserRuntimeWatch? = null
    @Synchronized fun forContext(context: Context): AgentBrowserRuntimeWatch = watch
        ?: AgentBrowserRuntimeWatch(context.applicationContext,
            onSettled = { AgentBrowserSessionEvents.forContext(context).unwatch(it) }).also { watch = it }
}
