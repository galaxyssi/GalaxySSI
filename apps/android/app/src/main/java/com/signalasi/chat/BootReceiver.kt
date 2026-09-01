package com.signalasi.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED && intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        runCatching {
            AgentEvalReliabilityHarness.initialize(
                context,
                if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
                    AgentEvalCondition.REBOOT
                } else {
                    AgentEvalCondition.PROCESS_DEATH
                }
            )
        }
        runCatching {
            AgentColdBootRecoveryCoordinator.pauseInterruptedTasks(
                context,
                "Task paused after the device or app restarted"
            )
        }
        runCatching { AgentWorkflowScheduler.restoreAll(context) }
        runCatching { AgentProactiveTaskScheduler.restoreAll(context) }
        runCatching { GlobalAgentWakeScheduler.restore(context) }
        runCatching { AndroidCognitionScheduler.requestImmediate(context) }
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
}
