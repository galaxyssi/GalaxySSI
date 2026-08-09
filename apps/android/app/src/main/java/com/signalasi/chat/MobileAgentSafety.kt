package com.signalasi.chat

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.util.Log
import com.signalasi.chat.voice.VoiceFeatureFlags
import com.signalasi.chat.voice.agent.VoiceAgentRunBridge
import com.signalasi.chat.voice.agent.VoiceAgentRunRequest
import com.signalasi.chat.voice.metrics.VoiceLatencyTraceContext
import com.signalasi.chat.voice.modelstream.ModelStreamEvent
import com.signalasi.chat.voice.modelstream.ModelStreamUiMerger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import java.util.Date
import java.text.SimpleDateFormat
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

interface AgentSafetyPolicy {
    fun permissionMode(): PermissionMode
    fun highRiskGuardEnabled(): Boolean
    fun review(plan: AgentPlan, sessionId: String = ""): AgentSafetyReview
    fun recordDecision(
        action: AgentAction,
        sessionId: String,
        choice: AgentPermissionChoice
    ) = Unit
}

class DefaultAgentSafetyPolicy(
    internal val settingsStore: AgentSafetySettingsStore? = null,
    internal val confirmationConsentStore: AgentConfirmationConsentStore? = null
) : AgentSafetyPolicy {
    override fun permissionMode(): PermissionMode =
        settingsStore?.load()?.permissionMode ?: PermissionMode.ASK_BEFORE_ACTION

    override fun highRiskGuardEnabled(): Boolean =
        settingsStore?.load()?.highRiskGuard ?: true

    override fun review(plan: AgentPlan, sessionId: String): AgentSafetyReview {
        val settings = settingsStore?.load() ?: AgentSafetySettings()
        val mode = permissionMode()
        val highestRisk = plan.actions.maxByOrNull { it.risk.weight }?.risk ?: AgentRisk.LOW
        val deniedSystemPermissions = plan.requiredPermissions
            .filter { it.required && !it.granted }
            .map { it.id }
        val deniedCapabilities = buildList {
            if (settings.executionPaused && plan.actions.any {
                    it.kind != AgentActionKind.DRAFT_PLAN && it.kind != AgentActionKind.READ_SCREEN
                }
            ) {
                add("execution_paused")
            }
            if (!settings.screenObservationAllowed && plan.actions.any { it.kind.requiresScreenObservation() }) {
                add("screen_observation")
            }
            if (!settings.localActionsAllowed && plan.actions.any { it.kind.isLocalExecutionAction() }) {
                add("local_actions")
            }
            if (!settings.memoryCapture && plan.actions.any { it.kind.writesAgentKnowledge() }) {
                add("memory_capture")
            }
            if (!settings.connectorCallsAllowed && plan.actions.any { it.kind == AgentActionKind.CALL_CONNECTOR }) {
                val hasUnrestrictedDesktopGrant = plan.actions
                    .filter { it.kind == AgentActionKind.CALL_CONNECTOR }
                    .all { it.parameters["_signalasi_desktop_executor_full"] == "true" }
                if (!hasUnrestrictedDesktopGrant) add("connector_calls")
            }
            if (!settings.deviceControlAllowed && plan.actions.any { it.kind == AgentActionKind.CONTROL_DEVICE }) {
                add("device_control")
            }
        }
        val deniedPermissions = (deniedSystemPermissions + deniedCapabilities).distinct()
        val blocksScreenAction = mode == PermissionMode.OBSERVE_ONLY &&
            plan.actions.any { it.kind != AgentActionKind.READ_SCREEN }
        val blocksExecution = mode == PermissionMode.SUGGEST_ONLY &&
            plan.actions.any { it.kind != AgentActionKind.READ_SCREEN && it.kind != AgentActionKind.DRAFT_PLAN }
        val blocksHighRisk = highRiskGuardEnabled() && highestRisk == AgentRisk.BLOCKED
        val blockedActionReason = plan.actions
            .firstOrNull { it.risk == AgentRisk.BLOCKED }
            ?.parameters
            ?.get("blocked_reason")
            .orEmpty()
        val blocked = deniedPermissions.isNotEmpty() || blocksScreenAction || blocksExecution || blocksHighRisk
        val pendingActions = plan.actions.filter {
            it.status == AgentActionStatus.PENDING_CONFIRMATION || it.status == AgentActionStatus.PROPOSED
        }
        val consentDecisions = pendingActions.associateWith { action ->
            confirmationConsentStore?.decision(
                AgentConfirmationPolicy.consentKey(action),
                sessionId
            )
        }
        val permanentlyDeniedAction = pendingActions.firstOrNull { action ->
            consentDecisions[action]?.denied == true
        }
        val permissionDecisionBlocked = permanentlyDeniedAction != null
        val requiresTierConfirmation = pendingActions.any { action ->
            when (AgentConfirmationPolicy.tier(action)) {
                AgentConfirmationTier.DIRECT -> false
                AgentConfirmationTier.CONFIRM_ALWAYS -> true
                AgentConfirmationTier.CONFIRM_ONCE ->
                    consentDecisions[action]?.allowed != true
            }
        }
        runCatching {
            Log.d(
                "SignalASISafety",
                "review mode=${mode.name} actions=${pendingActions.joinToString(",") { action ->
                    "${action.kind.name}:${AgentConfirmationPolicy.tier(action).name}"
                }} tier_confirmation=$requiresTierConfirmation blocked=$blocked " +
                    "denied=${deniedPermissions.joinToString(",")} " +
                    "screen_blocked=$blocksScreenAction execution_blocked=$blocksExecution " +
                    "high_risk_blocked=$blocksHighRisk"
            )
        }
        val requiresConfirmation = when (mode) {
            PermissionMode.OBSERVE_ONLY,
            PermissionMode.SUGGEST_ONLY -> false
            PermissionMode.ASK_BEFORE_ACTION -> pendingActions.any {
                val tier = AgentConfirmationPolicy.tier(it)
                tier != AgentConfirmationTier.DIRECT &&
                    (tier == AgentConfirmationTier.CONFIRM_ALWAYS ||
                        consentDecisions[it]?.allowed != true) &&
                    it.kind != AgentActionKind.READ_SCREEN &&
                    it.kind != AgentActionKind.DRAFT_PLAN &&
                    it.kind != AgentActionKind.CALL_CONNECTOR &&
                    !it.isPhoneDevelopmentRuntimeHandoff()
            }
            PermissionMode.AUTO_LOW_RISK -> requiresTierConfirmation
        }
        val warnings = buildList {
            if (highestRisk == AgentRisk.BLOCKED) add("blocked_action")
            if (highestRisk.weight >= AgentRisk.HIGH.weight) add("high_risk_action")
            if (deniedPermissions.isNotEmpty()) add("missing_required_permission")
            if (permissionDecisionBlocked) add("permission_permanently_denied")
            if (blocksScreenAction) add("observe_only_mode")
            if (blocksExecution) add("suggest_only_mode")
        }
        val reason = when {
            permissionDecisionBlocked ->
                "Tool permission was permanently denied: " +
                    AgentConfirmationPolicy.consentKey(requireNotNull(permanentlyDeniedAction))
            "execution_paused" in deniedCapabilities -> "All Agent execution is paused"
            deniedPermissions.isNotEmpty() -> "Missing required permission: ${deniedPermissions.joinToString(", ")}"
            blocksScreenAction -> "Observe-only mode blocks screen actions"
            blocksExecution -> "Suggest-only mode blocks execution"
            blocksHighRisk -> blockedActionReason.ifBlank { "High-risk guard blocked this action" }
            else -> ""
        }
        return AgentSafetyReview(
            risk = highestRisk,
            requiresConfirmation = requiresConfirmation || blocked || permissionDecisionBlocked,
            blocked = blocked || permissionDecisionBlocked,
            mode = mode,
            deniedPermissions = deniedPermissions,
            warnings = warnings,
            reason = reason
        )
    }

    override fun recordDecision(
        action: AgentAction,
        sessionId: String,
        choice: AgentPermissionChoice
    ) {
        val tier = AgentConfirmationPolicy.tier(action)
        if (tier == AgentConfirmationTier.DIRECT) return
        val effectiveChoice = if (
            tier == AgentConfirmationTier.CONFIRM_ALWAYS &&
            choice in setOf(
                AgentPermissionChoice.ALLOW_SESSION,
                AgentPermissionChoice.ALLOW_ALWAYS
            )
        ) {
            AgentPermissionChoice.ALLOW_ONCE
        } else {
            choice
        }
        confirmationConsentStore?.record(
            AgentConfirmationPolicy.consentKey(action),
            effectiveChoice,
            sessionId
        )
    }
}
