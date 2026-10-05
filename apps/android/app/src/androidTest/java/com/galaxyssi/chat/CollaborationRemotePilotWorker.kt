package com.galaxyssi.chat

import android.content.Context

internal object CollaborationRemotePilotWorker {
    fun create(context: Context, delegate: AgentActionExecutor): ActionExecutorAgentTeamMemberWorker {
        val provider = ActionExecutorAgentProvider(registrationSource = { AppStoreAgentConnectorRegistry(context).registrations() },
            delegate = delegate, runStartReceipts = EncryptedAgentRunStartReceiptStore(context),
            healthLedger = EncryptedAgentProviderHealthLedger(context), managedResponses = EncryptedAgentManagedResponseLedger(context),
            globalRunSlots = AgentGlobalRunSlotStore(context))
        return ActionExecutorAgentTeamMemberWorker(provider, AgentAdapterDirectory().apply { register(provider) },
            screenProvider = { ScreenContext(foregroundApp = "GalaxySSI remote pilot", pageTitle = "Engineering comparison") },
            progressContext = context.applicationContext)
    }

    fun requireTarget(context: Context, policy: CollaborationRemoteExecutionPolicy) {
        val target = requireNotNull(AppStoreAgentConnectorRegistry(context).availableTargets().singleOrNull { it.id == policy.targetId })
        CollaborationLiveModelSelection.requireAvailable(target, policy.selection.modelId, policy.selection.reasoningEffort)
    }
}
