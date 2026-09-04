package com.signalasi.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

data class AgentEvalProcessSession(
    val processInstanceId: String,
    val bootCount: Int,
    val startedAtMillis: Long
)

private class AgentEvalProcessSessionStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun replace(current: AgentEvalProcessSession): AgentEvalProcessSession? {
        val previous = decode(database.readString(KEY_SESSION, ""))
        database.writeString(KEY_SESSION, JSONObject()
            .put("process_instance_id", current.processInstanceId)
            .put("boot_count", current.bootCount)
            .put("started_at_millis", current.startedAtMillis)
            .toString())
        return previous
    }

    private fun decode(raw: String): AgentEvalProcessSession? = runCatching {
        val json = JSONObject(raw)
        AgentEvalProcessSession(
            processInstanceId = json.getString("process_instance_id"),
            bootCount = json.optInt("boot_count", -1),
            startedAtMillis = json.optLong("started_at_millis")
        )
    }.getOrNull()

    private companion object {
        const val DATABASE = "signalasi_eval_process_session_v1"
        const val KEY_SESSION = "current"
    }
}

object AgentEvalReliabilityHarness {
    private val processInitialized = AtomicBoolean(false)
    private val environmentMonitoring = AtomicBoolean(false)
    private val networkUnavailable = AtomicBoolean(false)
    private val deviceIdle = AtomicBoolean(false)
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var idleReceiver: BroadcastReceiver? = null

    fun initialize(
        context: Context,
        forcedRestartCondition: AgentEvalCondition? = null
    ): AgentEvalCondition? {
        val appContext = context.applicationContext
        if (!processInitialized.compareAndSet(false, true)) {
            startEnvironmentMonitoring(appContext)
            return null
        }
        val session = AgentEvalProcessSession(
            processInstanceId = AgentProcessIdentity.instanceId,
            bootCount = bootCount(appContext),
            startedAtMillis = System.currentTimeMillis()
        )
        val previous = AgentEvalProcessSessionStore(appContext).replace(session)
        val detected = forcedRestartCondition ?: previous
            ?.takeIf { it.processInstanceId != session.processInstanceId }
            ?.let { old ->
                if (old.bootCount >= 0 && session.bootCount >= 0 && old.bootCount != session.bootCount) {
                    AgentEvalCondition.REBOOT
                } else {
                    AgentEvalCondition.PROCESS_DEATH
                }
            }
        RECOVERY_EXECUTOR.execute {
            runCatching { AgentBenchmarkMemoryFixtures.prepareLongitudinal(appContext) }
            if (detected != null) recoverInterruptedRuns(appContext, detected)
            AgentEvalBenchmarkCatalog.suites.forEach { suite ->
                runCatching {
                    AgentBenchmarkCoordinator(appContext, suite).resumeLatestIncomplete(
                        condition = detected ?: AgentEvalCondition.PROCESS_DEATH,
                        reason = if (detected != null) {
                            "${suite.title} resumed after ${detected.wireValue}"
                        } else {
                            "${suite.title} resumed from persisted incomplete work"
                        }
                    )
                }
            }
        }
        startEnvironmentMonitoring(appContext)
        return detected
    }

    private fun recoverInterruptedRuns(context: Context, condition: AgentEvalCondition) {
        val reason = when (condition) {
            AgentEvalCondition.REBOOT -> "Agent run was interrupted by an Android reboot"
            AgentEvalCondition.PROCESS_DEATH -> "Agent run was interrupted by Android process death"
            else -> "Agent run was interrupted by ${condition.wireValue}"
        }
        AgentRunRecorder(context).runningRuns().forEach { run ->
            AgentEvalOpsService.observeRunInterrupted(context, run.runId, condition, reason)
        }
        AgentColdBootRecoveryCoordinator.pauseInterruptedTasks(context, reason)
        AgentEvolutionLabRuntimeRegistry.get(context).resumeInterrupted(condition, reason)
    }

    private fun startEnvironmentMonitoring(context: Context) {
        if (!environmentMonitoring.compareAndSet(false, true)) return
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val currentNetwork = connectivity?.activeNetwork
        val initialValidated = currentNetwork?.let(connectivity::getNetworkCapabilities)
            ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
        networkUnavailable.set(!initialValidated)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onLost(network: Network) {
                if (networkUnavailable.compareAndSet(false, true)) {
                    AgentEvalOpsService.observeConditionEntered(
                        context,
                        AgentEvalCondition.NETWORK_LOSS,
                        "Android reported that the active network was lost"
                    )
                }
            }

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                val validated = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                if (validated && networkUnavailable.compareAndSet(true, false)) {
                    AgentEvalOpsService.observeConditionRecovered(
                        context,
                        AgentEvalCondition.NETWORK_LOSS,
                        "Android reported that validated network access recovered"
                    )
                }
            }
        }
        if (connectivity != null && runCatching {
                connectivity.registerDefaultNetworkCallback(callback)
            }.isSuccess
        ) {
            networkCallback = callback
        }

        val power = context.getSystemService(PowerManager::class.java)
        deviceIdle.set(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && power?.isDeviceIdleMode == true)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context, intent: Intent?) {
                if (intent?.action != PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED) return
                val idle = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                    receiverContext.getSystemService(PowerManager::class.java)?.isDeviceIdleMode == true
                if (idle && deviceIdle.compareAndSet(false, true)) {
                    AgentEvalOpsService.observeConditionEntered(
                        receiverContext,
                        AgentEvalCondition.DOZE,
                        "Android entered device idle mode"
                    )
                } else if (!idle && deviceIdle.compareAndSet(true, false)) {
                    AgentEvalOpsService.observeConditionRecovered(
                        receiverContext,
                        AgentEvalCondition.DOZE,
                        "Android exited device idle mode"
                    )
                }
            }
        }
        val filter = IntentFilter(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
        val registered = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                context.registerReceiver(receiver, filter)
            }
        }.isSuccess
        if (registered) idleReceiver = receiver
    }

    private fun bootCount(context: Context): Int = runCatching {
        Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT)
    }.getOrDefault(-1)

    private val RECOVERY_EXECUTOR = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "signalasi-eval-recovery").apply { isDaemon = true }
    }
}
