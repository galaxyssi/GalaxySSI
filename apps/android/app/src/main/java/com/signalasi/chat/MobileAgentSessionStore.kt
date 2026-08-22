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

interface AgentSessionStore {
    fun load(): AgentSessionSnapshot?
    fun save(snapshot: AgentSessionSnapshot)
    fun clear()
}

internal object AgentProcessIdentity {
    val instanceId: String = UUID.randomUUID().toString()
}

internal object AgentSessionInterruptionPolicy {
    fun wasInterrupted(snapshot: AgentSessionSnapshot): Boolean {
        val active = snapshot.phase == AgentPhase.EXECUTING ||
            snapshot.phase == AgentPhase.VERIFYING ||
            snapshot.executionLoopSnapshot?.phase?.isActive == true
        return active && snapshot.processInstanceId != AgentProcessIdentity.instanceId
    }
}

class InMemoryAgentSessionStore : AgentSessionStore {
    @Volatile internal var snapshot: AgentSessionSnapshot? = null
    override fun load(): AgentSessionSnapshot? = snapshot
    override fun save(snapshot: AgentSessionSnapshot) { this.snapshot = snapshot }
    override fun clear() { snapshot = null }
}

class SharedPreferencesAgentSessionStore(
    context: Context,
    internal val storageKey: String = KEY_SESSION
) : AgentSessionStore {
    internal val prefs = AgentEncryptedPreferences(context, PREFS)

    override fun load(): AgentSessionSnapshot? {
        val encodedLength = prefs.encodedValueLength(storageKey)
        if (AgentSessionPersistencePolicy.shouldDiscardEncodedValue(encodedLength)) {
            prefs.remove(storageKey)
            Log.w(
                "SignalASIAgentSession",
                "Discarded oversized session checkpoint key=$storageKey encoded_chars=$encodedLength"
            )
            return null
        }
        val raw = prefs.readString(storageKey, "").takeIf { it.isNotBlank() } ?: return null
        return runCatching {
            decodeSession(JSONObject(raw))
        }.getOrNull()
    }

    override fun save(snapshot: AgentSessionSnapshot) {
        val encoded = encodeSession(snapshot).toString()
        val payload = if (encoded.length <= AgentSessionPersistencePolicy.MAX_SESSION_JSON_CHARACTERS) {
            encoded
        } else {
            encodeRecoverySession(snapshot).toString()
        }
        prefs.writeString(storageKey, payload)
    }

    override fun clear() {
        prefs.remove(storageKey)
    }

    internal fun encodeSession(snapshot: AgentSessionSnapshot): JSONObject = JSONObject()
        .put("version", 7)
        .put("session_id", snapshot.sessionId)
        .put("phase", snapshot.phase.name)
        .put("current_goal", AgentSessionPersistencePolicy.compactText(snapshot.currentGoal))
        .put("current_screen", encodeScreen(snapshot.currentScreen))
        .put("current_plan", snapshot.currentPlan?.let { encodePlan(it) })
        .put("audit_trail", JSONArray().also { array ->
            snapshot.auditTrail.takeLast(MAX_SESSION_AUDIT_ITEMS).forEach { array.put(encodeAudit(it)) }
        })
        .put("last_action_result", snapshot.lastActionResult?.let { encodeActionResult(it) })
        .put("active_workflow_execution_id", snapshot.activeWorkflowExecutionId)
        .put("task_execution_mode", snapshot.taskExecutionMode.name)
        .put(
            "execution_loop",
            snapshot.executionLoopSnapshot
                ?.let(AgentExecutionLoopJsonCodec::encode)
                ?.let(::JSONObject)
        )
        .put("process_instance_id", snapshot.processInstanceId)
        .put("updated_at", snapshot.updatedAtMillis)

    internal fun encodeRecoverySession(snapshot: AgentSessionSnapshot): JSONObject = JSONObject()
        .put("version", 7)
        .put("session_id", snapshot.sessionId)
        .put("phase", snapshot.phase.name)
        .put("current_goal", AgentSessionPersistencePolicy.compactText(snapshot.currentGoal))
        .put("current_screen", encodeScreen(snapshot.currentScreen))
        .put("current_plan", JSONObject.NULL)
        .put("audit_trail", JSONArray().also { array ->
            snapshot.auditTrail.takeLast(RECOVERY_AUDIT_ITEMS).forEach { array.put(encodeAudit(it)) }
        })
        .put("last_action_result", snapshot.lastActionResult?.let { encodeActionResult(it) })
        .put("active_workflow_execution_id", snapshot.activeWorkflowExecutionId)
        .put("task_execution_mode", snapshot.taskExecutionMode.name)
        .put(
            "execution_loop",
            snapshot.executionLoopSnapshot
                ?.let(AgentExecutionLoopJsonCodec::encode)
                ?.let(::JSONObject)
        )
        .put("process_instance_id", snapshot.processInstanceId)
        .put("updated_at", snapshot.updatedAtMillis)

    internal fun decodeSession(json: JSONObject): AgentSessionSnapshot = AgentSessionSnapshot(
        sessionId = json.optString("session_id"),
        phase = enumOrDefault(json.optString("phase"), AgentPhase.OBSERVING),
        currentGoal = json.optString("current_goal"),
        currentScreen = decodeScreen(json.optJSONObject("current_screen")),
        currentPlan = json.optJSONObject("current_plan")?.let { decodePlan(it) },
        auditTrail = decodeAuditTrail(json.optJSONArray("audit_trail")),
        lastActionResult = json.optJSONObject("last_action_result")?.let { decodeActionResult(it) },
        activeWorkflowExecutionId = json.optString("active_workflow_execution_id"),
        taskExecutionMode = enumOrDefault(
            json.optString("task_execution_mode"),
            AgentTaskExecutionMode.AUTO_COMPLETE
        ),
        executionLoopSnapshot = json.optJSONObject("execution_loop")
            ?.toString()
            ?.let(AgentExecutionLoopJsonCodec::decode),
        processInstanceId = json.optString("process_instance_id"),
        updatedAtMillis = json.optLong("updated_at", 0L)
    )

    internal fun encodeScreen(source: ScreenContext): JSONObject {
        val screen = AgentSessionPersistencePolicy.compactScreen(source)
        return JSONObject()
        .put("foreground_app", screen.foregroundApp)
        .put("activity_name", screen.activityName)
        .put("page_title", screen.pageTitle)
        .put("visible_text_count", screen.visibleTextCount)
        .put("clickable_node_count", screen.clickableNodeCount)
        .put("input_field_count", screen.inputFieldCount)
        .put("scrollable_region_count", screen.scrollableRegionCount)
        .put("sensitive_flag_count", screen.sensitiveFlagCount)
        .put("selected_text", screen.selectedText)
        .put("focused_input_field", screen.focusedInputField?.let { encodeElement(it) } ?: JSONObject.NULL)
        .put("visible_texts", JSONArray().also { array ->
            screen.visibleTexts.forEach { array.put(it) }
        })
        .put("clickable_elements", encodeElements(screen.clickableElements))
        .put("input_fields", encodeElements(screen.inputFields))
        .put("scrollable_regions", encodeElements(screen.scrollableRegions))
        .put("sensitive_flags", JSONArray().also { array ->
            screen.sensitiveFlags.forEach { array.put(it) }
        })
        .put("visual_scene", encodeVisualScene(screen.visualScene))
        .put("clipboard_context", encodeClipboardContext(screen.clipboard))
        .put("notification_context", encodeNotificationContext(screen.notifications))
        .put("installed_apps", encodeInstalledApps(screen.installedApps))
        .put("device_status", encodeDeviceStatus(screen.deviceStatus))
        .put("is_accessibility_enabled", screen.isAccessibilityEnabled)
        .put("snapshot_age_millis", screen.snapshotAgeMillis)
    }

    internal fun decodeScreen(json: JSONObject?): ScreenContext {
        if (json == null) return ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent")
        return ScreenContext(
            foregroundApp = json.optString("foreground_app", "SignalASI"),
            activityName = json.optString("activity_name"),
            pageTitle = json.optString("page_title", "Agent"),
            visibleTextCount = json.optInt("visible_text_count"),
            clickableNodeCount = json.optInt("clickable_node_count"),
            inputFieldCount = json.optInt("input_field_count"),
            scrollableRegionCount = json.optInt("scrollable_region_count"),
            sensitiveFlagCount = json.optInt("sensitive_flag_count"),
            selectedText = json.optString("selected_text"),
            focusedInputField = decodeElement(json.optJSONObject("focused_input_field")),
            visibleTexts = decodeStringList(json.optJSONArray("visible_texts")),
            clickableElements = decodeElements(json.optJSONArray("clickable_elements")),
            inputFields = decodeElements(json.optJSONArray("input_fields")),
            scrollableRegions = decodeElements(json.optJSONArray("scrollable_regions")),
            sensitiveFlags = decodeStringList(json.optJSONArray("sensitive_flags")),
            visualScene = decodeVisualScene(json.optJSONObject("visual_scene")),
            clipboard = decodeClipboardContext(json.optJSONObject("clipboard_context")),
            notifications = decodeNotificationContext(json.optJSONObject("notification_context")),
            installedApps = decodeInstalledApps(json.optJSONArray("installed_apps")),
            deviceStatus = decodeDeviceStatus(json.optJSONObject("device_status")),
            isAccessibilityEnabled = json.optBoolean("is_accessibility_enabled"),
            snapshotAgeMillis = json.optLong("snapshot_age_millis")
        )
    }

    internal fun encodeClipboardContext(clipboard: ClipboardContext): JSONObject = JSONObject()
        .put("has_text", clipboard.hasText)
        .put("text_length", clipboard.textLength)
        .put("text_hash", clipboard.textHash)
        .put("preview", clipboard.preview)
        .put("sensitive_flags", JSONArray().also { array ->
            clipboard.sensitiveFlags.forEach { array.put(it) }
        })

    internal fun decodeClipboardContext(json: JSONObject?): ClipboardContext {
        if (json == null) return ClipboardContext()
        return ClipboardContext(
            hasText = json.optBoolean("has_text"),
            textLength = json.optInt("text_length"),
            textHash = json.optString("text_hash"),
            preview = json.optString("preview"),
            sensitiveFlags = decodeStringList(json.optJSONArray("sensitive_flags"))
        )
    }

    internal fun encodeNotificationContext(context: AgentNotificationContext): JSONObject = JSONObject()
        .put("has_access", context.hasAccess)
        .put("items", JSONArray().also { array ->
            context.items.forEach { item ->
                array.put(JSONObject()
                    .put("key", item.key)
                    .put("package_name", item.packageName)
                    .put("title", item.title)
                    .put("text_preview", item.textPreview)
                    .put("category", item.category)
                    .put("posted_at_millis", item.postedAtMillis)
                    .put("can_reply", item.canReply)
                    .put("sensitive_flags", JSONArray().also { flags ->
                        item.sensitiveFlags.forEach { flags.put(it) }
                    }))
            }
        })
        .put("sensitive_flags", JSONArray().also { array ->
            context.sensitiveFlags.forEach { array.put(it) }
        })

    internal fun decodeNotificationContext(json: JSONObject?): AgentNotificationContext {
        if (json == null) return AgentNotificationContext()
        return AgentNotificationContext(
            hasAccess = json.optBoolean("has_access"),
            items = decodeNotificationItems(json.optJSONArray("items")),
            sensitiveFlags = decodeStringList(json.optJSONArray("sensitive_flags"))
        )
    }

    internal fun decodeNotificationItems(array: JSONArray?): List<AgentNotificationItem> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                add(
                    AgentNotificationItem(
                        key = item.optString("key"),
                        packageName = item.optString("package_name"),
                        title = item.optString("title"),
                        textPreview = item.optString("text_preview"),
                        category = item.optString("category", "app"),
                        postedAtMillis = item.optLong("posted_at_millis"),
                        canReply = item.optBoolean("can_reply"),
                        sensitiveFlags = decodeStringList(item.optJSONArray("sensitive_flags"))
                    )
                )
            }
        }
    }

    internal fun encodeInstalledApps(apps: List<InstalledAppInfo>): JSONArray = JSONArray().also { array ->
        apps.forEach { app ->
            array.put(JSONObject()
                .put("label", app.label)
                .put("package_name", app.packageName))
        }
    }

    internal fun decodeInstalledApps(array: JSONArray?): List<InstalledAppInfo> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val label = item.optString("label")
                val packageName = item.optString("package_name")
                if (label.isNotBlank() && packageName.isNotBlank()) {
                    add(InstalledAppInfo(label = label, packageName = packageName))
                }
            }
        }
    }

    internal fun encodeDeviceStatus(status: AgentDeviceStatusContext): JSONObject = JSONObject()
        .put("battery_percent", status.batteryPercent)
        .put("charging", status.charging)
        .put("power_save_mode", status.powerSaveMode)
        .put("network", status.network)
        .put("free_storage_mb", status.freeStorageMb)
        .put("total_storage_mb", status.totalStorageMb)

    internal fun decodeDeviceStatus(json: JSONObject?): AgentDeviceStatusContext {
        if (json == null) return AgentDeviceStatusContext()
        return AgentDeviceStatusContext(
            batteryPercent = json.optInt("battery_percent", -1),
            charging = json.optBoolean("charging"),
            powerSaveMode = json.optBoolean("power_save_mode"),
            network = json.optString("network", "unknown"),
            freeStorageMb = json.optLong("free_storage_mb"),
            totalStorageMb = json.optLong("total_storage_mb")
        )
    }

    internal fun encodePlan(plan: AgentPlan): JSONObject = JSONObject()
        .put("goal", AgentSessionPersistencePolicy.compactText(plan.goal))
        .put("screen", encodeScreen(plan.screen))
        .put("execution_mode", plan.executionMode.name)
        .put("plan_id", plan.planId)
        .put("selected_agent_or_model", plan.selectedAgentOrModel)
        .put("required_permissions", encodePermissions(plan.requiredPermissions))
        .put("confirmation_required", plan.confirmationRequired)
        .put("rollback_strategy", plan.rollbackStrategy)
        .put("expected_result", plan.expectedResult)
        .put("timeout_seconds", plan.timeoutSeconds)
        .put("planner_profile", plan.plannerProfile)
        .put("context_digest", plan.contextDigest)
        .put("revision", plan.revision)
        .put("replan_count", plan.replanCount)
        .put("route_rationale", plan.routeRationale)
        .put("route", encodeRoute(plan.route))
        .put("validation", encodePlanValidation(plan.validation))
        .put("verification_results", JSONArray().also { array ->
            plan.verificationResults.takeLast(MAX_SESSION_VERIFICATION_RESULTS).forEach {
                array.put(encodeVerificationResult(it))
            }
        })
        .put("steps", JSONArray().also { array ->
            plan.steps.take(MAX_SESSION_STEPS).forEach { array.put(encodeStep(it)) }
        })
        .put("actions", JSONArray().also { array ->
            plan.actions.take(MAX_SESSION_ACTIONS).forEach { array.put(encodeAction(it)) }
        })
        .put("action_history", JSONArray().also { array ->
            AgentSessionPersistencePolicy.actionHistory(plan).forEach { array.put(encodeAction(it)) }
        })
        .put("checkpoints", JSONArray().also { array ->
            plan.checkpoints.takeLast(MAX_SESSION_CHECKPOINTS).forEach { array.put(encodeCheckpoint(it)) }
        })
        .put("artifact_rich_output", plan.artifactRichOutputJson)
        .put("safety_review", encodeSafetyReview(plan.safetyReview))

    internal fun decodePlan(json: JSONObject): AgentPlan = AgentPlan(
        goal = json.optString("goal"),
        screen = decodeScreen(json.optJSONObject("screen")),
        steps = decodeSteps(json.optJSONArray("steps")),
        actions = decodeActions(json.optJSONArray("actions")),
        executionMode = enumOrDefault(
            json.optString("execution_mode"),
            AgentTaskExecutionMode.AUTO_COMPLETE
        ),
        planId = json.optString("plan_id").ifBlank { UUID.randomUUID().toString() },
        selectedAgentOrModel = json.optString("selected_agent_or_model"),
        requiredPermissions = decodePermissions(json.optJSONArray("required_permissions")),
        confirmationRequired = json.optBoolean("confirmation_required", true),
        rollbackStrategy = json.optString("rollback_strategy", "Stop execution and ask the user before retrying."),
        expectedResult = json.optString("expected_result"),
        timeoutSeconds = json.optInt("timeout_seconds", 60),
        plannerProfile = json.optString("planner_profile", "rule-based-local"),
        contextDigest = json.optString("context_digest"),
        revision = json.optInt("revision", 1).coerceAtLeast(1),
        replanCount = json.optInt("replan_count", 0).coerceAtLeast(0),
        routeRationale = json.optString("route_rationale"),
        route = decodeRoute(json.optJSONObject("route")),
        validation = decodePlanValidation(json.optJSONObject("validation")),
        verificationResults = decodeVerificationResults(json.optJSONArray("verification_results")),
        safetyReview = decodeSafetyReview(json.optJSONObject("safety_review")),
        actionHistory = decodeActions(json.optJSONArray("action_history")),
        checkpoints = decodeCheckpoints(json.optJSONArray("checkpoints")),
        artifactRichOutputJson = AgentRuntimeArtifactUi.mergeArtifactOutputs(
            json.optString("artifact_rich_output")
        )
    )

    internal fun encodeRoute(route: AgentRoute): JSONObject = JSONObject()
        .put("route_id", route.routeId)
        .put("kind", route.kind.name)
        .put("target_id", route.targetId)
        .put("target_title", route.targetTitle)
        .put("status", route.status.name)
        .put("delivery_mode", route.deliveryMode)
        .put("execution_location_kind", route.executionLocationKind.name)
        .put("execution_runtime_kind", route.executionRuntimeKind.name)
        .put("execution_device_id", route.executionDeviceId)
        .put("execution_device_name", route.executionDeviceName)
        .put("capabilities", JSONArray().also { array ->
            route.capabilities.forEach { array.put(it.name) }
        })

    internal fun decodeRoute(json: JSONObject?): AgentRoute {
        if (json == null) return AgentRoute()
        return AgentRoute(
            routeId = json.optString("route_id"),
            kind = enumOrDefault(json.optString("kind"), AgentRouteKind.UNKNOWN),
            targetId = json.optString("target_id"),
            targetTitle = json.optString("target_title"),
            status = enumOrDefault(json.optString("status"), AgentConnectorStatus.DISCONNECTED),
            deliveryMode = json.optString("delivery_mode"),
            capabilities = decodeCapabilities(json.optJSONArray("capabilities")),
            executionLocationKind = enumOrDefault(
                json.optString("execution_location_kind"),
                AgentExecutionLocationKind.UNKNOWN
            ),
            executionRuntimeKind = enumOrDefault(
                json.optString("execution_runtime_kind"),
                AgentExecutionRuntimeKind.UNKNOWN
            ),
            executionDeviceId = json.optString("execution_device_id"),
            executionDeviceName = json.optString("execution_device_name")
        )
    }

    internal fun decodeCapabilities(array: JSONArray?): List<AgentCapability> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                add(enumOrDefault(array.optString(index), AgentCapability.CHAT))
            }
        }
    }

    internal fun encodePermissions(permissions: List<AgentPermissionRequirement>): JSONArray = JSONArray().also { array ->
        permissions.forEach { permission ->
            array.put(JSONObject()
                .put("id", permission.id)
                .put("title", permission.title)
                .put("required", permission.required)
                .put("granted", permission.granted))
        }
    }

    internal fun decodePermissions(array: JSONArray?): List<AgentPermissionRequirement> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                add(
                    AgentPermissionRequirement(
                        id = item.optString("id"),
                        title = item.optString("title"),
                        required = item.optBoolean("required", true),
                        granted = item.optBoolean("granted")
                    )
                )
            }
        }
    }

    internal fun encodePlanValidation(validation: AgentPlanValidation): JSONObject = JSONObject()
        .put("valid", validation.valid)
        .put("issues", JSONArray().also { array ->
            validation.issues.forEach { array.put(it) }
        })

    internal fun decodePlanValidation(json: JSONObject?): AgentPlanValidation {
        if (json == null) return AgentPlanValidation()
        return AgentPlanValidation(
            valid = json.optBoolean("valid", true),
            issues = decodeStringList(json.optJSONArray("issues"))
        )
    }

    internal fun encodeVerificationResult(result: AgentVerificationResult): JSONObject = JSONObject()
        .put("action_id", result.actionId)
        .put("success", result.success)
        .put("observed_app", result.observedApp)
        .put("observed_title", result.observedTitle)
        .put("visible_text_count", result.visibleTextCount)
        .put("clickable_node_count", result.clickableNodeCount)
        .put("evidence", result.evidence)
        .put("observation_decision", result.observationDecision.name)
        .put("observation_sample_count", result.observationSampleCount)
        .put("observation_duration_millis", result.observationDurationMillis)
        .put("screen_changed", result.screenChanged)
        .put("screen_stable", result.screenStable)
        .put("recovery_decision", result.recoveryDecision.name)
        .put("recovery_attempt_count", result.recoveryAttemptCount)
        .put("timestamp_millis", result.timestampMillis)

    internal fun decodeVerificationResults(array: JSONArray?): List<AgentVerificationResult> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                add(
                    AgentVerificationResult(
                        actionId = item.optString("action_id"),
                        success = item.optBoolean("success"),
                        observedApp = item.optString("observed_app"),
                        observedTitle = item.optString("observed_title"),
                        visibleTextCount = item.optInt("visible_text_count"),
                        clickableNodeCount = item.optInt("clickable_node_count"),
                        evidence = item.optString("evidence"),
                        observationDecision = enumOrDefault(
                            item.optString("observation_decision"),
                            AgentObservationDecision.NO_CHANGE_REQUIRED
                        ),
                        observationSampleCount = item.optInt("observation_sample_count", 1),
                        observationDurationMillis = item.optLong("observation_duration_millis"),
                        screenChanged = item.optBoolean("screen_changed"),
                        screenStable = item.optBoolean("screen_stable", true),
                        recoveryDecision = enumOrDefault(
                            item.optString("recovery_decision"),
                            AgentRecoveryDecision.NOT_NEEDED
                        ),
                        recoveryAttemptCount = item.optInt("recovery_attempt_count"),
                        timestampMillis = item.optLong("timestamp_millis")
                    )
                )
            }
        }
    }

    internal fun encodeStep(step: AgentStep): JSONObject = JSONObject()
        .put("order", step.order)
        .put("kind", step.kind.name)
        .put("status", step.status.name)

    internal fun decodeSteps(array: JSONArray?): List<AgentStep> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                add(
                    AgentStep(
                        order = item.optInt("order"),
                        kind = enumOrDefault(item.optString("kind"), AgentStepKind.OBSERVE_SCREEN),
                        status = enumOrDefault(item.optString("status"), AgentStepStatus.WAITING)
                    )
                )
            }
        }
    }

    internal fun encodeAction(action: AgentAction): JSONObject = JSONObject()
        .put("id", action.id)
        .put("kind", action.kind.name)
        .put("target", action.target)
        .put("risk", action.risk.name)
        .put("status", action.status.name)
        .put("description", AgentSessionPersistencePolicy.compactActionText(action.description))
        .put("parameters", JSONObject(AgentSessionPersistencePolicy.compactMetadata(action.parameters)))
        .put("requires_confirmation", action.requiresConfirmation)
        .put("result", AgentSessionPersistencePolicy.compactActionText(action.result))
        .put("evidence", AgentSessionPersistencePolicy.compactActionText(action.evidence))

    internal fun decodeActions(array: JSONArray?): List<AgentAction> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                add(
                    AgentAction(
                        id = item.optString("id"),
                        kind = enumOrDefault(item.optString("kind"), AgentActionKind.DRAFT_PLAN),
                        target = item.optString("target"),
                        risk = enumOrDefault(item.optString("risk"), AgentRisk.LOW),
                        status = enumOrDefault(item.optString("status"), AgentActionStatus.PENDING_CONFIRMATION),
                        description = item.optString("description"),
                        parameters = decodeStringMap(item.optJSONObject("parameters")),
                        requiresConfirmation = item.optBoolean("requires_confirmation", true),
                        result = item.optString("result"),
                        evidence = item.optString("evidence")
                    )
                )
            }
        }
    }

    internal fun encodeCheckpoint(checkpoint: AgentExecutionCheckpoint): JSONObject = JSONObject()
        .put("id", checkpoint.id)
        .put("action_id", checkpoint.actionId)
        .put("plan_revision", checkpoint.planRevision)
        .put("foreground_app", checkpoint.foregroundApp)
        .put("activity_name", checkpoint.activityName)
        .put("page_title", checkpoint.pageTitle)
        .put("screen_digest", checkpoint.screenDigest)
        .put("rollback_action", checkpoint.rollbackAction?.let { encodeAction(it) })
        .put("status", checkpoint.status.name)
        .put("created_at_millis", checkpoint.createdAtMillis)

    internal fun decodeCheckpoints(array: JSONArray?): List<AgentExecutionCheckpoint> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                add(
                    AgentExecutionCheckpoint(
                        id = item.optString("id").ifBlank { UUID.randomUUID().toString() },
                        actionId = item.optString("action_id"),
                        planRevision = item.optInt("plan_revision", 1).coerceAtLeast(1),
                        foregroundApp = item.optString("foreground_app"),
                        activityName = item.optString("activity_name"),
                        pageTitle = item.optString("page_title"),
                        screenDigest = item.optString("screen_digest"),
                        rollbackAction = item.optJSONObject("rollback_action")?.let { decodeAction(it) },
                        status = enumOrDefault(
                            item.optString("status"),
                            AgentCheckpointStatus.ACTIVE
                        ),
                        createdAtMillis = item.optLong("created_at_millis", System.currentTimeMillis())
                    )
                )
            }
        }
    }

    internal fun decodeAction(item: JSONObject): AgentAction = AgentAction(
        id = item.optString("id"),
        kind = enumOrDefault(item.optString("kind"), AgentActionKind.DRAFT_PLAN),
        target = item.optString("target"),
        risk = enumOrDefault(item.optString("risk"), AgentRisk.LOW),
        status = enumOrDefault(item.optString("status"), AgentActionStatus.PENDING_CONFIRMATION),
        description = item.optString("description"),
        parameters = decodeStringMap(item.optJSONObject("parameters")),
        requiresConfirmation = item.optBoolean("requires_confirmation", true),
        result = item.optString("result"),
        evidence = item.optString("evidence")
    )

    internal fun encodeSafetyReview(review: AgentSafetyReview): JSONObject = JSONObject()
        .put("risk", review.risk.name)
        .put("requires_confirmation", review.requiresConfirmation)
        .put("blocked", review.blocked)
        .put("mode", review.mode.name)
        .put("denied_permissions", JSONArray().also { array ->
            review.deniedPermissions.forEach { array.put(it) }
        })
        .put("warnings", JSONArray().also { array ->
            review.warnings.forEach { array.put(it) }
        })
        .put("reason", review.reason)

    internal fun decodeSafetyReview(json: JSONObject?): AgentSafetyReview {
        if (json == null) return AgentSafetyReview()
        return AgentSafetyReview(
            risk = enumOrDefault(json.optString("risk"), AgentRisk.LOW),
            requiresConfirmation = json.optBoolean("requires_confirmation", true),
            blocked = json.optBoolean("blocked"),
            mode = enumOrDefault(json.optString("mode"), PermissionMode.ASK_BEFORE_ACTION),
            deniedPermissions = decodeStringList(json.optJSONArray("denied_permissions")),
            warnings = decodeStringList(json.optJSONArray("warnings")),
            reason = json.optString("reason")
        )
    }

    internal fun encodeActionResult(result: AgentActionResult): JSONObject = JSONObject()
        .put("action_id", result.actionId)
        .put("success", result.success)
        .put("message", AgentSessionPersistencePolicy.compactActionText(result.message))
        .put("metadata", JSONObject(AgentSessionPersistencePolicy.compactMetadata(result.metadata)))

    internal fun decodeActionResult(json: JSONObject): AgentActionResult = AgentActionResult(
        actionId = json.optString("action_id"),
        success = json.optBoolean("success"),
        message = json.optString("message"),
        metadata = decodeStringMap(json.optJSONObject("metadata"))
    )

    internal fun encodeAudit(audit: AgentAuditEntry): JSONObject = JSONObject()
        .put("event", audit.event.name)
        .put("detail", AgentSessionPersistencePolicy.compactAuditText(audit.detail))
        .put("timestamp_millis", audit.timestampMillis)

    internal fun decodeAuditTrail(array: JSONArray?): List<AgentAuditEntry> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                add(
                    AgentAuditEntry(
                        event = enumOrDefault(item.optString("event"), AgentAuditEvent.SCREEN_OBSERVED),
                        detail = item.optString("detail"),
                        timestampMillis = item.optLong("timestamp_millis")
                    )
                )
            }
        }
    }

    internal fun encodeElements(elements: List<ScreenElement>): JSONArray = JSONArray().also { array ->
        elements.forEach { element ->
            array.put(encodeElement(element))
        }
    }

    internal fun encodeElement(element: ScreenElement): JSONObject = JSONObject()
        .put("label", element.label)
        .put("view_id", element.viewId)
        .put("class_name", element.className)
        .put("bounds", element.bounds)
        .put("origin", element.origin.name)
        .put("confidence", element.confidence.toDouble())
        .put("visual_role", element.visualRole.name)
        .put("actionable", element.actionable)

    internal fun decodeElements(array: JSONArray?): List<ScreenElement> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                decodeElement(item)?.let { add(it) }
            }
        }
    }

    internal fun decodeElement(item: JSONObject?): ScreenElement? {
        if (item == null) return null
        return ScreenElement(
            label = item.optString("label"),
            viewId = item.optString("view_id"),
            className = item.optString("class_name"),
            bounds = item.optString("bounds"),
            origin = enumOrDefault(item.optString("origin"), AgentElementOrigin.ACCESSIBILITY),
            confidence = item.optDouble("confidence", 1.0).toFloat().coerceIn(0f, 1f),
            visualRole = enumOrDefault(item.optString("visual_role"), AgentVisualRole.UNKNOWN),
            actionable = item.optBoolean("actionable", true)
        )
    }

    internal fun encodeVisualScene(scene: AgentVisualScene): JSONObject = JSONObject()
        .put("width", scene.width)
        .put("height", scene.height)
        .put("model_profile", scene.modelProfile)
        .put("action_candidate_count", scene.actionCandidateCount)
        .put("input_candidate_count", scene.inputCandidateCount)
        .put("timestamp_millis", scene.timestampMillis)
        .put("elements", JSONArray().also { array ->
            scene.elements.take(MAX_SESSION_VISUAL_ELEMENTS).forEach { element ->
                array.put(
                    JSONObject()
                        .put("text", element.text)
                        .put("bounds", element.bounds)
                        .put("confidence", element.confidence.toDouble())
                        .put("role", element.role.name)
                        .put("actionable", element.actionable)
                        .put("input_candidate", element.inputCandidate)
                )
            }
        })

    internal fun decodeVisualScene(json: JSONObject?): AgentVisualScene {
        if (json == null) return AgentVisualScene()
        val elements = buildList {
            val array = json.optJSONArray("elements") ?: JSONArray()
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val text = item.optString("text").trim()
                val bounds = item.optString("bounds")
                if (text.isBlank() || bounds.isBlank()) continue
                add(
                    AgentVisualElement(
                        text = text,
                        bounds = bounds,
                        confidence = item.optDouble("confidence", 1.0).toFloat().coerceIn(0f, 1f),
                        role = enumOrDefault(item.optString("role"), AgentVisualRole.UNKNOWN),
                        actionable = item.optBoolean("actionable"),
                        inputCandidate = item.optBoolean("input_candidate")
                    )
                )
            }
        }
        return AgentVisualScene(
            width = json.optInt("width"),
            height = json.optInt("height"),
            modelProfile = json.optString("model_profile", "none"),
            elements = elements,
            actionCandidateCount = json.optInt("action_candidate_count", elements.count { it.actionable }),
            inputCandidateCount = json.optInt("input_candidate_count", elements.count { it.inputCandidate }),
            timestampMillis = json.optLong("timestamp_millis")
        )
    }

    internal fun decodeStringList(array: JSONArray?): List<String> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                array.optString(index).takeIf { it.isNotBlank() }?.let { add(it) }
            }
        }
    }

    internal fun decodeStringMap(json: JSONObject?): Map<String, String> {
        if (json == null) return emptyMap()
        return buildMap {
            json.keys().forEach { key ->
                put(key, json.optString(key))
            }
        }
    }

    companion object {
        private const val PREFS = "signalasi_agent_runtime"
        private const val KEY_SESSION = "session"
        private const val TASK_PREFIX = "task:"
        private const val MAX_SESSION_VISUAL_ELEMENTS = 60
        private const val MAX_SESSION_AUDIT_ITEMS = 20
        private const val RECOVERY_AUDIT_ITEMS = 4
        private const val MAX_SESSION_VERIFICATION_RESULTS = 24
        private const val MAX_SESSION_STEPS = 64
        private const val MAX_SESSION_ACTIONS = 64
        private const val MAX_SESSION_CHECKPOINTS = 16

        fun taskStorageKeys(context: Context): List<String> =
            AgentEncryptedPreferences(context, PREFS).keys()
                .asSequence()
                .filter { it.startsWith(TASK_PREFIX) }
                .sorted()
                .toList()

        fun taskStorageKeyForConnectorResponse(
            context: Context,
            sourceMessageId: Long,
            contactId: String
        ): String? = taskStorageKeys(context).firstOrNull { storageKey ->
            val snapshot = SharedPreferencesAgentSessionStore(context, storageKey).load()
                ?: return@firstOrNull false
            val pending = snapshot.lastActionResult ?: return@firstOrNull false
            val recoverable = snapshot.phase == AgentPhase.WAITING_RESPONSE || (
                snapshot.phase == AgentPhase.FAILED &&
                    !pending.success &&
                    pending.metadata["timeout_stage"].orEmpty().isNotBlank()
                )
            val expectedContact = pending.metadata["contact_id"].orEmpty()
            recoverable &&
                pending.metadata["source_message_id"]?.toLongOrNull() == sourceMessageId &&
                (expectedContact.isBlank() || contactId.isBlank() || expectedContact == contactId)
        }
    }
}

internal object AgentSessionPersistencePolicy {
    const val MAX_SESSION_JSON_CHARACTERS = 96 * 1024
    internal const val MAX_ENCRYPTED_SESSION_CHARACTERS = 192 * 1024
    internal const val MAX_GENERAL_TEXT_CHARACTERS = 8 * 1024
    internal const val MAX_ACTION_TEXT_CHARACTERS = 4 * 1024
    internal const val MAX_AUDIT_TEXT_CHARACTERS = 1 * 1024
    internal const val MAX_METADATA_ENTRIES = 24
    internal const val MAX_METADATA_VALUE_CHARACTERS = 2 * 1024
    internal const val MAX_SCREEN_LABEL_CHARACTERS = 512

    fun actionHistory(plan: AgentPlan): List<AgentAction> =
        if (plan.isSupervisedProjectPlan()) {
            AgentProjectHistoryRetentionPolicy.retainForPersistence(plan.actionHistory)
        } else {
            plan.actionHistory.takeLast(MAX_NON_PROJECT_ACTION_HISTORY)
        }

    fun shouldDiscardEncodedValue(encodedLength: Int): Boolean =
        encodedLength > MAX_ENCRYPTED_SESSION_CHARACTERS

    fun compactText(value: String): String = value.take(MAX_GENERAL_TEXT_CHARACTERS)

    fun compactActionText(value: String): String = value.take(MAX_ACTION_TEXT_CHARACTERS)

    fun compactAuditText(value: String): String = value.take(MAX_AUDIT_TEXT_CHARACTERS)

    fun compactMetadata(metadata: Map<String, String>): Map<String, String> = metadata.entries
        .sortedBy { (key, _) -> if (key in RECOVERY_METADATA_KEYS) 0 else 1 }
        .take(MAX_METADATA_ENTRIES)
        .associate { (key, value) ->
            key.take(128) to value.take(MAX_METADATA_VALUE_CHARACTERS)
        }

    private val RECOVERY_METADATA_KEYS = setOf(
        "delivery_failed",
        "source_message_id",
        "awaiting_response",
        "contact_id",
        "resource_id",
        "failure_domain",
        "resource_started_at",
        "handoff_recovery_attempt"
    )

    private const val MAX_NON_PROJECT_ACTION_HISTORY = 24

    fun compactScreen(screen: ScreenContext): ScreenContext = screen.copy(
        foregroundApp = screen.foregroundApp.take(256),
        activityName = screen.activityName.take(256),
        pageTitle = screen.pageTitle.take(256),
        visibleTexts = emptyList(),
        selectedText = screen.selectedText.take(MAX_SCREEN_LABEL_CHARACTERS),
        focusedInputField = screen.focusedInputField?.copy(
            label = screen.focusedInputField.label.take(MAX_SCREEN_LABEL_CHARACTERS),
            viewId = screen.focusedInputField.viewId.take(256),
            className = screen.focusedInputField.className.take(256),
            bounds = screen.focusedInputField.bounds.take(128)
        ),
        clickableElements = emptyList(),
        inputFields = emptyList(),
        scrollableRegions = emptyList(),
        sensitiveFlags = screen.sensitiveFlags.take(8).map { it.take(128) },
        visualScene = screen.visualScene.copy(
            modelProfile = screen.visualScene.modelProfile.take(128),
            elements = emptyList()
        ),
        clipboard = ClipboardContext(),
        notifications = AgentNotificationContext(
            hasAccess = screen.notifications.hasAccess,
            totalCount = screen.notifications.totalCount
        ),
        installedApps = emptyList(),
        deviceStatus = screen.deviceStatus.copy(network = screen.deviceStatus.network.take(64))
    )
}

internal inline fun <reified T : Enum<T>> enumOrDefault(value: String, default: T): T =
    runCatching { enumValueOf<T>(value) }.getOrElse { default }

internal fun String.removePrefixIgnoreCase(prefix: String): String =
    if (startsWith(prefix, ignoreCase = true)) drop(prefix.length) else this

internal fun String.normalizedElementQuery(): String =
    lowercase(Locale.US).replace(Regex("[^\\p{L}\\p{N}]+"), "")

internal fun String.stableActionId(): String =
    normalizedElementQuery().take(24).ifBlank { "action" }

internal fun sensitiveFlagsForText(value: String): List<String> {
    val lower = value.lowercase(Locale.US)
    val flags = SENSITIVE_MEMORY_TERMS.filter { lower.contains(it) }.toMutableList()
    if (Regex("\\b\\d{4,8}\\b").containsMatchIn(value) &&
        listOf("code", "otp", "verification", "2fa", "sms").any { lower.contains(it) }
    ) {
        flags += "verification_code"
    }
    return flags.distinct().take(6)
}
