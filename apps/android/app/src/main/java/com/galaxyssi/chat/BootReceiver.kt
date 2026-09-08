package com.galaxyssi.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.concurrent.Executors

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED && intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val appContext = context.applicationContext
        startMessageService(appContext)
        val restartCondition = if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            AgentEvalCondition.REBOOT
        } else {
            AgentEvalCondition.PROCESS_DEATH
        }
        val pending = goAsync()
        RESTORE_EXECUTOR.execute {
            try {
                // Keep the broadcast alive until WorkManager has durably accepted the request.
                AgentStartupRecovery.enqueue(appContext).result.get()
                runCatching { AgentEvalReliabilityHarness.initialize(appContext, restartCondition) }
            } catch (error: Exception) {
                android.util.Log.w("GalaxySSIRecovery", "Boot recovery enqueue failed", error)
            } finally {
                pending.finish()
            }
            runCatching { AgentWorkflowScheduler.restoreAll(appContext) }
            runCatching { AgentProactiveTaskScheduler.restoreAll(appContext) }
            runCatching { GlobalAgentWakeScheduler.restore(appContext) }
            runCatching { AndroidCognitionScheduler.requestImmediate(appContext) }
        }
    }

    private fun startMessageService(context: Context) {
        val service = Intent(context, MessageService::class.java)
        val started = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
        }.isSuccess
        if (!started) {
            runCatching { GlobalAgentWakeScheduler.schedule(context, System.currentTimeMillis() + 60_000L) }
        }
    }

    private companion object {
        val RESTORE_EXECUTOR = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "galaxyssi-boot-restore").apply { isDaemon = true }
        }
    }
}
