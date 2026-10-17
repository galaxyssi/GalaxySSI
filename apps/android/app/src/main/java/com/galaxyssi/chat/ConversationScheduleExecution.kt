package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.provider.AlarmClock
import org.json.JSONObject

internal data class ConversationScheduleOutcome(
    val status: AgentProactiveRunStatus,
    val summary: String,
    val errorCode: String = ""
)

internal object ConversationScheduleExecution {
    fun localAction(context: Context, task: AgentProactiveTask): AgentAction? {
        val screen = ScreenContext("", pageTitle = "")
        val tools = AgentPhoneNativeToolCatalog.defaultRegistry(context, screenProvider = { screen }).descriptors()
        return localAction(request(task.action.prompt, tools), RuleBasedAgentPlanner(context))
    }

    internal fun localAction(request: AgentRequest, planner: RuleBasedAgentPlanner = RuleBasedAgentPlanner()): AgentAction? =
        if (explicitDesktop.containsMatchIn(request.goal)) null else planner.deterministicLocalAction(request)

    private val explicitDesktop = Regex("(?:\\b(?:windows|desktop|computer|macos)\\b|\u7535\u8111|\u96fb\u8166)", RegexOption.IGNORE_CASE)

    fun expectsPhone(goal: String): Boolean = !explicitDesktop.containsMatchIn(goal) &&
        AgentTaskIntentClassifier.classify(goal).intent == AgentTaskIntent.PHONE_CONTROL

    internal fun request(goal: String, tools: List<AgentNativeToolDescriptor> = emptyList()): AgentRequest {
        val screen = ScreenContext("", pageTitle = "")
        return AgentRequest(goal, screen, emptyList(), memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build("schedule", goal, screen,
                PermissionMode.FULL_ACCESS, false, false, emptyList(), emptyList(), nativeTools = tools))
    }

    fun executeLocal(context: Context, task: AgentProactiveTask, run: AgentProactiveRun,
        action: AgentAction): ConversationScheduleOutcome {
        // Stable scope lets the existing effect journal prevent duplicate side effects after recovery.
        val agent = MobileNativeAgent(context, sessionStore = InMemoryAgentSessionStore(),
            screenObservationOverride = false)
        agent.sessionId = run.runId
        agent.currentGoal = task.action.prompt
        val result = agent.executeDirectAction(action, task.action.conversationId, run.runId)
        if (!result.success) return ConversationScheduleOutcome(AgentProactiveRunStatus.FAILED,
            result.message, result.metadata["error_code"].orEmpty().ifBlank { "local_action_failed" })

        val expectedPackage = expectedForegroundPackage(context, action)
        if (action.kind in setOf(AgentActionKind.SET_ALARM, AgentActionKind.OPEN_APP)) {
            if (action.parameters.containsKey("hour") || action.parameters.containsKey("timer_seconds"))
                return ConversationScheduleOutcome(AgentProactiveRunStatus.UNVERIFIED,
                    context.getString(R.string.schedule_local_configuration_unverified), "configuration_not_verified")
            if (!GalaxySSIAccessibilityService.isActive())
                return ConversationScheduleOutcome(AgentProactiveRunStatus.UNVERIFIED,
                    context.getString(R.string.schedule_local_unverified), "foreground_observer_unavailable")
            val deadline = android.os.SystemClock.elapsedRealtime() + 2_000L
            do {
                val visible = GalaxySSIAccessibilityService.captureCurrentScreen("", "")?.foregroundApp
                if (!expectedPackage.isNullOrBlank() && visible == expectedPackage) {
                    return ConversationScheduleOutcome(AgentProactiveRunStatus.COMPLETED,
                        context.getString(R.string.schedule_local_opened, task.name))
                }
                Thread.sleep(150)
            } while (android.os.SystemClock.elapsedRealtime() < deadline)
            return ConversationScheduleOutcome(AgentProactiveRunStatus.UNVERIFIED,
                context.getString(R.string.schedule_local_unverified), "foreground_not_verified")
        }
        return ConversationScheduleOutcome(AgentProactiveRunStatus.COMPLETED, result.message)
    }

    private fun expectedForegroundPackage(context: Context, action: AgentAction): String? {
        if (action.kind == AgentActionKind.OPEN_APP) return action.parameters["package_name"]
            ?.takeIf(String::isNotBlank) ?: action.parameters["package"]?.takeIf(String::isNotBlank)
        if (action.kind != AgentActionKind.SET_ALARM) return null
        val intent = Intent(if (action.id == "open-timer" || action.parameters.containsKey("timer_seconds"))
            AlarmClock.ACTION_SHOW_TIMERS else AlarmClock.ACTION_SHOW_ALARMS)
        return context.packageManager.resolveActivity(intent, 0)?.activityInfo?.packageName
    }

    const val REMOTE_CONTRACT = """
This occurrence was requested on an Android phone. Device/UI actions refer to the originating phone unless the user explicitly names a computer/Windows/Desktop. Do not substitute desktop applications for phone applications. If the necessary phone tool is unavailable, report blocked; do not open a desktop substitute.
Return a single JSON object (no Markdown fence) with protocol="galaxyssi.schedule-outcome.v1", outcome="completed"|"failed"|"blocked", summary (in the user's language), execution_device="phone"|"desktop"|"none", and evidence (actual tool observations, or sources for an informational task). A finished model response is not proof that the requested action succeeded. Never claim completed when a tool is unavailable, denied, failed, or its result is unknown.
"""

    fun remoteOutcome(raw: String, succeeded: Boolean, phoneAction: Boolean = false): ConversationScheduleOutcome {
        val json = runCatching { JSONObject(raw.trim().removePrefix("```json").removeSuffix("```").trim()) }.getOrNull()
        if (!succeeded) return ConversationScheduleOutcome(AgentProactiveRunStatus.FAILED,
            if (json?.optString("protocol") == "galaxyssi.schedule-outcome.v1") json.optString("summary") else raw,
            "remote_execution_failed")
        if (json?.optString("protocol") != "galaxyssi.schedule-outcome.v1")
            return ConversationScheduleOutcome(AgentProactiveRunStatus.UNVERIFIED, raw, "missing_execution_outcome")
        val summary = json.optString("summary").trim()
        if (json.optString("outcome") == "completed" && phoneAction && json.optString("execution_device") != "phone")
            return ConversationScheduleOutcome(AgentProactiveRunStatus.FAILED, summary, "wrong_execution_device")
        return when (json.optString("outcome")) {
            "failed", "blocked" -> ConversationScheduleOutcome(AgentProactiveRunStatus.FAILED, summary,
                "remote_${json.optString("outcome")}")
            "completed" -> if (summary.isNotBlank() && json.optString("evidence").isNotBlank() &&
                json.optString("execution_device") in setOf("phone", "desktop", "none"))
                ConversationScheduleOutcome(AgentProactiveRunStatus.COMPLETED, summary)
            else ConversationScheduleOutcome(AgentProactiveRunStatus.UNVERIFIED, summary, "missing_execution_evidence")
            else -> ConversationScheduleOutcome(AgentProactiveRunStatus.UNVERIFIED, summary, "invalid_execution_outcome")
        }
    }

    fun remoteRichOutput(raw: String, summary: String): String {
        val blocks = AgentRichContentCodec.decode(raw)
        if (blocks.none { "galaxyssi.schedule-outcome.v1" in it.text }) return raw
        val visible = blocks.filterNot { "galaxyssi.schedule-outcome.v1" in it.text }
        return AgentRichContentCodec.encode(listOf(AgentRichBlock("schedule-outcome", AgentRichBlockType.TEXT, text = summary)) + visible)
    }
}
