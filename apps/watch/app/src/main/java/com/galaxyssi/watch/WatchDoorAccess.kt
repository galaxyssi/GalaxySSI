package com.galaxyssi.watch

import android.content.Context
import com.galaxyssi.chat.DoorAccessClient
import com.galaxyssi.chat.DoorAccessCommand
import com.galaxyssi.chat.DoorAccessConfiguration
import com.galaxyssi.chat.DoorAccessCredentialStore
import com.galaxyssi.chat.DoorAccessOpenStatus

/** Snapshot an exact, installed Skill command before dispatch. Never send it to a model. */
internal object WatchDoorAccess {
    sealed class Plan {
        object Unmatched : Plan()
        class Panel(val configuration: DoorAccessConfiguration) : Plan()
        // Do not use a data class: its generated toString would expose credentials.
        class Open(val configuration: DoorAccessConfiguration, val command: DoorAccessCommand.Open,
            val credentials: Pair<String, String>) : Plan()
    }
    data class Outcome(val state: TaskState, val message: String)

    fun prepare(context: Context, prompt: String): Plan {
        val configuration = WatchSkillManager(context).activeConfiguration()
        val credentials = if (configuration?.parse(prompt) is DoorAccessCommand.Open)
            DoorAccessCredentialStore(context).load() else null
        return plan(configuration, prompt, credentials)
    }

    fun plan(configuration: DoorAccessConfiguration?, prompt: String, credentials: Pair<String, String>?): Plan {
        val command = configuration?.parse(prompt) ?: return Plan.Unmatched
        return if (command is DoorAccessCommand.Open && credentials != null)
            Plan.Open(configuration, command, credentials) else Plan.Panel(configuration)
    }

    fun execute(plan: Plan.Open, client: DoorAccessClient = DoorAccessClient(), checkpoint: () -> Unit = {}): Outcome {
        val result = try {
            client.openUnique(plan.credentials.first, plan.credentials.second, plan.command,
                System.currentTimeMillis(), plan.configuration, checkpoint)
        } catch (_: Exception) {
            checkpoint()
            return Outcome(TaskState.FAILED, "service_failed")
        }
        // Match Android's result wording and never retry an unconfirmed opening.
        return when (result.status) {
            DoorAccessOpenStatus.ACCEPTED -> Outcome(TaskState.COMPLETED, "sent")
            DoorAccessOpenStatus.NO_UNIQUE_MATCH -> Outcome(TaskState.FAILED, "not_unique_tool")
            DoorAccessOpenStatus.REJECTED -> Outcome(TaskState.FAILED, "rejected_tool")
            DoorAccessOpenStatus.UNCONFIRMED -> Outcome(TaskState.FAILED, "unconfirmed")
        }
    }
}
