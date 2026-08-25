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

interface AgentPlanner {
    fun plan(request: AgentRequest): AgentPlan
}

internal const val UNAVAILABLE_REASONING_CONNECTOR_ID = "reasoning-provider-unavailable"

class RuleBasedAgentPlanner(private val context: Context? = null) : AgentPlanner {
    override fun plan(request: AgentRequest): AgentPlan {
        AgentSpecializedAppPlanner.plan(request)?.let { specialized ->
            return AgentPlanFactory.actions(request, specialized.actions).copy(
                plannerProfile = "specialized-adapter:${specialized.profile}",
                routeRationale = "A deterministic app adapter selected the next grounded step."
            )
        }
        val actions = actionsFor(request)
        return AgentPlanFactory.actions(request, actions)
    }

    fun deterministicLocalAction(request: AgentRequest): AgentAction? =
        androidSystemNativeToolAction(request)
            ?: AgentSystemToolPlanner.actionFor(request)
            ?: installedAppOpenAction(request)
            ?: directDeviceStatusAction(request)

    fun directInformationConnectorAction(request: AgentRequest): AgentAction? {
        val requirements = AgentTaskRequirementAnalyzer.analyze(request.goal)
        if (AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(
                request.goal,
                request.conversationContext
            ) ||
            requirements.executionHorizon != AgentExecutionHorizon.INTERACTIVE ||
            AgentPhoneDevelopmentPolicy.shouldUsePhoneRuntime(request.goal) ||
            AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject(request.goal)
        ) {
            return null
        }
        return informationQueryAction(request)?.takeIf { it.kind == AgentActionKind.CALL_CONNECTOR }
    }

    internal fun configuredResponseLanguageCode(goal: String): String {
        val languageTag = context?.let { appContext ->
            runCatching { LanguagePolicySettings.resolvedResponseLanguage(appContext) }.getOrNull()
        }
        return languageTag
            ?.substringBefore('-')
            ?.lowercase(Locale.ROOT)
            ?: if (goal.any { it in '\u3400'..'\u9fff' }) "zh" else "en"
    }

    internal fun actionsFor(request: AgentRequest): List<AgentAction> {
        notificationReplyAction(request)?.let { return listOf(it) }
        deterministicLocalAction(request)?.let { return listOf(it) }
        supervisedProjectActions(request)?.let { return it }
        genericWebResearchActions(request)?.let { return it }
        manualSelectedConnectorAction(request)?.let { return listOf(it) }
        phoneDevelopmentActions(request)?.let { return it }
        val segments = splitGoalSegments(request.goal)
        if (segments.size <= 1) return listOf(actionFor(request))
        return segments.mapIndexed { index, segment ->
            actionFor(request.copy(goal = segment)).copy(id = "queue-${index + 1}-${segment.stableActionId()}")
        }
    }

    internal fun supervisedProjectActions(request: AgentRequest): List<AgentAction>? {
        if (!AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(
                request.goal,
                request.conversationContext
            )
        ) return null
        val selected = manualSelectedConnectorAction(request)
        val routing = if (selected == null) context?.let { appContext ->
            AgentResourceRouter(appContext).route(
                goal = request.goal,
                targets = request.targets,
                tools = request.runtimeContext.systemTools,
                nativeTools = request.runtimeContext.nativeTools
            )
        } else null
        val routedSelection = if (selected == null) {
            AgentConnectorRouteSelector.select(request.targets, routing)
        } else null
        val target = selected?.parameters?.get("connector_id")?.let { connectorId ->
            request.targets.firstOrNull { it.id == connectorId }
        } ?: routedSelection?.target ?: request.targets
            .asSequence()
            .filter { target ->
                target.kind != AgentConnectorKind.DEVICE &&
                    (AgentCapability.CODE in target.capabilities ||
                        AgentCapability.TASK_EXECUTION in target.capabilities ||
                        AgentCapability.REASONING in target.capabilities)
            }
            .minByOrNull { target ->
                val identity = "${target.id} ${target.title}".lowercase(Locale.US)
                val identityRank = when {
                    "codex" in identity -> 0
                    "claude" in identity -> 1
                    "hermes" in identity -> 2
                    target.kind == AgentConnectorKind.MODEL -> 3
                    else -> 4
                }
                val availabilityRank = if (target.status == AgentConnectorStatus.AVAILABLE) 0 else 10
                availabilityRank + identityRank
            } ?: return null
        val base = selected ?: connectorAction(
            request = request,
            connectorId = target.id,
            description = "Plan the next phone project step",
            routing = routedSelection?.decision
        )
        return listOf(
            base.copy(
                id = "supervise-phone-project-${request.goal.hashCode().toUInt()}",
                target = base.target.ifBlank { target.title },
                risk = AgentRisk.LOW,
                status = AgentActionStatus.PENDING_CONFIRMATION,
                description = "Plan the next phone project step",
                parameters = base.parameters + mapOf(
                    "connector_id" to target.id,
                    "prompt" to AgentSupervisedProjectLoop.planningPrompt(request),
                    "connector_task_mode" to PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
                    INTERNAL_TASK_EXECUTION_MODE to AgentTaskExecutionMode.PLAN_ONLY.wireValue,
                    "supervised_iteration" to "0",
                    "depends_on" to "",
                    "use_outputs_from" to ""
                ),
                requiresConfirmation = false
            )
        )
    }

    internal fun phoneDevelopmentActions(request: AgentRequest): List<AgentAction>? {
        if (!AgentPhoneDevelopmentPolicy.shouldUseManifestAuthoring(request.goal)) return null
        val runtime = request.runtimeContext.nativeTools.firstOrNull { descriptor ->
            descriptor.id == AgentOnDeviceRuntimeTools.EXECUTE &&
                (descriptor.availability.status == AgentNativeToolAvailabilityStatus.AVAILABLE ||
                    installedPhoneRuntimeCanWarm())
        } ?: return null
        val plannerTarget = request.targets
            .filter { target ->
                target.status == AgentConnectorStatus.AVAILABLE &&
                    target.kind != AgentConnectorKind.DEVICE &&
                    (AgentCapability.CODE in target.capabilities ||
                        AgentCapability.REASONING in target.capabilities ||
                        AgentCapability.CHAT in target.capabilities)
            }
            .minByOrNull { target ->
                when {
                    target.id.equals("codex", ignoreCase = true) -> 0
                    target.kind == AgentConnectorKind.MODEL -> 1
                    target.id.equals("claude-code", ignoreCase = true) -> 2
                    else -> 3
                }
            } ?: return null
        val executionProfile = AgentExecutionProfile.forGoal(
            goal = request.goal,
            hasAttachments = request.conversationContext.hasAttachments
        )
        val baseAuthoringPrompt = if (request.replanReason == PHONE_DEVELOPMENT_REPLAN_REASON) {
            AgentPhoneDevelopmentPolicy.repairPrompt(
                goal = request.goal,
                history = request.executionHistory,
                runtimeSummary = request.runtimeContext.compactSummary()
            ) ?: AgentPhoneDevelopmentPolicy.planningPrompt(request.goal)
        } else {
            AgentPhoneDevelopmentPolicy.planningPrompt(request.goal)
        }
        val authoringPrompt = buildString {
            append(baseAuthoringPrompt)
            append("\n\n")
            append(executionProfile.contract())
        }
        val manifestAction = connectorAction(
            request = request,
            connectorId = plannerTarget.id,
            description = "Prepare code for phone execution"
        ).copy(
            id = "prepare-phone-development-${request.goal.hashCode().toUInt()}",
            risk = AgentRisk.LOW,
            parameters = mapOf(
                "connector_id" to plannerTarget.id,
                "prompt" to authoringPrompt,
                "connector_task_mode" to PHONE_DEVELOPMENT_CONNECTOR_MODE,
                "_signalasi_desktop_executor_full" to
                    (plannerTarget.desktopAccessProfile == SignalASILinkProtocol.ACCESS_DESKTOP_EXECUTOR).toString()
            )
        )
        val runtimeInput = JSONObject()
            .put("language", AgentRuntimeLanguage.PYTHON.wireValue)
            .put("source", "")
            .put("arguments", JSONArray())
            .put("timeout_ms", 180_000L)
            .put("network_enabled", false)
            .put("allowed_network_domains", JSONArray())
            .put("artifact_paths", JSONArray())
        val runtimeAction = AgentAction(
            id = "execute-phone-development-${request.goal.hashCode().toUInt()}",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = runtime.title,
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Run and verify in the phone's on-device Linux runtime",
            parameters = mapOf(
                "tool_id" to runtime.id,
                "tool_version" to runtime.version,
                "native_tool_risk" to runtime.risk.wireValue,
                "response_language" to configuredResponseLanguageCode(request.goal),
                "input_json" to runtimeInput.toString(),
                "depends_on" to manifestAction.id,
                "use_outputs_from" to manifestAction.id,
                PHONE_DEVELOPMENT_MANIFEST_PARAMETER to "true"
            )
        )
        return listOf(manifestAction, runtimeAction)
    }

    internal fun installedPhoneRuntimeCanWarm(): Boolean {
        val appContext = context?.applicationContext ?: return false
        val status = AgentOnDeviceRuntimeManager(appContext).cachedStatus()
        val pythonPackReady = status.packs.any { pack ->
            pack.id == AgentRuntimeLanguage.PYTHON.requiredPack &&
                pack.state == AgentRuntimePackState.READY &&
                AgentRuntimeLanguage.PYTHON.requiredCapability in pack.manifest?.capabilities.orEmpty()
        }
        return status.backend != AgentOnDeviceRuntimeBackend.NONE && pythonPackReady
    }

    internal fun genericWebResearchActions(request: AgentRequest): List<AgentAction>? {
        if (AgentPhoneDevelopmentPolicy.shouldUseSupervisedProject(request.goal)) return null
        val requirements = AgentTaskRequirementAnalyzer.analyze(request.goal)
        val explicitSearch = phoneWebSearchQuery(request.goal, request.goal.lowercase(Locale.US)) != null
        if (!requirements.liveDataRequired && !explicitSearch) return null
        if (requirements.localOnly) return null
        val synthesis = informationQueryAction(request) ?: return null
        if (synthesis.kind != AgentActionKind.CALL_CONNECTOR) return null
        val connectorId = synthesis.parameters["connector_id"].orEmpty()
        val target = request.targets.firstOrNull { it.id == connectorId }
        val isPhoneCloudApi = connectorId == "cloud-models" ||
            (context != null && AppStore.isCloudApiContact(context, connectorId))
        val canRetrieveAtExecutionSite = isPhoneCloudApi || (
            target?.kind == AgentConnectorKind.AGENT &&
                AgentCapability.LIVE_DATA in target.capabilities &&
                AgentCapability.TOOL_USE in target.capabilities
            )
        if (canRetrieveAtExecutionSite) {
            return listOf(
                synthesis.copy(parameters = synthesis.parameters + mapOf(
                    "research_mode" to if (isPhoneCloudApi) "phone_cloud_tool_loop_v1" else "remote_agent_tool_loop_v1",
                    "web_execution_location" to if (isPhoneCloudApi) "phone" else "agent_host"
                ))
            )
        }
        val search = nativeToolAction(
            request,
            AgentWebIntelligenceNativeTools.RESEARCH,
            JSONObject()
                .put("query", request.goal.replace("%27", "'", ignoreCase = true).trim())
                .put("evidence_limit", 8)
                .put("engine_fanout", 18)
                .put("timeout_ms", 30_000)
        ) ?: return null
        val synthesisId = "research-synthesis-${request.goal.hashCode().toUInt()}"
        return listOf(
            search,
            synthesis.copy(
                id = synthesisId,
                description = "Answer from current public web evidence",
                parameters = synthesis.parameters + mapOf(
                    "prompt" to buildString {
                        append(request.goal.trim())
                        append("\n\nUse the phone-retrieved public web evidence below to answer directly. ")
                        append("Prefer current facts, cite source URLs, distinguish uncertainty, and do not describe internal tool steps.")
                    },
                    "depends_on" to search.id,
                    "use_outputs_from" to search.id,
                    "research_mode" to "signalasi_native_web_intelligence_v1"
                )
            )
        )
    }

    internal fun splitGoalSegments(goal: String): List<String> =
        goal.split(Regex("""\s+(?:and\s+then|then)\s+|[;\n]+""", RegexOption.IGNORE_CASE))
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .take(8)

    internal fun actionFor(request: AgentRequest): AgentAction {
        val goal = request.goal.trim()
        val lower = goal.lowercase()
        val taskRequirements = AgentTaskRequirementAnalyzer.analyze(goal)
        notificationReplyAction(request)?.let { return it }
        deterministicLocalAction(request)?.let { return it }
        explicitCallableTargetAction(request)?.let { return it }
        return when {
            lower == "back" || lower.contains("go back") -> AgentAction(
                id = "go-back",
                kind = AgentActionKind.BACK,
                target = request.screen.foregroundApp,
                risk = AgentRisk.LOW,
                status = AgentActionStatus.PENDING_CONFIRMATION,
                description = "Go back one screen"
            )
            lower == "lock screen" ||
                lower == "turn off screen" ||
                lower.contains("lock the phone") -> AgentAction(
                    id = "lock-screen",
                    kind = AgentActionKind.LOCK_SCREEN,
                    target = "Screen Lock",
                    risk = AgentRisk.MEDIUM,
                    status = AgentActionStatus.PENDING_CONFIRMATION,
                    description = "Lock the phone screen"
                )
            lower.contains("save screen") ||
                lower.contains("remember screen") ||
                lower.contains("capture screen to knowledge") -> AgentAction(
                id = "save-screen-knowledge",
                kind = AgentActionKind.SAVE_SCREEN_KNOWLEDGE,
                target = request.screen.foregroundApp,
                risk = AgentRisk.LOW,
                status = AgentActionStatus.PENDING_CONFIRMATION,
                description = "Save current screen to Agent knowledge"
            )
            lower.contains("read screen") || lower.contains("scan screen") -> AgentAction(
                id = "read-screen",
                kind = AgentActionKind.READ_SCREEN,
                target = request.screen.foregroundApp,
                risk = AgentRisk.LOW,
                status = AgentActionStatus.PENDING_CONFIRMATION,
                description = "Read current screen structure"
            )
            lower.contains("read notifications") || lower.contains("scan notifications") -> AgentAction(
                id = "read-notifications",
                kind = AgentActionKind.CALL_NATIVE_TOOL,
                target = "Notification Context",
                risk = AgentRisk.MEDIUM,
                status = AgentActionStatus.PENDING_CONFIRMATION,
                description = "Read current notification context",
                parameters = mapOf(
                    "tool_id" to AgentNotificationNativeTools.NOTIFICATIONS_LIST,
                    "input_json" to AgentNativeJsonCodec.stringify(mapOf("limit" to 6))
                )
            )
            lower.contains("read sms") ||
                lower.contains("read messages") ||
                lower.contains("read calls") ||
                lower.contains("missed calls") -> AgentAction(
                    id = "read-notifications",
                    kind = AgentActionKind.CALL_NATIVE_TOOL,
                    target = "Communication Notifications",
                    risk = AgentRisk.MEDIUM,
                    status = AgentActionStatus.PENDING_CONFIRMATION,
                    description = "Read current communication notification context",
                    parameters = mapOf(
                        "tool_id" to AgentNotificationNativeTools.NOTIFICATIONS_LIST,
                        "input_json" to AgentNativeJsonCodec.stringify(mapOf("limit" to 6))
                    )
                )
            lower.contains("device status") ||
                lower.contains("phone status") ||
                lower.contains("storage status") ||
                lower.contains("network status") -> AgentAction(
                    id = "read-device-status",
                    kind = AgentActionKind.READ_SCREEN,
                    target = "Device Status",
                    risk = AgentRisk.LOW,
                    status = AgentActionStatus.PENDING_CONFIRMATION,
                    description = "Read current device status"
                )
            lower.startsWith("notify me") ||
                lower.startsWith("create notification") ||
                lower.startsWith("send notification") ||
                lower.startsWith("show notification") -> notificationAction(goal)
            (lower.startsWith("type ") || lower.startsWith("input ")) && lower.contains(" into ") ->
                namedTextInputAction(request)
            lower.startsWith("type ") -> AgentAction(
                id = "type-text",
                kind = AgentActionKind.TYPE_TEXT,
                target = request.screen.foregroundApp,
                risk = AgentRisk.MEDIUM,
                status = AgentActionStatus.PENDING_CONFIRMATION,
                description = "Type text into the focused field",
                parameters = mapOf("text" to goal.removePrefix("type ").trim())
            )
            lower.contains("tap first") || lower.contains("click first") -> {
                val firstElement = request.screen.clickableElements.firstOrNull()
                AgentAction(
                    id = "tap-first-action",
                    kind = AgentActionKind.TAP,
                    target = firstElement?.label?.ifBlank { request.screen.foregroundApp } ?: request.screen.foregroundApp,
                    risk = AgentRisk.MEDIUM,
                    status = AgentActionStatus.PENDING_CONFIRMATION,
                    description = "Tap the first clickable element",
                    parameters = mapOf(
                        "bounds" to firstElement?.bounds.orEmpty(),
                        "element_origin" to firstElement?.origin?.name.orEmpty(),
                        "element_role" to firstElement?.visualRole?.name.orEmpty(),
                        "element_confidence" to firstElement?.confidence?.toString().orEmpty()
                    )
                )
            }
            lower.startsWith("tap ") || lower.startsWith("click ") -> namedTapAction(request)
            lower.startsWith("long press ") || lower.startsWith("press and hold ") -> namedLongPressAction(request)
            lower.contains("swipe up") -> AgentAction(
                id = "swipe-up",
                kind = AgentActionKind.SWIPE,
                target = request.screen.foregroundApp,
                risk = AgentRisk.LOW,
                status = AgentActionStatus.PENDING_CONFIRMATION,
                description = "Swipe up on the current screen",
                parameters = mapOf("from_x" to "540", "from_y" to "1700", "to_x" to "540", "to_y" to "700")
            )
            lower.contains("cloud") ||
                lower.contains("gpt") ||
                lower.contains("deepseek") ||
                lower.contains("gemini") ||
                lower.contains("qwen") -> if (taskRequirements.localOnly) {
                    informationQueryAction(request) ?: unavailableReasoningAction(request)
                } else {
                    connectorAction(request, "cloud-models", "Send task to cloud model")
                }
            lower.contains("codex") -> connectorActionForAlias(request, "codex", "Send task to Codex")
            lower.contains("claude") -> connectorActionForAlias(request, "claude-code", "Send task to Claude Code")
            lower.contains("hermes") -> connectorActionForAlias(request, "hermes", "Send task to Hermes")
            lower.contains("home assistant") ||
                lower.contains("smart home") ||
                lower.contains("device") ||
                request.targets.any {
                    it.kind == AgentConnectorKind.DEVICE && request.goal.contains(it.title, ignoreCase = true)
                } -> deviceAction(request)
            isInformationQuery(goal) -> informationQueryAction(request)
                ?: unavailableReasoningAction(request)
            else -> informationQueryAction(request)
                ?: unavailableReasoningAction(request)
        }
    }

    internal fun androidSystemNativeToolAction(request: AgentRequest): AgentAction? {
        val goal = request.goal.trim()
        val lower = goal.lowercase(Locale.US)
        val now = System.currentTimeMillis()
        val phoneWebSearchQuery = phoneWebSearchQuery(goal, lower)
        val batteryReadIntent = lower.hasAny(
            "battery status", "phone battery", "current battery level", "how much battery",
            "\u624b\u673a\u7535\u91cf", "\u624b\u673a\u7535\u6c60", "\u7535\u6c60\u7535\u91cf", "\u7535\u91cf\u591a\u5c11",
            "\u67e5\u770b\u7535\u91cf", "\u67e5\u8be2\u7535\u91cf", "\u67e5\u7535\u91cf"
        ) || (
            lower.hasAny("battery", "\u7535\u91cf", "\u7535\u6c60") &&
                lower.hasAny(
                    "read", "check", "show", "current", "how much", "status",
                    "\u8bfb\u53d6", "\u67e5\u770b", "\u67e5\u8be2", "\u5f53\u524d", "\u591a\u5c11"
                ) &&
                !lower.hasAny(
                    "battery saver", "power saving", "battery threshold", "battery settings",
                    "\u7701\u7535", "\u9608\u503c", "\u7535\u6c60\u8bbe\u7f6e"
                )
            )
        val selected: Pair<String, JSONObject> = when {
            lower.hasAny(
                "turn on flashlight", "turn on the flashlight", "switch on flashlight", "switch on the flashlight",
                "open flashlight", "flashlight on", "turn on torch", "turn on the torch", "switch on torch", "torch on",
                "\u6253\u5f00\u624b\u7535\u7b52", "\u5f00\u542f\u624b\u7535\u7b52", "\u6253\u5f00\u95ea\u5149\u706f", "\u5f00\u542f\u95ea\u5149\u706f"
            ) -> AgentHardwareNativeTools.FLASHLIGHT_SET to JSONObject().put("enabled", true)
            lower.hasAny(
                "turn off flashlight", "turn off the flashlight", "switch off flashlight", "switch off the flashlight",
                "close flashlight", "flashlight off", "turn off torch", "turn off the torch", "switch off torch", "torch off",
                "\u5173\u95ed\u624b\u7535\u7b52", "\u5173\u6389\u624b\u7535\u7b52", "\u5173\u95ed\u95ea\u5149\u706f", "\u5173\u6389\u95ea\u5149\u706f"
            ) -> AgentHardwareNativeTools.FLASHLIGHT_SET to JSONObject().put("enabled", false)
            batteryReadIntent ->
                AgentHardwareNativeTools.BATTERY_STATUS to JSONObject()
            lower.hasAny("power status", "battery saver status", "power saving status", "\u7535\u6e90\u72b6\u6001", "\u7701\u7535\u6a21\u5f0f\u72b6\u6001", "\u67e5\u770b\u7701\u7535\u6a21\u5f0f") ->
                AgentHardwareNativeTools.POWER_STATUS to JSONObject()
            lower.hasAny(
                "phone memory", "phone ram", "device memory", "device ram", "available ram", "free ram", "ram status",
                "\u624b\u673a\u5185\u5b58", "\u8bbe\u5907\u5185\u5b58", "\u8fd0\u884c\u5185\u5b58", "\u53ef\u7528\u5185\u5b58", "\u5269\u4f59\u5185\u5b58",
                "\u5185\u5b58\u5360\u7528", "\u5185\u5b58\u4f7f\u7528", "\u67e5\u5185\u5b58", "\u67e5\u770b\u5185\u5b58", "\u67e5\u8be2\u5185\u5b58"
            ) -> AgentHardwareNativeTools.MEMORY_STATUS to JSONObject()
            lower.hasAny("storage status", "phone storage", "available storage", "free storage", "\u624b\u673a\u5b58\u50a8", "\u5b58\u50a8\u72b6\u6001", "\u5269\u4f59\u5b58\u50a8", "\u5269\u4f59\u7a7a\u95f4") ->
                AgentHardwareNativeTools.STORAGE_STATUS to JSONObject()
            lower.hasAny("network status", "phone network", "active network", "\u624b\u673a\u7f51\u7edc\u72b6\u6001", "\u5f53\u524d\u7f51\u7edc", "\u7f51\u7edc\u8fde\u63a5\u72b6\u6001") ->
                AgentHardwareNativeTools.NETWORK_STATUS to JSONObject()
            phoneWebSearchQuery != null ->
                AgentWebIntelligenceNativeTools.SEARCH to JSONObject()
                    .put("query", phoneWebSearchQuery)
                    .put("limit", 8)
                    .put("engine_fanout", 18)
                    .put("timeout_ms", 15_000)
            lower.hasAny("current location", "phone location", "where am i", "\u5f53\u524d\u4f4d\u7f6e", "\u624b\u673a\u4f4d\u7f6e", "\u6211\u5728\u54ea\u91cc", "\u83b7\u53d6\u4f4d\u7f6e") ->
                AgentHardwareNativeTools.LOCATION_FOREGROUND_READ to JSONObject().put("timeout_ms", 10_000)
            lower.hasAny("list sensors", "device sensors", "sensor list", "\u5217\u51fa\u4f20\u611f\u5668", "\u624b\u673a\u4f20\u611f\u5668", "\u4f20\u611f\u5668\u5217\u8868") ->
                AgentHardwareNativeTools.SENSORS_LIST to JSONObject().put("limit", 64)
            lower.hasAny("sample sensor", "read sensor", "sensor sample", "\u8bfb\u53d6\u4f20\u611f\u5668", "\u4f20\u611f\u5668\u6570\u636e", "\u91c7\u6837\u4f20\u611f\u5668") ||
                (lower.contains("\u8bfb\u53d6") && lower.contains("\u4f20\u611f\u5668")) ->
                AgentHardwareNativeTools.SENSOR_SAMPLE to JSONObject()
                    .put("type", sensorTypeFromGoal(lower))
                    .put("timeout_ms", 5_000)
            lower.hasAny("bluetooth status", "is bluetooth on", "\u84dd\u7259\u72b6\u6001", "\u84dd\u7259\u662f\u5426\u6253\u5f00") ->
                AgentHardwareNativeTools.BLUETOOTH_STATUS to JSONObject()
            lower.hasAny("discover bluetooth", "scan bluetooth", "nearby bluetooth", "\u626b\u63cf\u84dd\u7259", "\u9644\u8fd1\u84dd\u7259", "\u53d1\u73b0\u84dd\u7259\u8bbe\u5907") ->
                AgentHardwareNativeTools.BLUETOOTH_DISCOVERY_FOREGROUND to JSONObject().put("timeout_ms", 10_000).put("limit", 16)
            lower.hasAny("open bluetooth pairing", "pair bluetooth", "\u6253\u5f00\u84dd\u7259\u914d\u5bf9", "\u914d\u5bf9\u84dd\u7259") ->
                AgentHardwareNativeTools.BLUETOOTH_PAIRING_HANDOFF to JSONObject()
            lower.hasAny("nfc status", "is nfc on", "\u67e5\u770bnfc", "nfc\u72b6\u6001", "nfc\u662f\u5426\u6253\u5f00") ->
                AgentHardwareNativeTools.NFC_STATUS to JSONObject()
            lower.startsWith("search installed apps ") || lower.startsWith("find installed apps ") ||
                lower.startsWith("\u641c\u7d22\u5df2\u5b89\u88c5\u5e94\u7528") || lower.startsWith("\u67e5\u627e\u5df2\u5b89\u88c5\u5e94\u7528") -> {
                val query = goal.replace(
                    Regex("^(?i:search installed apps|find installed apps)\\s*|^(?:\\u641c\\u7d22\\u5df2\\u5b89\\u88c5\\u5e94\\u7528|\\u67e5\\u627e\\u5df2\\u5b89\\u88c5\\u5e94\\u7528)\\s*"),
                    ""
                ).trim()
                AgentHardwareNativeTools.INSTALLED_APPS_LIST to JSONObject().put("query", query).put("limit", 100)
            }
            lower.hasAny("list installed apps", "installed applications", "installed app list", "\u5df2\u5b89\u88c5\u5e94\u7528", "\u5e94\u7528\u5217\u8868", "\u5217\u51fa\u5df2\u5b89\u88c5app") ->
                AgentHardwareNativeTools.INSTALLED_APPS_LIST to JSONObject().put("query", "").put("limit", 100)
            Regex("(?:package detail|package info|app package)\\s+([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+)", RegexOption.IGNORE_CASE).find(goal) != null -> {
                val packageName = Regex("([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+)").find(goal)?.value.orEmpty()
                AgentHardwareNativeTools.PACKAGE_DETAIL to JSONObject().put("package_name", packageName)
            }
            lower.hasAny("call state", "incoming call", "\u6765\u7535\u72b6\u6001", "\u901a\u8bdd\u72b6\u6001", "\u662f\u5426\u6765\u7535") ->
                AgentAndroidSystemNativeTools.TELEPHONY_CALL_STATE to JSONObject()
            lower.hasAny("monitor incoming call", "observe call state", "\u76d1\u542c\u6765\u7535", "\u76d1\u542c\u7535\u8bdd", "\u7b49\u5f85\u6765\u7535") ->
                AgentAndroidSystemNativeTools.TELEPHONY_CALL_STATE_OBSERVE to JSONObject().put("timeout_ms", 30_000)
            lower.hasAny("phone service", "telephony status", "mobile service", "\u7535\u8bdd\u72b6\u6001", "\u624b\u673a\u4fe1\u53f7", "\u8fd0\u8425\u5546", "\u79fb\u52a8\u7f51\u7edc\u72b6\u6001") ->
                AgentAndroidSystemNativeTools.TELEPHONY_STATUS to JSONObject()
            lower.hasAny("recent sms", "read sms", "sms list", "\u67e5\u770b\u77ed\u4fe1", "\u8bfb\u53d6\u77ed\u4fe1", "\u6700\u8fd1\u77ed\u4fe1", "\u77ed\u4fe1\u5217\u8868") ->
                AgentAndroidSystemNativeTools.SMS_LIST to JSONObject().put("limit", 30)
            lower.hasAny("start wifi scan", "rescan wifi", "\u91cd\u65b0\u626b\u63cfwifi", "\u5f00\u59cb\u626b\u63cfwifi") ->
                AgentAndroidSystemNativeTools.WIFI_SCAN_START to JSONObject()
            lower.hasAny("scan wifi", "nearby wifi", "wi-fi scan", "\u626b\u63cfwifi", "\u9644\u8fd1wifi", "\u67e5\u627ewifi") ->
                AgentAndroidSystemNativeTools.WIFI_SCAN_RESULTS to JSONObject().put("limit", 30)
            lower.hasAny("wifi status", "wi-fi status", "\u67e5\u770bwifi", "wifi\u72b6\u6001", "\u65e0\u7ebf\u7f51\u7edc\u72b6\u6001") ->
                AgentAndroidSystemNativeTools.WIFI_STATUS to JSONObject()
            lower.hasAny("open wifi settings", "open internet panel", "\u6253\u5f00wifi", "\u6253\u5f00\u7f51\u7edc\u8bbe\u7f6e") ->
                AgentAndroidSystemNativeTools.WIFI_PANEL_OPEN to JSONObject()
            lower.hasAny("open hotspot settings", "hotspot settings", "\u6253\u5f00\u70ed\u70b9", "\u70ed\u70b9\u8bbe\u7f6e") ->
                AgentAndroidSystemNativeTools.WIFI_HOTSPOT_PANEL_OPEN to JSONObject()
            lower.hasAny("audio status", "volume status", "\u97f3\u91cf\u72b6\u6001", "\u67e5\u770b\u97f3\u91cf", "\u5f53\u524d\u97f3\u91cf") ->
                AgentAndroidSystemNativeTools.AUDIO_STATUS to JSONObject()
            lower.hasAny("biometric status", "fingerprint status", "\u751f\u7269\u8bc6\u522b\u72b6\u6001", "\u6307\u7eb9\u72b6\u6001", "\u662f\u5426\u652f\u6301\u6307\u7eb9") ->
                AgentAndroidSystemNativeTools.BIOMETRIC_STATUS to JSONObject()
            lower.hasAny("open biometric enrollment", "enroll fingerprint", "\u5f55\u5165\u6307\u7eb9", "\u6253\u5f00\u751f\u7269\u8bc6\u522b\u8bbe\u7f6e") ->
                AgentAndroidSystemNativeTools.BIOMETRIC_ENROLLMENT_OPEN to JSONObject()
            lower.hasAny("vpn status", "\u67e5\u770bvpn", "vpn\u72b6\u6001", "\u662f\u5426\u8fde\u63a5vpn") ->
                AgentAndroidSystemNativeTools.VPN_STATUS to JSONObject()
            lower.hasAny("request vpn permission", "open vpn consent", "\u8bf7\u6c42vpn\u6743\u9650", "\u6253\u5f00vpn\u6388\u6743") ->
                AgentAndroidSystemNativeTools.VPN_CONSENT_OPEN to JSONObject()
            lower.hasAny("device policy status", "device owner status", "\u8bbe\u5907\u7ba1\u7406\u72b6\u6001", "\u8bbe\u5907\u6240\u6709\u8005\u72b6\u6001") ->
                AgentAndroidSystemNativeTools.DEVICE_POLICY_STATUS to JSONObject()
            lower.hasAny("lock this phone", "lock device", "\u9501\u5b9a\u624b\u673a", "\u9501\u5c4f") ->
                AgentAndroidSystemNativeTools.DEVICE_POLICY_LOCK to JSONObject()
            lower.hasAny("reboot this phone", "reboot device", "\u91cd\u542f\u624b\u673a", "\u91cd\u542f\u8bbe\u5907") ->
                AgentAndroidSystemNativeTools.DEVICE_POLICY_REBOOT to JSONObject()
            lower.hasAny("list calendars", "calendar list", "\u65e5\u5386\u5217\u8868", "\u6709\u54ea\u4e9b\u65e5\u5386") ->
                AgentAndroidSystemNativeTools.CALENDARS_LIST to JSONObject()
            lower.hasAny("calendar events", "schedule", "agenda", "\u67e5\u770b\u65e5\u7a0b", "\u6700\u8fd1\u65e5\u7a0b", "\u4eca\u5929\u65e5\u7a0b", "\u65e5\u7a0b\u5b89\u6392") ->
                AgentAndroidSystemNativeTools.CALENDAR_EVENTS_QUERY to JSONObject()
                    .put("start_epoch_ms", now - 24L * 60L * 60L * 1000L)
                    .put("end_epoch_ms", now + 7L * 24L * 60L * 60L * 1000L)
                    .put("limit", 50)
            lower.startsWith("search contacts ") || lower.startsWith("find contact ") ||
                lower.startsWith("\u641c\u7d22\u8054\u7cfb\u4eba") || lower.startsWith("\u67e5\u627e\u8054\u7cfb\u4eba") || lower.startsWith("\u67e5\u8054\u7cfb\u4eba") -> {
                val query = goal.replace(Regex("^(?i:search contacts|find contact)\\s*|^(?:\u641c\u7d22\u8054\u7cfb\u4eba|\u67e5\u627e\u8054\u7cfb\u4eba|\u67e5\u8054\u7cfb\u4eba)\\s*"), "").trim()
                AgentAndroidSystemNativeTools.CONTACTS_SEARCH to JSONObject().put("query", query).put("limit", 30)
            }
            Regex("(?:volume|\u97f3\u91cf)[^0-9]{0,12}(\\d{1,3})", RegexOption.IGNORE_CASE).find(goal) != null -> {
                val percent = Regex("(\\d{1,3})").find(goal)?.groupValues?.get(1)?.toIntOrNull()?.coerceIn(0, 100) ?: 50
                AgentAndroidSystemNativeTools.AUDIO_VOLUME_SET to JSONObject().put("stream", audioStreamFromGoal(lower)).put("percent", percent)
            }
            lower.hasAny("unmute phone", "unmute media", "\u53d6\u6d88\u9759\u97f3", "\u6062\u590d\u58f0\u97f3") ->
                AgentAndroidSystemNativeTools.AUDIO_MUTE_SET to JSONObject().put("stream", audioStreamFromGoal(lower)).put("muted", false)
            lower.hasAny("mute phone", "mute media", "\u624b\u673a\u9759\u97f3", "\u5a92\u4f53\u9759\u97f3") ->
                AgentAndroidSystemNativeTools.AUDIO_MUTE_SET to JSONObject().put("stream", audioStreamFromGoal(lower)).put("muted", true)
            Regex("(?:dial|\u62e8\u53f7|\u6253\u7535\u8bdd\u7ed9)\\s*([+0-9][0-9 ()-]{2,31})", RegexOption.IGNORE_CASE).find(goal) != null -> {
                val number = Regex("([+0-9][0-9 ()-]{2,31})").find(goal)?.groupValues?.get(1).orEmpty().trim()
                AgentAndroidSystemNativeTools.TELEPHONY_DIAL_HANDOFF to JSONObject().put("phone_number", number)
            }
            Regex("(?:send sms to|\u7ed9)\\s*([+0-9][0-9 ()-]{2,31})\\s*(?:send|\u53d1\u77ed\u4fe1|\u53d1\u9001)?\\s*[:\uff1a]?\\s*(.+)", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)).find(goal) != null -> {
                val match = Regex("(?:send sms to|\u7ed9)\\s*([+0-9][0-9 ()-]{2,31})\\s*(?:send|\u53d1\u77ed\u4fe1|\u53d1\u9001)?\\s*[:\uff1a]?\\s*(.+)", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)).find(goal)
                AgentAndroidSystemNativeTools.SMS_SEND to JSONObject()
                    .put("phone_number", match?.groupValues?.getOrNull(1).orEmpty().trim())
                    .put("message", match?.groupValues?.getOrNull(2).orEmpty().trim())
            }
            Regex("(?:download status|\u67e5\u770b\u4e0b\u8f7d)\\s*(\\d+)", RegexOption.IGNORE_CASE).find(goal) != null -> {
                val id = Regex("(\\d+)").find(goal)?.value?.toLongOrNull() ?: 0L
                AgentAndroidSystemNativeTools.DOWNLOAD_QUERY to JSONObject().put("download_id", id)
            }
            Regex("(?:remove download|delete download|\u5220\u9664\u4e0b\u8f7d)\\s*(\\d+)", RegexOption.IGNORE_CASE).find(goal) != null -> {
                val id = Regex("(\\d+)").find(goal)?.value?.toLongOrNull() ?: 0L
                AgentAndroidSystemNativeTools.DOWNLOAD_REMOVE to JSONObject().put("download_id", id)
            }
            lower.contains("https://") && lower.hasAny("download", "\u4e0b\u8f7d") -> {
                val url = Regex("https://\\S+", RegexOption.IGNORE_CASE).find(goal)?.value.orEmpty().trimEnd('.', ',', '\u3002')
                AgentAndroidSystemNativeTools.DOWNLOAD_ENQUEUE to JSONObject().put("url", url)
            }
            else -> return null
        }
        return nativeToolAction(request, selected.first, selected.second)
    }

    internal fun nativeToolAction(request: AgentRequest, toolId: String, input: JSONObject): AgentAction? {
        val descriptor = request.runtimeContext.nativeTools.firstOrNull { it.id == toolId } ?: return null
        val risk = when (descriptor.risk) {
            AgentNativeToolRisk.LOW -> AgentRisk.LOW
            AgentNativeToolRisk.MEDIUM -> AgentRisk.MEDIUM
            AgentNativeToolRisk.HIGH -> AgentRisk.HIGH
            AgentNativeToolRisk.BLOCKED -> AgentRisk.BLOCKED
        }
        return AgentAction(
            id = "native-${descriptor.id.substringAfterLast('.')}-${request.goal.hashCode().toUInt()}",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = descriptor.title,
            risk = risk,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = descriptor.title,
            parameters = mapOf(
                "tool_id" to descriptor.id,
                "tool_version" to descriptor.version,
                "native_tool_risk" to descriptor.risk.wireValue,
                "_signalasi_native_tool_location" to descriptor.location.wireValue,
                "_signalasi_execution_device_id" to input.optString("desktop_id"),
                "response_language" to configuredResponseLanguageCode(request.goal),
                "input_json" to input.toString()
            )
        )
    }

    internal fun String.hasAny(vararg values: String): Boolean = values.any(::contains)

    internal fun audioStreamFromGoal(goal: String): String = when {
        goal.hasAny("ring", "ringer", "\u94c3\u58f0") -> "ring"
        goal.hasAny("alarm", "\u95f9\u949f") -> "alarm"
        goal.hasAny("notification", "\u901a\u77e5") -> "notification"
        goal.hasAny("call", "\u901a\u8bdd") -> "voice_call"
        else -> "music"
    }

    internal fun sensorTypeFromGoal(goal: String): String = when {
        goal.hasAny("gyroscope", "\u9640\u87ba\u4eea") -> "gyroscope"
        goal.hasAny("gravity", "\u91cd\u529b") -> "gravity"
        goal.hasAny("light", "\u5149\u7ebf", "\u5149\u7167") -> "light"
        goal.hasAny("proximity", "\u8ddd\u79bb") -> "proximity"
        goal.hasAny("pressure", "\u6c14\u538b") -> "pressure"
        goal.hasAny("magnetic", "compass", "\u78c1\u573a", "\u6307\u5357\u9488") -> "magnetic_field"
        goal.hasAny("rotation", "\u65cb\u8f6c") -> "rotation_vector"
        goal.hasAny("temperature", "\u6e29\u5ea6") -> "ambient_temperature"
        goal.hasAny("humidity", "\u6e7f\u5ea6") -> "relative_humidity"
        else -> "accelerometer"
    }

    internal fun phoneWebSearchQuery(goal: String, lower: String): String? {
        val explicitSearch = lower.hasAny(
            "search the web", "web search", "search online", "look up online",
            "\u8054\u7f51\u641c\u7d22", "\u7f51\u4e0a\u641c\u7d22", "\u7f51\u7edc\u641c\u7d22", "\u767e\u5ea6\u641c\u7d22"
        )
        return if (explicitSearch) goal.replace("%27", "'", ignoreCase = true).trim() else null
    }

    internal fun informationQueryAction(request: AgentRequest): AgentAction? {
        manualSelectedConnectorAction(request)?.let { return it }
        val routing = context?.let { appContext ->
            AgentResourceRouter(appContext).route(
                goal = request.goal,
                targets = request.targets,
                tools = request.runtimeContext.systemTools,
                nativeTools = request.runtimeContext.nativeTools
            )
        }
        val selection = AgentConnectorRouteSelector.select(
            targets = request.targets,
            decision = routing
        ) ?: return null
        val currentInformation = selection.decision?.requirements?.liveDataRequired == true
        return connectorAction(
            request,
            selection.target.id,
            if (currentInformation) {
                "Get current information from ${selection.target.title}"
            } else {
                "Ask ${selection.target.title}"
            },
            selection.decision
        )
    }

    internal fun manualSelectedConnectorAction(request: AgentRequest): AgentAction? {
        val appContext = context ?: return null
        val selection = AgentModelSelectionSettings.selection(
            appContext,
            request.conversationContext.conversationId
        )
        if (selection.mode != AgentModelSelectionMode.MANUAL || selection.targetId.isBlank()) return null
        val target = request.targets.firstOrNull { it.id == selection.targetId }
        val displayName = selection.displayName
            .ifBlank { target?.title.orEmpty() }
            .ifBlank { selection.targetId }
        val action = connectorAction(
            request = request,
            connectorId = selection.targetId,
            description = "Ask $displayName"
        )
        return action.copy(
            target = displayName,
            parameters = action.parameters + mapOf(
                "manual_target_locked" to "true",
                "manual_model_id" to selection.modelId
            )
        )
    }

    internal fun directDeviceStatusAction(request: AgentRequest): AgentAction? {
        val lower = request.goal.lowercase(Locale.US)
        if (!lower.hasAny(
                "device status", "phone status", "storage status", "network status",
                "\u8bbe\u5907\u72b6\u6001", "\u624b\u673a\u72b6\u6001", "\u5b58\u50a8\u72b6\u6001", "\u7f51\u7edc\u72b6\u6001"
            )
        ) return null
        return AgentAction(
            id = "read-device-status",
            kind = AgentActionKind.READ_SCREEN,
            target = "Device Status",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Read current device status"
        )
    }

    internal fun explicitCallableTargetAction(request: AgentRequest): AgentAction? {
        val normalizedGoal = request.goal.lowercase(Locale.US)
        val target = request.targets
            .asSequence()
            .filter(AgentConnectorRouteSelector::isDeliverable)
            .filter { it.kind != AgentConnectorKind.DEVICE }
            .sortedByDescending { it.title.length }
            .firstOrNull { candidate ->
                val aliases = buildList {
                    add(candidate.id.lowercase(Locale.US))
                    add(candidate.id.substringAfterLast(':').lowercase(Locale.US))
                    add(candidate.title.lowercase(Locale.US))
                }.map(String::trim).filter { it.length >= 3 }.distinct()
                aliases.any(normalizedGoal::contains)
            } ?: return null
        val explicitResource = AgentResourceCatalog.build(
            request.targets,
            request.runtimeContext.systemTools,
            request.runtimeContext.nativeTools
        ).firstOrNull { it.targetId == target.id }
        if (AgentTaskRequirementAnalyzer.analyze(request.goal).localOnly &&
            explicitResource?.location == AgentResourceLocation.CLOUD
        ) {
            return unavailableReasoningAction(request)
        }
        val routing = context?.let { appContext ->
            AgentResourceRouter(appContext).route(
                goal = request.goal,
                targets = request.targets,
                tools = request.runtimeContext.systemTools,
                nativeTools = request.runtimeContext.nativeTools
            )
        }
        val connectorRouting = AgentConnectorRouteSelector.select(
            targets = request.targets,
            decision = routing,
            preferredTargetId = target.id
        )?.decision
        return connectorAction(request, target.id, "Send task to ${target.title}", connectorRouting)
    }

    internal fun unavailableReasoningAction(request: AgentRequest): AgentAction = AgentAction(
        id = "connector-unavailable-${request.goal.hashCode().toUInt()}",
        kind = AgentActionKind.CALL_CONNECTOR,
        target = "Agent or model",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.PENDING_CONFIRMATION,
        description = "Report that no reasoning provider is configured",
        parameters = mapOf(
            "connector_id" to UNAVAILABLE_REASONING_CONNECTOR_ID,
            "prompt" to request.goal
        ),
        requiresConfirmation = false
    )

    internal fun isInformationQuery(goal: String): Boolean {
        val normalized = goal.trim().lowercase(Locale.US)
        if (normalized.endsWith('?') || normalized.endsWith('\uFF1F')) return true
        return INFORMATION_QUERY_PREFIXES.any(normalized::startsWith) ||
            CURRENT_INFORMATION_TERMS.any(normalized::contains)
    }

    internal fun notificationReplyAction(request: AgentRequest): AgentAction? {
        val englishMatch = Regex(
            "^(?:reply(?: to)? notification)\\s+(.+?)\\s*::\\s*(.+)$",
            RegexOption.IGNORE_CASE
        ).matchEntire(request.goal.trim())
        val chineseMatch = Regex(
            "^\\u56de\\u590d\\u901a\\u77e5\\s+(.+?)\\s*::\\s*(.+)$"
        ).matchEntire(request.goal.trim())
        val chineseLatestMatch = Regex(
            "^\\u56de\\u590d\\u6700\\u65b0\\u901a\\u77e5\\s*::\\s*(.+)$"
        ).matchEntire(request.goal.trim())
        val query = when {
            englishMatch != null -> englishMatch.groupValues[1].trim()
            chineseMatch != null -> chineseMatch.groupValues[1].trim()
            chineseLatestMatch != null -> "latest"
            else -> return null
        }
        val replyText = when {
            englishMatch != null -> englishMatch.groupValues[2]
            chineseMatch != null -> chineseMatch.groupValues[2]
            else -> chineseLatestMatch!!.groupValues[1]
        }.trim().take(MAX_NOTIFICATION_REPLY_CHARACTERS)
        val replyable = request.screen.notifications.items.filter { it.canReply }
        val item = when {
            query.equals("latest", ignoreCase = true) -> replyable.firstOrNull()
            else -> replyable.firstOrNull { it.key == query } ?:
                replyable.firstOrNull { it.packageName.equals(query, ignoreCase = true) } ?:
                replyable.firstOrNull { it.title.equals(query, ignoreCase = true) } ?:
                replyable.firstOrNull {
                    it.packageName.contains(query, ignoreCase = true) ||
                        it.title.contains(query, ignoreCase = true)
                }
        }
        val sensitive = sensitiveFlagsForText(replyText).isNotEmpty() ||
            item?.sensitiveFlags?.isNotEmpty() == true
        val blockedReason = when {
            item == null -> "No matching reply-capable notification is available"
            replyText.isBlank() -> "Notification reply text is missing"
            sensitive -> "Sensitive notification replies are blocked"
            else -> ""
        }
        val risk = if (blockedReason.isNotBlank()) AgentRisk.BLOCKED else AgentRisk.HIGH
        return AgentAction(
            id = "reply-notification",
            kind = AgentActionKind.CALL_NATIVE_TOOL,
            target = item?.title?.ifBlank { item.packageName } ?: query,
            risk = risk,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = if (item == null) {
                "Reply-capable notification '$query' was not found"
            } else {
                "Reply to ${item.title.ifBlank { item.packageName }}"
            },
            parameters = mapOf(
                "tool_id" to AgentNotificationNativeTools.NOTIFICATION_REPLY,
                "input_json" to AgentNativeJsonCodec.stringify(
                    mapOf(
                        "notification_key" to item?.key.orEmpty(),
                        "reply_text" to replyText
                    )
                ),
                "notification_key" to item?.key.orEmpty(),
                "notification_package" to item?.packageName.orEmpty(),
                "blocked_reason" to blockedReason
            )
        )
    }

    internal fun namedTapAction(request: AgentRequest): AgentAction {
        val query = request.goal
            .removePrefixIgnoreCase("tap ")
            .removePrefixIgnoreCase("click ")
            .trim()
        val element = findElementByQuery(request.screen.clickableElements, query)
        return AgentAction(
            id = "tap-named-action",
            kind = AgentActionKind.TAP,
            target = element?.label?.ifBlank { query } ?: query.ifBlank { request.screen.foregroundApp },
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = if (query.isBlank()) "Tap a matching element" else "Tap $query",
            parameters = mapOf(
                "bounds" to element?.bounds.orEmpty(),
                "query" to query,
                "matched_label" to element?.label.orEmpty(),
                "element_origin" to element?.origin?.name.orEmpty(),
                "element_role" to element?.visualRole?.name.orEmpty(),
                "element_confidence" to element?.confidence?.toString().orEmpty()
            )
        )
    }

    internal fun namedLongPressAction(request: AgentRequest): AgentAction {
        val query = request.goal
            .removePrefixIgnoreCase("long press ")
            .removePrefixIgnoreCase("press and hold ")
            .trim()
        val element = findElementByQuery(request.screen.clickableElements, query)
        return AgentAction(
            id = "long-press-named-action",
            kind = AgentActionKind.LONG_PRESS,
            target = element?.label?.ifBlank { query } ?: query.ifBlank { request.screen.foregroundApp },
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = if (query.isBlank()) "Long press a matching element" else "Long press $query",
            parameters = mapOf(
                "bounds" to element?.bounds.orEmpty(),
                "query" to query,
                "matched_label" to element?.label.orEmpty(),
                "element_origin" to element?.origin?.name.orEmpty(),
                "element_role" to element?.visualRole?.name.orEmpty(),
                "element_confidence" to element?.confidence?.toString().orEmpty()
            )
        )
    }

    internal fun namedTextInputAction(request: AgentRequest): AgentAction {
        val goal = request.goal.trim()
        val prefix = if (goal.startsWith("input ", ignoreCase = true)) "input " else "type "
        val payload = goal.drop(prefix.length)
        val splitIndex = payload.lowercase(Locale.US).lastIndexOf(" into ")
        val text = if (splitIndex >= 0) payload.take(splitIndex).trim() else payload.trim()
        val query = if (splitIndex >= 0) payload.drop(splitIndex + " into ".length).trim() else ""
        val field = findElementByQuery(request.screen.inputFields, query)
            ?: request.screen.inputFields.firstOrNull()
        return AgentAction(
            id = "type-into-named-field",
            kind = AgentActionKind.TYPE_TEXT,
            target = field?.label?.ifBlank { query } ?: query.ifBlank { request.screen.foregroundApp },
            risk = AgentRisk.MEDIUM,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = if (query.isBlank()) "Type text into an input field" else "Type text into $query",
            parameters = mapOf(
                "text" to text,
                "field_bounds" to field?.bounds.orEmpty(),
                "query" to query,
                "matched_label" to field?.label.orEmpty(),
                "field_origin" to field?.origin?.name.orEmpty(),
                "field_confidence" to field?.confidence?.toString().orEmpty()
            )
        )
    }

    internal fun findElementByQuery(elements: List<ScreenElement>, query: String): ScreenElement? {
        if (query.isBlank()) return elements.firstOrNull()
        return AgentScreenElementMatcher.resolve(query, elements)
    }

    internal fun connectorAction(
        request: AgentRequest,
        connectorId: String,
        description: String,
        routing: AgentRoutingDecision? = null
    ): AgentAction {
        val target = request.targets.firstOrNull { it.id == connectorId }
        val requirements = AgentTaskRequirementAnalyzer.analyze(request.goal)
        val executionRisk = AgentCapability.CODE in requirements.capabilities ||
            AgentCapability.TASK_EXECUTION in requirements.capabilities ||
            requirements.executionHorizon != AgentExecutionHorizon.INTERACTIVE
        return AgentAction(
            id = "connector-$connectorId",
            kind = AgentActionKind.CALL_CONNECTOR,
            target = target?.title ?: connectorId,
            risk = if (executionRisk) AgentRisk.MEDIUM else AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = description,
            parameters = buildMap {
                put("connector_id", connectorId)
                put("prompt", request.goal)
                target?.let { callable ->
                    put("connector_kind", callable.kind.name.lowercase(Locale.ROOT))
                    put("connector_adapter_type", callable.adapterType)
                    put("connector_failure_domain", callable.failureDomain)
                }
                put(
                    "_signalasi_desktop_executor_full",
                    (target?.desktopAccessProfile == SignalASILinkProtocol.ACCESS_DESKTOP_EXECUTOR).toString()
                )
                routing?.let { decision ->
                    put("routing_mode", decision.requirements.mode.name)
                    put("routing_requires_live_data", decision.requirements.liveDataRequired.toString())
                    put("routing_local_only", decision.requirements.localOnly.toString())
                    put("routing_estimated_input_tokens", decision.requirements.estimatedInputTokens.toString())
                    put("routing_data_sensitivity", decision.requirements.dataSensitivity.name)
                    put("routing_execution_horizon", decision.requirements.executionHorizon.name)
                    put("routing_battery_percent", decision.environment.batteryPercent.toString())
                    put("routing_power_save", decision.environment.powerSaveMode.toString())
                    put("routing_network_metered", decision.environment.networkMetered.toString())
                    put("routing_network_validated", decision.environment.networkValidated.toString())
                    put("routing_fallback_ids", decision.fallbacks.joinToString(",") { it.resource.targetId })
                    put("routing_score", decision.primary?.score?.toString().orEmpty())
                    put("routing_reasons", decision.primary?.reasons?.joinToString("|").orEmpty())
                    put("task_budget_profile", decision.taskBudget.profile.wireValue)
                    put("task_budget", AgentTaskBudgetJsonCodec.encode(decision.taskBudget).toString())
                }
            }
        )
    }

    internal fun connectorActionForAlias(
        request: AgentRequest,
        alias: String,
        description: String
    ): AgentAction {
        val normalizedAlias = alias.filter(Char::isLetterOrDigit).lowercase(Locale.US)
        val target = request.targets.firstOrNull { candidate ->
            AgentConnectorRouteSelector.isDeliverable(candidate) &&
                candidate.kind != AgentConnectorKind.DEVICE &&
                listOf(candidate.id, candidate.id.substringAfterLast(':'), candidate.title).any { value ->
                    value.filter(Char::isLetterOrDigit).lowercase(Locale.US).contains(normalizedAlias)
                }
        }
        return connectorAction(request, target?.id ?: alias, description)
    }

    internal fun deviceAction(request: AgentRequest): AgentAction {
        val customTarget = request.targets
            .filter { it.kind == AgentConnectorKind.DEVICE && it.id.startsWith(CUSTOM_DEVICE_TARGET_PREFIX) }
            .firstOrNull { request.goal.contains(it.title, ignoreCase = true) }
        val target = customTarget ?: request.targets.firstOrNull {
            it.kind == AgentConnectorKind.DEVICE &&
                it.id == "home-assistant" &&
                it.status == AgentConnectorStatus.AVAILABLE
        } ?: request.targets.firstOrNull {
            it.kind == AgentConnectorKind.DEVICE &&
                it.id.startsWith(CUSTOM_DEVICE_TARGET_PREFIX) &&
                it.status == AgentConnectorStatus.AVAILABLE
        } ?: request.targets.firstOrNull { it.kind == AgentConnectorKind.DEVICE }
        val entityId = context?.let { HomeAssistantDeviceClient.entityIdForPrompt(it, request.goal) }
            ?: HomeAssistantDeviceClient.entityIdForPrompt(request.goal)
        val customConnector = if (target?.id?.startsWith(CUSTOM_DEVICE_TARGET_PREFIX) == true && context != null) {
            CustomDeviceConnectorStore(context).find(target.id.removePrefix(CUSTOM_DEVICE_TARGET_PREFIX))
        } else {
            null
        }
        val risk = customConnector?.risk ?: context?.let { HomeAssistantDeviceClient.riskForPrompt(it, request.goal) }
            ?: HomeAssistantDeviceClient.riskForPrompt(request.goal)
        val lower = request.goal.lowercase(Locale.US)
        val description = when {
            customConnector != null -> "Send command to ${customConnector.name}"
            lower.contains("automation") -> "Trigger a Home Assistant automation"
            lower.contains("script") -> "Run a Home Assistant script"
            lower.contains("scene") -> "Activate a Home Assistant scene"
            else -> "Control a trusted device connector"
        }
        val homeAssistantCall = if (customConnector == null && context != null) {
            HomeAssistantDeviceClient.serviceCallForPrompt(context, request.goal)
        } else {
            null
        }
        if (homeAssistantCall != null) {
            val toolInput = JSONObject()
                .put("service_domain", homeAssistantCall.serviceDomain)
                .put("service", homeAssistantCall.service)
                .put("entity_id", homeAssistantCall.entityId)
                .put("service_data", JSONObject(homeAssistantCall.serviceData))
                .toString()
            return AgentAction(
                id = "home-assistant-service-${AgentNativeJsonCodec.sha256(toolInput).take(16)}",
                kind = AgentActionKind.CALL_NATIVE_TOOL,
                target = homeAssistantCall.entityId,
                risk = risk,
                status = AgentActionStatus.PENDING_CONFIRMATION,
                description = description,
                parameters = mapOf(
                    "tool_id" to AgentHomeAssistantNativeTools.SERVICE_CALL,
                    "input_json" to toolInput,
                    "connector_id" to "home-assistant",
                    "response_language" to configuredResponseLanguageCode(request.goal)
                )
            )
        }
        return AgentAction(
            id = "device-control",
            kind = AgentActionKind.CONTROL_DEVICE,
            target = customConnector?.name ?: entityId.ifBlank { target?.title ?: "Home Assistant" },
            risk = risk,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = description,
            parameters = mapOf(
                "connector_id" to (target?.id ?: "home-assistant"),
                "prompt" to request.goal,
                "entity_id" to entityId,
                "device_risk" to risk.name,
                "custom_device_id" to customConnector?.id.orEmpty()
            )
        )
    }

    internal fun installedAppOpenAction(request: AgentRequest): AgentAction? {
        val query = appOpenQuery(request.goal).takeIf { it.isNotBlank() } ?: return null
        val app = findInstalledApp(request.screen.installedApps, query) ?: return null
        return AgentAction(
            id = "open-installed-app",
            kind = AgentActionKind.OPEN_APP,
            target = app.label,
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Open ${app.label}",
            parameters = mapOf("package" to app.packageName)
        )
    }

    internal fun appOpenQuery(goal: String): String {
        val trimmed = goal.trim()
        val rawQuery = when {
            trimmed.startsWith("open ", ignoreCase = true) ->
                trimmed.removePrefixIgnoreCase("open ").removeSuffixIgnoreCase(" app").trim()
            trimmed.startsWith("launch ", ignoreCase = true) ->
                trimmed.removePrefixIgnoreCase("launch ").removeSuffixIgnoreCase(" app").trim()
            trimmed.startsWith("start ", ignoreCase = true) ->
                trimmed.removePrefixIgnoreCase("start ").removeSuffixIgnoreCase(" app").trim()
            trimmed.startsWith("\u6253\u5f00") -> trimmed.removePrefix("\u6253\u5f00").trim()
            trimmed.startsWith("\u542f\u52a8") -> trimmed.removePrefix("\u542f\u52a8").trim()
            trimmed.startsWith("\u8fd0\u884c") -> trimmed.removePrefix("\u8fd0\u884c").trim()
            else -> ""
        }
        val query = rawQuery
            .removePrefixIgnoreCase("app ")
            .removeSuffix("\u5e94\u7528")
            .trim()
        return if (query.equals("app", ignoreCase = true)) "" else query
    }

    internal fun findInstalledApp(apps: List<InstalledAppInfo>, query: String): InstalledAppInfo? {
        val normalizedQuery = query.normalizeAppName()
        if (normalizedQuery.isBlank()) return null
        return apps.firstOrNull { it.label.normalizeAppName() == normalizedQuery } ?:
            apps.firstOrNull { it.label.normalizeAppName().contains(normalizedQuery) } ?:
            apps.firstOrNull { it.packageName.normalizeAppName().contains(normalizedQuery) }
    }

    internal fun String.removeSuffixIgnoreCase(suffix: String): String =
        if (endsWith(suffix, ignoreCase = true)) dropLast(suffix.length) else this

    internal fun String.normalizeAppName(): String =
        lowercase(Locale.US).replace(Regex("[^\\p{L}\\p{N}]+"), "")

    internal fun notificationAction(goal: String): AgentAction {
        val body = goal
            .removePrefixIgnoreCase("notify me")
            .removePrefixIgnoreCase("create notification")
            .removePrefixIgnoreCase("send notification")
            .removePrefixIgnoreCase("show notification")
            .trim()
            .ifBlank { "Agent task needs your attention" }
        return AgentAction(
            id = "create-local-notification",
            kind = AgentActionKind.CREATE_NOTIFICATION,
            target = "Android Notifications",
            risk = AgentRisk.LOW,
            status = AgentActionStatus.PENDING_CONFIRMATION,
            description = "Create local notification",
            parameters = mapOf(
                "title" to "SignalASI Agent",
                "text" to body
            )
        )
    }

    internal fun riskFor(goal: String): AgentRisk = when {
        containsBlockedGoal(goal) -> AgentRisk.BLOCKED
        containsHighRiskGoal(goal) -> AgentRisk.HIGH
        goal.containsAny(MEDIUM_RISK_GOAL_TERMS) -> AgentRisk.MEDIUM
        else -> AgentRisk.LOW
    }

    internal fun containsBlockedGoal(goal: String): Boolean {
        return goal.containsAny(BLOCKED_GOAL_TERMS)
    }

    internal fun containsHighRiskGoal(goal: String): Boolean {
        return goal.containsAny(HIGH_RISK_GOAL_TERMS)
    }

    internal fun String.containsAny(terms: List<String>): Boolean =
        terms.any { contains(it) }

    companion object {
        private const val MAX_NOTIFICATION_REPLY_CHARACTERS = 2_000
        private const val CUSTOM_DEVICE_TARGET_PREFIX = "custom-device:"
        private val INFORMATION_QUERY_PREFIXES = listOf(
            "what ", "how ", "why ", "who ", "when ", "where ", "which ",
            "tell me ", "explain ", "compare ", "summarize ", "research ", "find out ",
            "\u4ec0\u4e48", "\u600e\u4e48", "\u4e3a\u4ec0\u4e48", "\u8c01", "\u4f55\u65f6", "\u54ea\u91cc", "\u8bf7\u95ee", "\u5e2e\u6211\u67e5"
        )
        private val CURRENT_INFORMATION_TERMS = listOf(
            "weather", "forecast", "news", "latest", "current", "today", "now", "live",
            "\u5929\u6c14", "\u9884\u62a5", "\u65b0\u95fb", "\u6700\u65b0", "\u5f53\u524d", "\u4eca\u5929", "\u73b0\u5728", "\u5b9e\u65f6"
        )
        private val BLOCKED_GOAL_TERMS = listOf(
            "install app",
            "uninstall app",
            "delete app",
            "factory reset",
            "erase phone",
            "clear all data",
            "unlock phone",
            "disable lock",
            "change screen lock",
            "answer call",
            "listen call",
            "record call",
            "send wechat",
            "reply wechat",
            "send message to",
            "authorize login",
            "approve login",
            "grant permission",
            "share password",
            "share private key",
            "export private key",
            "export api key",
            "transfer money",
            "make payment",
            "place order",
            "checkout"
        )

        private val HIGH_RISK_GOAL_TERMS = listOf(
            "delete",
            "clear all",
            "send sms",
            "reply sms",
            "send email",
            "reply email",
            "forward message",
            "post to",
            "publish",
            "upload",
            "make phone call",
            "dial",
            "pay",
            "payment",
            "purchase",
            "order",
            "authorize",
            "grant permission",
            "change security",
            "share private",
            "share password",
            "export key",
            "security setting",
            "location",
            "camera",
            "microphone"
        )

        private val MEDIUM_RISK_GOAL_TERMS = listOf(
            "send",
            "reply",
            "share",
            "copy",
            "paste",
            "download",
            "open file",
            "open app",
            "change setting",
            "edit"
        )
    }
}

object AgentPlanFactory {
    fun singleAction(request: AgentRequest, action: AgentAction): AgentPlan {
        return actions(request, listOf(action))
    }

    fun actions(request: AgentRequest, actions: List<AgentAction>): AgentPlan {
        val plannedActions = collapseDuplicateConnectorCalls(actions).ifEmpty {
            listOf(emptyPlanFallbackAction(request))
        }
        val routeAction = plannedActions.firstOrNull {
            it.kind == AgentActionKind.CALL_CONNECTOR || it.kind == AgentActionKind.CONTROL_DEVICE
        } ?: plannedActions.first()
        val plan = AgentPlan(
            goal = request.goal,
            screen = request.screen,
            steps = listOf(
                AgentStep(1, AgentStepKind.OBSERVE_SCREEN, AgentStepStatus.DONE),
                AgentStep(2, AgentStepKind.ANALYZE_GOAL, AgentStepStatus.DONE),
                AgentStep(3, AgentStepKind.BUILD_PLAN, AgentStepStatus.DONE),
                AgentStep(4, AgentStepKind.CONFIRM_AND_ACT, AgentStepStatus.CURRENT)
            ),
            actions = plannedActions,
            selectedAgentOrModel = selectedAgentOrModel(plannedActions),
            requiredPermissions = plannedActions
                .flatMap { permissionsFor(it, request) }
                .distinctBy { "${it.id}:${it.title}" },
            confirmationRequired = true,
            rollbackStrategy = rollbackStrategyFor(plannedActions),
            expectedResult = expectedResultFor(plannedActions),
            timeoutSeconds = plannedActions.sumOf { timeoutFor(it) }.coerceAtMost(240),
            plannerProfile = "rule-based-local",
            contextDigest = request.runtimeContext.compactSummary().hashCode().toString(),
            route = AgentRouteResolver.resolve(routeAction, request.targets),
            routeRationale = routeRationaleFor(routeAction, request)
        )
        return plan.copy(validation = AgentPlanValidator.validate(plan))
    }

    internal fun emptyPlanFallbackAction(request: AgentRequest): AgentAction {
        val target = AgentConnectorRouteSelector.select(request.targets, decision = null)?.target
        return if (target != null) {
            AgentAction(
                id = "fallback-connector-${request.goal.hashCode().toUInt()}",
                kind = AgentActionKind.CALL_CONNECTOR,
                target = target.title,
                risk = AgentRisk.LOW,
                status = AgentActionStatus.PENDING_CONFIRMATION,
                description = "Ask ${target.title}",
                parameters = mapOf(
                    "connector_id" to target.id,
                    "prompt" to request.goal,
                    "planner_fallback" to "empty_action_plan",
                    "_signalasi_desktop_executor_full" to
                        (target.desktopAccessProfile == SignalASILinkProtocol.ACCESS_DESKTOP_EXECUTOR).toString()
                ),
                requiresConfirmation = false
            )
        } else {
            AgentAction(
                id = "connector-unavailable-${request.goal.hashCode().toUInt()}",
                kind = AgentActionKind.CALL_CONNECTOR,
                target = "Agent or model",
                risk = AgentRisk.LOW,
                status = AgentActionStatus.PENDING_CONFIRMATION,
                description = "Report that no reasoning provider is configured",
                parameters = mapOf(
                    "connector_id" to UNAVAILABLE_REASONING_CONNECTOR_ID,
                    "prompt" to request.goal,
                    "planner_fallback" to "empty_action_plan"
                ),
                requiresConfirmation = false
            )
        }
    }

    internal fun collapseDuplicateConnectorCalls(actions: List<AgentAction>): List<AgentAction> {
        val canonicalIds = mutableMapOf<String, String>()
        val retained = actions.filter { action ->
            if (action.kind != AgentActionKind.CALL_CONNECTOR || action.id == "knowledge-answer") {
                canonicalIds[action.id] = action.id
                true
            } else {
                val connector = action.parameters["connector_id"].orEmpty()
                    .ifBlank { action.target }
                    .trim()
                    .lowercase(Locale.US)
                val key = "${action.kind}:$connector"
                val canonicalId = canonicalIds[key]
                if (canonicalId == null) {
                    canonicalIds[key] = action.id
                    canonicalIds[action.id] = action.id
                    true
                } else {
                    canonicalIds[action.id] = canonicalId
                    false
                }
            }
        }
        val idMap = actions.associate { action ->
            action.id to canonicalIds[action.id].orEmpty().ifBlank { action.id }
        }
        return retained.map { action -> action.remapToolGraphIds(action.id, idMap) }
    }

    internal fun selectedAgentOrModel(actions: List<AgentAction>): String {
        val connectorTargets = actions.asSequence()
            .filter { action ->
                action.kind == AgentActionKind.CALL_CONNECTOR ||
                    action.kind == AgentActionKind.CONTROL_DEVICE
            }
            .map { action -> selectedAgentOrModel(action) }
            .distinct()
            .toList()
        if (connectorTargets.size == 1) return connectorTargets.first()
        val distinctTargets = actions.map { selectedAgentOrModel(it) }.distinct()
        return if (distinctTargets.size == 1) distinctTargets.first() else "Multiple Executors"
    }

    internal fun selectedAgentOrModel(action: AgentAction): String = when (action.kind) {
        AgentActionKind.CALL_CONNECTOR,
        AgentActionKind.CONTROL_DEVICE -> action.target
        AgentActionKind.IMPORT_WEB_KNOWLEDGE -> "Agent Knowledge"
        else -> "Mobile Executor"
    }

    internal fun permissionsFor(action: AgentAction, request: AgentRequest): List<AgentPermissionRequirement> {
        val permissions = mutableListOf<AgentPermissionRequirement>()
        when (action.kind) {
            AgentActionKind.READ_SCREEN,
            AgentActionKind.SAVE_SCREEN_KNOWLEDGE,
            AgentActionKind.COPY_SCREEN_TEXT,
            AgentActionKind.TAP,
            AgentActionKind.LONG_PRESS,
            AgentActionKind.TYPE_TEXT,
            AgentActionKind.DELETE_TEXT,
            AgentActionKind.PASTE_TEXT,
            AgentActionKind.SWIPE,
            AgentActionKind.BACK,
            AgentActionKind.HOME,
            AgentActionKind.RECENTS,
            AgentActionKind.LOCK_SCREEN -> permissions += AgentPermissionRequirement(
                id = "accessibility_service",
                title = "Screen Agent permission",
                granted = request.screen.isAccessibilityEnabled
            )
            AgentActionKind.OPEN_APP,
            AgentActionKind.OPEN_URL,
            AgentActionKind.SET_ALARM -> permissions += intentPermissionFor(action)
            AgentActionKind.CREATE_NOTIFICATION -> permissions += AgentPermissionRequirement(
                id = "post_notification",
                title = "Post local notification",
                granted = true
            )
            AgentActionKind.REPLY_NOTIFICATION -> permissions += AgentPermissionRequirement(
                id = "notification_direct_reply",
                title = "Notification direct reply",
                granted = request.screen.notifications.hasAccess &&
                    request.screen.notifications.items.any {
                        it.key == action.parameters["notification_key"] && it.canReply
                    }
            )
            AgentActionKind.CALL_NATIVE_TOOL -> {
                val descriptor = request.runtimeContext.nativeTools.firstOrNull {
                    it.id == action.parameters["tool_id"]
                }
                descriptor?.requiredPermissions?.forEach { requirement ->
                    permissions += AgentPermissionRequirement(
                        id = requirement.id,
                        title = requirement.title,
                        granted = descriptor.availability.status == AgentNativeToolAvailabilityStatus.AVAILABLE
                    )
                }
            }
            AgentActionKind.CALL_CONNECTOR,
            AgentActionKind.CONTROL_DEVICE -> {
                val connectorId = action.parameters["connector_id"]
                val target = request.targets.firstOrNull { target ->
                    target.id == connectorId || target.title == action.target
                }
                permissions += AgentPermissionRequirement(
                    id = "paired_contact",
                    title = "Verified SignalASI contact",
                    granted = AgentConnectorRouteSelector.isDeliverable(target)
                )
            }
            AgentActionKind.DRAFT_PLAN,
            AgentActionKind.IMPORT_WEB_KNOWLEDGE -> Unit
        }
        if (action.kind == AgentActionKind.PASTE_TEXT) {
            permissions += AgentPermissionRequirement(
                id = "clipboard_read",
                title = "Clipboard read",
                granted = true
            )
        }
        if (action.kind == AgentActionKind.COPY_SCREEN_TEXT) {
            permissions += AgentPermissionRequirement(
                id = "clipboard_write",
                title = "Clipboard write",
                granted = true
            )
        }
        return permissions
    }

    internal fun intentPermissionFor(action: AgentAction): AgentPermissionRequirement {
        val id = when {
            action.id.contains("notification-listener") -> "notification_listener_settings"
            action.id.contains("accessibility") -> "accessibility_settings"
            action.id.contains("current-app-settings") -> "current_app_details_settings"
            action.id == "open-installed-app" -> "launch_installed_app"
            action.id.contains("camera") -> "camera_app_handoff"
            action.id.contains("phone") -> "phone_dialer_handoff"
            action.id.contains("messages") -> "messages_app_handoff"
            action.id.contains("apk-install") -> "apk_install_handoff"
            action.id.contains("unknown-app-sources") -> "unknown_app_sources_settings"
            action.kind == AgentActionKind.SET_ALARM -> "alarm_handoff"
            action.kind == AgentActionKind.OPEN_URL -> "external_url_handoff"
            else -> "android_intent"
        }
        val title = when (id) {
            "notification_listener_settings" -> "Notification access settings"
            "accessibility_settings" -> "Accessibility settings"
            "current_app_details_settings" -> "Current app details settings"
            "launch_installed_app" -> "Launch installed app"
            "camera_app_handoff" -> "Camera app handoff"
            "phone_dialer_handoff" -> "Phone dialer handoff"
            "messages_app_handoff" -> "Messages app handoff"
            "apk_install_handoff" -> "APK install handoff"
            "unknown_app_sources_settings" -> "Unknown app source settings"
            "alarm_handoff" -> "Alarm app handoff"
            "external_url_handoff" -> "External URL handoff"
            else -> "Android system intent"
        }
        return AgentPermissionRequirement(
            id = id,
            title = title,
            granted = true
        )
    }

    internal fun rollbackStrategyFor(action: AgentAction): String = when (action.kind) {
        AgentActionKind.TYPE_TEXT,
        AgentActionKind.DELETE_TEXT,
        AgentActionKind.PASTE_TEXT -> "Stop before sending or submitting anything."
        AgentActionKind.TAP,
        AgentActionKind.LONG_PRESS,
        AgentActionKind.SWIPE -> "Observe the result and go back if the page changed unexpectedly."
        AgentActionKind.LOCK_SCREEN -> "Wake and unlock the phone manually to continue."
        AgentActionKind.REPLY_NOTIFICATION -> "The sent reply cannot be recalled; report delivery failure immediately."
        AgentActionKind.CALL_NATIVE_TOOL -> "Use the native tool receipt and its verification evidence before retrying."
        AgentActionKind.CALL_CONNECTOR,
        AgentActionKind.CONTROL_DEVICE -> "Keep the task in chat history and report delivery failure."
        AgentActionKind.IMPORT_WEB_KNOWLEDGE -> "Remove the imported source if extraction or indexing is incorrect."
        else -> "Stop execution and ask the user before retrying."
    }

    internal fun rollbackStrategyFor(actions: List<AgentAction>): String =
        if (actions.size == 1) rollbackStrategyFor(actions.first()) else "Stop the queue and ask the user before retrying the next action."

    internal fun expectedResultFor(action: AgentAction): String = when (action.kind) {
        AgentActionKind.OPEN_APP -> "The requested Android screen opens."
        AgentActionKind.OPEN_URL -> "The requested URL opens in a browser or matching app."
        AgentActionKind.SET_ALARM -> "Android alarm setup is opened or handed off."
        AgentActionKind.LOCK_SCREEN -> "The phone screen is locked through Accessibility."
        AgentActionKind.COPY_SCREEN_TEXT -> "Visible screen text is copied to the clipboard."
        AgentActionKind.SAVE_SCREEN_KNOWLEDGE -> "Current screen is saved into Agent knowledge."
        AgentActionKind.DELETE_TEXT -> "Text is cleared from the active input field."
        AgentActionKind.PASTE_TEXT -> "Clipboard text is pasted into the active input field."
        AgentActionKind.CREATE_NOTIFICATION -> "A local Android notification is created."
        AgentActionKind.REPLY_NOTIFICATION -> "The selected app receives the confirmed notification reply."
        AgentActionKind.CALL_NATIVE_TOOL -> "The selected phone-native tool returns a locally verified receipt."
        AgentActionKind.CALL_CONNECTOR -> "The task is sent to the paired agent contact."
        AgentActionKind.CONTROL_DEVICE -> "The trusted device connector receives the task."
        AgentActionKind.IMPORT_WEB_KNOWLEDGE -> "The web page is extracted and indexed in Agent knowledge."
        else -> action.description
    }

    internal fun expectedResultFor(actions: List<AgentAction>): String =
        if (actions.size == 1) expectedResultFor(actions.first()) else "Run ${actions.size} queued actions in order."

    internal fun timeoutFor(action: AgentAction): Int = when (action.kind) {
        AgentActionKind.CALL_CONNECTOR,
        AgentActionKind.CONTROL_DEVICE -> 120
        AgentActionKind.IMPORT_WEB_KNOWLEDGE -> 45
        AgentActionKind.OPEN_URL,
        AgentActionKind.OPEN_APP,
        AgentActionKind.SET_ALARM -> 30
        AgentActionKind.CREATE_NOTIFICATION -> 10
        AgentActionKind.REPLY_NOTIFICATION -> 30
        AgentActionKind.CALL_NATIVE_TOOL -> action.parameters["tool_timeout_seconds"]
            ?.toIntOrNull()?.coerceIn(1, 120) ?: 30
        else -> 20
    }

    internal fun routeRationaleFor(action: AgentAction, request: AgentRequest): String = when (action.kind) {
        AgentActionKind.CALL_CONNECTOR -> {
            val connectorId = action.parameters["connector_id"].orEmpty()
            val target = request.targets.firstOrNull { it.id == connectorId || it.title == action.target }
            when (target?.kind) {
                AgentConnectorKind.MODEL -> "Model route selected for reasoning or generation outside the phone UI."
                AgentConnectorKind.AGENT -> "Desktop Agent route selected for specialist work beyond local Android actions."
                AgentConnectorKind.DEVICE -> "Device connector route selected for trusted external device control."
                AgentConnectorKind.KNOWLEDGE -> "Knowledge route selected for memory or document retrieval."
                null -> "Connector route selected from the requested target, but the contact is not available yet."
            }
        }
        AgentActionKind.CONTROL_DEVICE -> "Device route selected because the goal targets Home Assistant or smart devices."
        AgentActionKind.CALL_NATIVE_TOOL ->
            if (action.isDesktopNativeTool()) {
                "Paired Desktop tool route selected from the live, locally validated capability catalog."
            } else {
                "Phone-native tool route selected from the live, locally validated capability catalog."
            }
        AgentActionKind.IMPORT_WEB_KNOWLEDGE -> "Knowledge route selected to extract and index a user-approved web page."
        AgentActionKind.READ_SCREEN,
        AgentActionKind.SAVE_SCREEN_KNOWLEDGE,
        AgentActionKind.COPY_SCREEN_TEXT -> "Local perception route selected because the task depends on the current phone screen."
        AgentActionKind.TAP,
        AgentActionKind.TYPE_TEXT,
        AgentActionKind.DELETE_TEXT,
        AgentActionKind.PASTE_TEXT,
        AgentActionKind.SWIPE,
        AgentActionKind.LONG_PRESS,
        AgentActionKind.BACK,
        AgentActionKind.HOME,
        AgentActionKind.RECENTS -> "Mobile executor route selected because the task changes the current Android UI."
        AgentActionKind.OPEN_APP,
        AgentActionKind.OPEN_URL,
        AgentActionKind.SET_ALARM -> "Android intent route selected because the task maps to a system app or system handoff."
        AgentActionKind.CREATE_NOTIFICATION -> "Local notification route selected because the task should alert the user on this phone."
        AgentActionKind.REPLY_NOTIFICATION -> "Notification reply route selected because the target app exposes Android direct reply."
        AgentActionKind.LOCK_SCREEN -> "Mobile executor route selected for an owner-confirmed screen lock."
        AgentActionKind.DRAFT_PLAN -> "Local planning route selected because the task needs clarification or a safe plan first."
    }
}

internal fun AgentAction.isDesktopNativeTool(): Boolean =
    kind == AgentActionKind.CALL_NATIVE_TOOL &&
        (
            parameters["_signalasi_native_tool_location"] == AgentNativeToolLocation.DESKTOP.wireValue ||
                parameters["tool_id"] in AgentDesktopRemoteNativeTools.toolIds
            )

object AgentRouteResolver {
    fun resolve(action: AgentAction, targets: List<AgentCallableTarget>): AgentRoute {
        val connectorId = action.parameters["connector_id"].orEmpty()
        val target = targets.firstOrNull { candidate ->
            candidate.id == connectorId || candidate.title == action.target
        }
        val kind = when (action.kind) {
            AgentActionKind.CALL_CONNECTOR -> when {
                connectorId == UNAVAILABLE_REASONING_CONNECTOR_ID -> AgentRouteKind.LOCAL_SYSTEM
                else -> when (target?.kind) {
                    AgentConnectorKind.MODEL -> if (target.id == "local-llm") AgentRouteKind.LOCAL_MODEL else AgentRouteKind.CLOUD_MODEL
                    AgentConnectorKind.AGENT -> AgentRouteKind.DESKTOP_AGENT
                    AgentConnectorKind.DEVICE -> AgentRouteKind.DEVICE_CONNECTOR
                    AgentConnectorKind.KNOWLEDGE -> AgentRouteKind.KNOWLEDGE
                    null -> AgentRouteKind.UNKNOWN
                }
            }
            AgentActionKind.CONTROL_DEVICE -> AgentRouteKind.DEVICE_CONNECTOR
            AgentActionKind.CALL_NATIVE_TOOL -> AgentRouteKind.LOCAL_SYSTEM
            AgentActionKind.IMPORT_WEB_KNOWLEDGE -> AgentRouteKind.KNOWLEDGE
            AgentActionKind.READ_SCREEN,
            AgentActionKind.SAVE_SCREEN_KNOWLEDGE,
            AgentActionKind.DRAFT_PLAN,
            AgentActionKind.TAP,
            AgentActionKind.TYPE_TEXT,
            AgentActionKind.DELETE_TEXT,
            AgentActionKind.PASTE_TEXT,
            AgentActionKind.SWIPE,
            AgentActionKind.LONG_PRESS,
            AgentActionKind.BACK,
            AgentActionKind.HOME,
            AgentActionKind.RECENTS,
            AgentActionKind.LOCK_SCREEN,
            AgentActionKind.OPEN_APP,
            AgentActionKind.OPEN_URL,
            AgentActionKind.SET_ALARM,
            AgentActionKind.CREATE_NOTIFICATION,
            AgentActionKind.REPLY_NOTIFICATION,
            AgentActionKind.COPY_SCREEN_TEXT -> AgentRouteKind.LOCAL_SYSTEM
        }
        val executionLocation = executionLocationFor(kind, target, action)
        return AgentRoute(
            routeId = connectorId.ifBlank { action.id },
            kind = kind,
            targetId = target?.id ?: connectorId.ifBlank { action.target },
            targetTitle = target?.title ?: action.target,
            status = target?.status ?: AgentConnectorStatus.AVAILABLE,
            deliveryMode = deliveryModeFor(kind),
            capabilities = target?.capabilities ?: emptyList(),
            executionLocationKind = executionLocation,
            executionRuntimeKind = executionRuntimeFor(kind, target, action),
            executionDeviceId = action.parameters["_signalasi_execution_device_id"]
                .orEmpty()
                .ifBlank { target?.failureDomain.orEmpty() }
                .takeIf {
                    executionLocation == AgentExecutionLocationKind.DESKTOP
                }
                .orEmpty(),
            executionDeviceName = target
                ?.title
                .orEmpty()
                .substringAfter(" \u00b7 ", "")
                .trim()
                .takeIf { executionLocation == AgentExecutionLocationKind.DESKTOP }
                .orEmpty()
        )
    }

    internal fun executionLocationFor(
        kind: AgentRouteKind,
        target: AgentCallableTarget?,
        action: AgentAction
    ): AgentExecutionLocationKind = when {
        action.isDesktopNativeTool() -> AgentExecutionLocationKind.DESKTOP
        action.parameters["tool_id"] == AgentOnDeviceRuntimeTools.EXECUTE ->
            AgentExecutionLocationKind.PHONE
        kind == AgentRouteKind.DESKTOP_AGENT -> AgentExecutionLocationKind.DESKTOP
        kind == AgentRouteKind.LOCAL_MODEL && target?.failureDomain.orEmpty().isNotBlank() ->
            AgentExecutionLocationKind.DESKTOP
        kind == AgentRouteKind.DEVICE_CONNECTOR -> AgentExecutionLocationKind.CONNECTED_DEVICE
        kind in setOf(
            AgentRouteKind.LOCAL_SYSTEM,
            AgentRouteKind.CLOUD_MODEL,
            AgentRouteKind.LOCAL_MODEL,
            AgentRouteKind.KNOWLEDGE
        ) -> AgentExecutionLocationKind.PHONE
        else -> AgentExecutionLocationKind.UNKNOWN
    }

    internal fun executionRuntimeFor(
        kind: AgentRouteKind,
        target: AgentCallableTarget?,
        action: AgentAction
    ): AgentExecutionRuntimeKind = when {
        action.isDesktopNativeTool() -> AgentExecutionRuntimeKind.DESKTOP_TOOL
        action.parameters["tool_id"] == AgentOnDeviceRuntimeTools.EXECUTE ->
            AgentExecutionRuntimeKind.PHONE_LINUX
        kind == AgentRouteKind.DESKTOP_AGENT -> AgentExecutionRuntimeKind.DESKTOP_AGENT
        kind == AgentRouteKind.LOCAL_MODEL && target?.failureDomain.orEmpty().isNotBlank() ->
            AgentExecutionRuntimeKind.DESKTOP_AGENT
        kind == AgentRouteKind.LOCAL_MODEL -> AgentExecutionRuntimeKind.PHONE_LOCAL_MODEL
        kind == AgentRouteKind.CLOUD_MODEL -> AgentExecutionRuntimeKind.PHONE_CLOUD_API
        kind == AgentRouteKind.DEVICE_CONNECTOR -> AgentExecutionRuntimeKind.CONNECTED_DEVICE
        kind == AgentRouteKind.KNOWLEDGE -> AgentExecutionRuntimeKind.KNOWLEDGE
        kind == AgentRouteKind.LOCAL_SYSTEM -> AgentExecutionRuntimeKind.PHONE_NATIVE
        else -> AgentExecutionRuntimeKind.UNKNOWN
    }

    internal fun deliveryModeFor(kind: AgentRouteKind): String = when (kind) {
        AgentRouteKind.LOCAL_SYSTEM -> "local_system"
        AgentRouteKind.CLOUD_MODEL -> "mobile_cloud_api"
        AgentRouteKind.LOCAL_MODEL -> "local_model"
        AgentRouteKind.DESKTOP_AGENT -> "pc_connector"
        AgentRouteKind.DEVICE_CONNECTOR -> "device_connector"
        AgentRouteKind.KNOWLEDGE -> "knowledge"
        AgentRouteKind.UNKNOWN -> "unknown"
    }
}

object AgentPlanValidator {
    fun validate(plan: AgentPlan): AgentPlanValidation {
        val issues = mutableListOf<String>()
        if (plan.goal.isBlank()) issues += "goal_blank"
        if (plan.actions.isEmpty()) issues += "actions_empty"
        val actionIds = plan.actions.map { it.id }
        if (actionIds.distinct().size != actionIds.size) issues += "action_ids_duplicate"
        val actionIndex = plan.actions.mapIndexed { index, action -> action.id to index }.toMap()
        plan.actions.forEach { action ->
            if (action.description.isBlank()) issues += "action_description_blank:${action.id}"
            if ((action.kind == AgentActionKind.TAP || action.kind == AgentActionKind.LONG_PRESS) &&
                action.parameters["bounds"].isNullOrBlank()) {
                issues += "action_bounds_missing:${action.id}"
            }
            if ((action.kind == AgentActionKind.TAP || action.kind == AgentActionKind.LONG_PRESS) &&
                !action.parameters["bounds"].isNullOrBlank() &&
                !validBounds(action.parameters["bounds"].orEmpty())) {
                issues += "action_bounds_invalid:${action.id}"
            }
            if (action.kind == AgentActionKind.TYPE_TEXT && action.parameters["text"].isNullOrBlank()) {
                issues += "action_text_missing:${action.id}"
            }
            if (action.kind == AgentActionKind.TYPE_TEXT &&
                !action.parameters["field_bounds"].isNullOrBlank() &&
                !validBounds(action.parameters["field_bounds"].orEmpty())) {
                issues += "action_field_bounds_invalid:${action.id}"
            }
            if (action.kind == AgentActionKind.IMPORT_WEB_KNOWLEDGE && action.parameters["url"].isNullOrBlank()) {
                issues += "action_url_missing:${action.id}"
            }
            if (action.kind == AgentActionKind.REPLY_NOTIFICATION) {
                if (action.parameters["notification_key"].isNullOrBlank()) {
                    issues += "notification_reply_target_missing:${action.id}"
                }
                if (action.parameters["reply_text"].isNullOrBlank()) {
                    issues += "notification_reply_text_missing:${action.id}"
                }
            }
            action.dependencyIds().forEach { dependencyId ->
                val dependencyIndex = actionIndex[dependencyId]
                val currentIndex = actionIndex[action.id] ?: -1
                if (dependencyIndex == null) {
                    issues += "action_dependency_missing:${action.id}:$dependencyId"
                } else if (dependencyIndex >= currentIndex) {
                    issues += "action_dependency_order_invalid:${action.id}:$dependencyId"
                }
            }
            val outputSources = action.outputSourceIds()
            if (outputSources.any { it !in action.dependencyIds() }) {
                issues += "action_output_source_not_dependency:${action.id}"
            }
            if (outputSources.isNotEmpty() &&
                action.kind != AgentActionKind.CALL_CONNECTOR &&
                !action.isPhoneDevelopmentRuntimeHandoff()
            ) {
                issues += "action_output_handoff_not_connector:${action.id}"
            }
        }
        if (plan.toolGraphDepth() == Int.MAX_VALUE) issues += "action_dependency_cycle"
        if (plan.safetyReview.risk.weight >= AgentRisk.HIGH.weight && !plan.confirmationRequired) {
            issues += "high_risk_without_confirmation"
        }
        if (plan.actions.any { it.kind == AgentActionKind.CALL_CONNECTOR || it.kind == AgentActionKind.CONTROL_DEVICE } &&
            plan.route.kind == AgentRouteKind.UNKNOWN) {
            issues += "route_unknown"
        }
        return AgentPlanValidation(
            valid = issues.isEmpty(),
            issues = issues
        )
    }

    internal fun validBounds(value: String): Boolean {
        val bounds = value.split(',').mapNotNull { it.trim().toIntOrNull() }
        if (bounds.size != 4) return false
        val (left, top, right, bottom) = bounds
        return left >= 0 && top >= 0 && right > left && bottom > top &&
            right <= MAX_GROUNDED_COORDINATE && bottom <= MAX_GROUNDED_COORDINATE
    }

    internal const val MAX_GROUNDED_COORDINATE = 20_000
}
