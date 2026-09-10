package com.galaxyssi.chat

import android.content.Context

enum class AgentPlannerRecoveryKind { GUARDED_MODEL, RULE_BASED, PHONE_REASONING, NATIVE_ACTION }

data class AgentPlannerRecoverySpec(
    val kind: AgentPlannerRecoveryKind,
    val action: AgentAction? = null,
    val configurationSha256: String = ""
)

internal class AgentSelectedNativeActionPlanner(private val action: AgentAction) : AgentPlanner {
    override fun recoverySpec() = AgentPlannerRecoverySpec(AgentPlannerRecoveryKind.NATIVE_ACTION, action)
    override fun plan(request: AgentRequest) = AgentPlanFactory.actions(request, listOf(action)).copy(
        plannerProfile = "deterministic-native-route",
        routeRationale = "An exact phone-native route was selected before model planning.")
}

internal fun AgentPlannerRecoverySpec.restore(context: Context, registry: () -> AgentNativeToolRegistry): AgentPlanner {
    val restored = when (kind) {
        AgentPlannerRecoveryKind.GUARDED_MODEL -> GuardedModelAgentPlanner(context, nativeToolRegistryProvider = registry)
        AgentPlannerRecoveryKind.RULE_BASED -> RuleBasedAgentPlanner(context)
        AgentPlannerRecoveryKind.PHONE_REASONING -> AgentPhoneReasoningProviderPlanner(requireNotNull(action))
        AgentPlannerRecoveryKind.NATIVE_ACTION -> AgentSelectedNativeActionPlanner(requireNotNull(action))
    }
    if (restored.recoverySpec() != this) throw AgentModelLoopRecoveryException("initial_planner_configuration_changed")
    return restored
}
