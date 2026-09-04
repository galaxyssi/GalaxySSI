package com.galaxyssi.chat

import android.content.Context
import java.io.File
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import org.json.JSONObject

internal object AgentRuntimePackMountState {
    private val gate = AgentRuntimePackActivationGate()

    fun <T> withStableGuest(
        context: Context,
        statuses: () -> List<AgentRuntimePackStatus>,
        block: (List<AgentRuntimePackStatus>) -> T
    ): T {
        var executionStatuses = emptyList<AgentRuntimePackStatus>()
        return gate.withExecution(
            needsRecycle = {
                val current = statuses()
                executionStatuses = current
                val appContext = context.applicationContext
                val lifecycle = AgentOnDeviceRuntimeLifecycle.inspect(appContext)
                lifecycle.phase in ACTIVE_PHASES && requiresRecycle(
                    current,
                    File(appContext.filesDir, RUNTIME_CONFIG_PATH)
                        .takeIf(File::isFile)
                        ?.readText()
                        .orEmpty()
                )
            },
            recycle = { AgentOnDeviceRuntimeLifecycle.stop(context.applicationContext) },
            block = { block(executionStatuses) }
        )
    }

    fun requiresRecycle(
        statuses: List<AgentRuntimePackStatus>,
        runtimeConfigJson: String
    ): Boolean = desiredPackVersions(statuses) != mountedPackVersions(runtimeConfigJson)

    internal fun desiredPackVersions(statuses: List<AgentRuntimePackStatus>): Map<String, String> =
        statuses.asSequence()
            .filter { status ->
                status.id != LINUX_BASE &&
                    status.state == AgentRuntimePackState.READY &&
                    status.manifest != null
            }
            .associate { status -> status.id to requireNotNull(status.manifest).version }
            .toSortedMap()

    internal fun mountedPackVersions(runtimeConfigJson: String): Map<String, String> = runCatching {
        val packs = JSONObject(runtimeConfigJson).optJSONArray("packs") ?: return@runCatching emptyMap()
        buildMap {
            for (index in 0 until packs.length()) {
                val pack = packs.optJSONObject(index) ?: continue
                val id = pack.optString("id").trim()
                val version = pack.optString("version").trim()
                if (id.isNotBlank() && version.isNotBlank()) put(id, version)
            }
        }.toSortedMap()
    }.getOrDefault(emptyMap())

    private val ACTIVE_PHASES = setOf(
        AgentRuntimeLifecyclePhase.STARTING,
        AgentRuntimeLifecyclePhase.READY,
        AgentRuntimeLifecyclePhase.DEGRADED
    )
    private const val LINUX_BASE = "linux-base"
    private const val RUNTIME_CONFIG_PATH = "agent-runtime/guest-config.json"
}

/** Keeps the active guest stable while commands are running. */
internal class AgentRuntimePackActivationGate {
    private val lock = ReentrantLock(true)
    private val idle = lock.newCondition()
    private var activeExecutions = 0

    fun <T> withExecution(
        needsRecycle: () -> Boolean,
        recycle: () -> Unit,
        block: () -> T
    ): T {
        lock.withLock {
            var recycleRequired = needsRecycle()
            while (recycleRequired && activeExecutions > 0) {
                idle.awaitUninterruptibly()
                recycleRequired = needsRecycle()
            }
            if (recycleRequired) recycle()
            activeExecutions += 1
        }
        return try {
            block()
        } finally {
            lock.withLock {
                activeExecutions -= 1
                check(activeExecutions >= 0) { "Runtime execution lease count became invalid" }
                if (activeExecutions == 0) idle.signalAll()
            }
        }
    }
}
