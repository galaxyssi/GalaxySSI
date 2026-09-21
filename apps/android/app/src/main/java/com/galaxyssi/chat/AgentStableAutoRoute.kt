package com.galaxyssi.chat

import android.content.Context

internal object AgentStableAutoRoutePolicy {
    fun displayedTarget(targets: List<AgentCallableTarget>, rememberedId: String): AgentCallableTarget? =
        targets.firstOrNull { it.id == rememberedId && it.kind != AgentConnectorKind.DEVICE }
            ?: AgentConnectorRouteSelector.select(targets, null)?.target

    fun usablePrimary(candidate: AgentResourceCandidate?): AgentResourceCandidate? =
        candidate?.takeIf { it.score > -1_000 }

    // Never resurrect a candidate excluded by privacy, budget, health or capacity checks.
    fun select(targets: List<AgentCallableTarget>, decision: AgentRoutingDecision?): AgentConnectorRouteSelection? {
        if (decision == null) return AgentConnectorRouteSelector.select(targets, null)
        val ids = decision.orderedTargetIds.toSet()
        return AgentConnectorRouteSelector.select(targets.filter { it.id in ids }, decision)
    }

    fun acceptsUpdate(activeTurn: String, incomingTurn: String): Boolean =
        incomingTurn.isNotBlank() && (activeTurn.isBlank() || activeTurn == incomingTurn)
}

/** The Auto label and the next dispatch share an exact, conversation-scoped identity. */
internal object AgentStableAutoRouteStore {
    private const val PREFERENCES = "agent_stable_auto_route"

    @Synchronized
    fun target(context: Context, conversationId: String, targets: List<AgentCallableTarget>): AgentCallableTarget? {
        val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val remembered = if (conversationId.isBlank()) "" else prefs.getString("$conversationId.target", "").orEmpty()
        val target = AgentStableAutoRoutePolicy.displayedTarget(targets, remembered)
        if (conversationId.isNotBlank() && target != null && target.id != remembered) {
            prefs.edit().putString("$conversationId.target", target.id).apply()
        }
        return target
    }

    @Synchronized
    fun beginTurn(context: Context, conversationId: String, turnId: String) {
        if (conversationId.isBlank() || turnId.isBlank()) return
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
            .putString("$conversationId.turn", turnId).apply()
    }

    @Synchronized
    fun recordDispatch(context: Context, conversationId: String, turnId: String, targetId: String) {
        if (conversationId.isBlank() || targetId.isBlank() || targetId == UNAVAILABLE_REASONING_CONNECTOR_ID) return
        if (AgentModelSelectionSettings.selection(context, conversationId).mode != AgentModelSelectionMode.AUTO) return
        val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (!AgentStableAutoRoutePolicy.acceptsUpdate(prefs.getString("$conversationId.turn", "").orEmpty(), turnId)) return
        prefs.edit().putString("$conversationId.target", targetId)
            .putString("$conversationId.turn", turnId).apply()
    }

    @Synchronized
    fun clear(context: Context, conversationIds: Collection<String>) {
        val editor = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
        conversationIds.filter(String::isNotBlank).forEach {
            editor.remove("$it.target").remove("$it.turn")
        }
        editor.apply()
    }
}
