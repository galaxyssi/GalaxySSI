package com.galaxyssi.chat

import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal data class AgentRuntimeInstanceEvent(val instanceId: String, val kind: Kind) {
    enum class Kind { EXITED, REPLACED }
    val browserCode: String get() = when (kind) {
        Kind.EXITED -> "browser_runtime_exited"
        Kind.REPLACED -> "browser_runtime_replaced"
    }
}

/** Host-issued identities only. A delayed old process exit cannot retire the current process. */
internal class AgentRuntimeInstanceEventHub(private val dispatch: (() -> Unit) -> Unit) {
    private val lock = Any()
    private var latest = ""
    private var running = false
    private val listeners = mutableMapOf<String, MutableSet<Subscription>>()

    private class Subscription(val listener: (AgentRuntimeInstanceEvent) -> Unit) {
        val cancelled = AtomicBoolean(false)
    }

    fun started(instanceId: String) {
        require(instanceId.isNotBlank())
        val retired = synchronized(lock) {
            if (latest == instanceId && running) return
            check(latest != instanceId) { "A retired runtime identity cannot be reused" }
            latest = instanceId
            running = true
            listeners.keys.filter { it != instanceId }.flatMap { id ->
                listeners.remove(id).orEmpty().map { it to AgentRuntimeInstanceEvent(id, AgentRuntimeInstanceEvent.Kind.REPLACED) }
            }
        }
        retired.forEach { (subscription, event) -> deliver(subscription, event) }
    }

    fun exited(instanceId: String) {
        require(instanceId.isNotBlank())
        val retired = synchronized(lock) {
            if (latest == instanceId) running = false
            listeners.remove(instanceId).orEmpty().toList()
        }
        retired.forEach { deliver(it, AgentRuntimeInstanceEvent(instanceId, AgentRuntimeInstanceEvent.Kind.EXITED)) }
    }

    fun observe(instanceId: String, listener: (AgentRuntimeInstanceEvent) -> Unit): AutoCloseable {
        require(instanceId.isNotBlank())
        val subscription = Subscription(listener)
        val immediate = synchronized(lock) {
            when {
                latest.isNotBlank() && latest != instanceId -> AgentRuntimeInstanceEvent.Kind.REPLACED
                latest == instanceId && !running -> AgentRuntimeInstanceEvent.Kind.EXITED
                else -> { listeners.getOrPut(instanceId) { mutableSetOf() }.add(subscription); null }
            }
        }
        immediate?.let { deliver(subscription, AgentRuntimeInstanceEvent(instanceId, it)) }
        return AutoCloseable {
            subscription.cancelled.set(true)
            synchronized(lock) {
                listeners[instanceId]?.let { active ->
                    active.remove(subscription)
                    if (active.isEmpty()) listeners.remove(instanceId)
                }
            }
        }
    }

    fun interruption(instanceId: String): AgentRuntimeInstanceEvent? = synchronized(lock) {
        when {
            latest.isBlank() || instanceId.isBlank() -> null
            latest != instanceId -> AgentRuntimeInstanceEvent(instanceId, AgentRuntimeInstanceEvent.Kind.REPLACED)
            !running -> AgentRuntimeInstanceEvent(instanceId, AgentRuntimeInstanceEvent.Kind.EXITED)
            else -> null
        }
    }

    private fun deliver(subscription: Subscription, event: AgentRuntimeInstanceEvent) = dispatch {
        if (!subscription.cancelled.get()) subscription.listener(event)
    }
}

internal object AgentRuntimeInstanceEvents {
    private val executor = Executors.newSingleThreadExecutor { work ->
        Thread(work, "galaxyssi-runtime-events").apply { isDaemon = true }
    }
    val hub = AgentRuntimeInstanceEventHub { work -> executor.execute {
        runCatching(work).onFailure { android.util.Log.w("GalaxySSIRuntimeEvents", "Runtime event delivery deferred", it) }
    } }
}

internal object AgentRuntimeProcessMonitor {
    fun start(child: Process, onExit: (Int) -> Unit): Thread = Thread({
        val code = try { child.waitFor() } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            return@Thread
        }
        onExit(code)
    }, "galaxyssi-runtime-process-monitor").apply { isDaemon = true; start() }
}
