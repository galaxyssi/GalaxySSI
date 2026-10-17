package com.galaxyssi.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** Debug-only ADB entry point for non-destructive native-tool audits on a real device. */
class AgentNativeToolAuditReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val pending = goAsync()
        Thread {
            try {
                val toolId = intent.getStringExtra("tool_id").orEmpty()
                val encodedGoal = intent.getStringExtra("goal_base64").orEmpty()
                val workspaceId = intent.getStringExtra("inspect_workspace_id").orEmpty()
                val checkpointFixture = intent.getBooleanExtra("checkpoint_fixture", false)
                val timingFixture = intent.getBooleanExtra("timing_fixture", false)
                val outcomeRecoveryFixture = intent.getBooleanExtra("outcome_recovery_fixture", false)
                val operationRuntimeFixture = intent.getBooleanExtra("operation_runtime_fixture", false)
                val observationEvidenceFixture = intent.getBooleanExtra("observation_evidence_fixture", false)
                val artifactEvidenceFixture = intent.getBooleanExtra("artifact_evidence_fixture", false)
                val report = when {
                    artifactEvidenceFixture -> AgentArtifactEvidenceDeviceFixture.run(context.cacheDir.toPath())
                    observationEvidenceFixture -> AgentObservationEvidenceDeviceFixture.run {
                        runSingleTool(context.applicationContext, AgentAndroidSystemNativeTools.AUDIO_STATUS, "", "evidence-freshness")
                    }
                    operationRuntimeFixture -> AgentOperationRuntimeDeviceFixture.run(context.applicationContext)
                    outcomeRecoveryFixture -> verifyUnverifiedOutcomeRecovery(context.applicationContext)
                    timingFixture -> verifyAgentProcessTiming(context.applicationContext)
                    checkpointFixture -> verifyOperationCheckpoints(context.applicationContext)
                    workspaceId.isNotBlank() -> inspectWorkspace(context.applicationContext, workspaceId)
                    encodedGoal.isNotBlank() -> runGoal(context.applicationContext, encodedGoal)
                    toolId.isNotBlank() -> runSingleTool(
                        context.applicationContext,
                        toolId,
                        intent.getStringExtra("input_base64").orEmpty(),
                        intent.getStringExtra("audit_scope").orEmpty()
                    )
                    else -> runAudit(context.applicationContext)
                }
                val fileName = when {
                    artifactEvidenceFixture -> "native-artifact-evidence-fixture.json"
                    observationEvidenceFixture -> "native-observation-evidence-fixture.json"
                    operationRuntimeFixture -> "native-operation-runtime-fixture.json"
                    outcomeRecoveryFixture -> "native-outcome-recovery-fixture.json"
                    timingFixture -> "native-timing-fixture.json"
                    checkpointFixture -> "native-checkpoint-fixture.json"
                    workspaceId.isNotBlank() -> "native-workspace-audit.json"
                    encodedGoal.isNotBlank() -> GOAL_REPORT_FILE
                    toolId.isNotBlank() -> SINGLE_REPORT_FILE
                    else -> REPORT_FILE
                }
                File(context.filesDir, fileName).writeText(report.toString(2))
                Log.i(TAG, "Native tool audit complete: ${toolId.ifBlank { if (encodedGoal.isBlank()) "catalog" else "goal" }}")
            } catch (error: Throwable) {
                Log.e(TAG, "Native tool audit failed", error)
            } finally {
                pending.finish()
            }
        }.start()
    }

    private fun inspectWorkspace(context: Context, workspaceId: String): JSONObject {
        require(UUID.fromString(workspaceId).toString() == workspaceId) { "A single workspace UUID is required" }
        val store = SharedPreferencesAgentSessionStore(context, "task:$workspaceId")
        val workspace = EncryptedAgentWorkspaceStore(context).find(workspaceId)
        val operation = workspace?.conversationId?.let {
            AgentRunEventStore(context).snapshot(AgentDeviceOperationCheckpoint.runId(it))
        }
        val projectedOperation = workspace?.conversationId?.let { AgentDeviceOperationStore(context).get(it) }
        return JSONObject().put("workspace_id", workspaceId)
            .put("workspace", workspace?.let {
                JSONObject(AgentWorkspaceJsonCodec.encode(it))
            })
            .put("session", store.load()?.let(store::encodeSession))
            .put("operation_ledger_state", operation?.state?.name)
            .put("operation_ledger_event", operation?.lastEvent?.type?.name)
            .put("operation_ledger_payload", operation?.lastEvent?.payload?.let(::JSONObject))
            .put("operation_projected_status", projectedOperation?.status)
            .put("operation_projected_context", projectedOperation?.context())
    }

    private fun verifyOperationCheckpoints(context: Context): JSONObject {
        val database = "debug-operation-${UUID.randomUUID()}.db"
        var ledger = AgentRunEventStore(context, database)
        try {
            val first = AgentDeviceOperation("debug-operation", kind = "agent", goal = "create a synthetic document",
                status = "waiting_accessibility", dispatched = true, evidence = "existing-effect-receipt")
            var store = AgentDeviceOperationStore(ledger)
            store.save(first)
            check(ledger.latestEvent(AgentDeviceOperationCheckpoint.runId(first.conversationId))
                ?.payload?.get("recovery_mode") == "observation_only")
            ledger.close()
            ledger = AgentRunEventStore(context, database)
            store = AgentDeviceOperationStore(ledger)
            check(store.get(first.conversationId)?.id == first.id)
            val old = requireNotNull(ledger.latestEvent(AgentDeviceOperationCheckpoint.runId(first.conversationId)))
            ledger.appendNext(old.copy(eventId = UUID.randomUUID().toString(), idempotencyKey = UUID.randomUUID().toString(),
                type = AgentRunControlEventType.RUN_FAILED, payload = (old.payload - "recovery_mode") +
                    mapOf("reason" to "interrupted_run_cannot_be_replayed_safely", "replay_safe" to false)))
            check(ledger.snapshot(old.runId)?.state == AgentRunControlState.FAILED)
            val restored = requireNotNull(store.get(first.conversationId))
            store.save(restored)
            check(store.get(first.conversationId)?.let {
                it.id == first.id && it.status == first.status && it.dispatched && it.evidence == first.evidence
            } == true)
            check(ledger.latestEvent(old.runId)?.type == AgentRunControlEventType.RUN_RECOVERED)
            store.recordPlan(first.conversationId, "modify the synthetic document", null, sourceTurnId = "fixture-turn")
            check(store.get(first.conversationId)?.goal == "modify the synthetic document")
            ledger.close()
            ledger = AgentRunEventStore(context, database)
            store = AgentDeviceOperationStore(ledger)
            val reopened = requireNotNull(store.get(first.conversationId))
            check(reopened.sourceTurnId == "fixture-turn")
            val conversation = AgentConversationContext(first.conversationId, "", listOf(AgentTranscriptEntry(
                "fixture-user", AgentTranscriptRole.USER, "modify the synthetic document", 1,
                conversationId = first.conversationId, turnId = "fixture-turn")), false)
            check(AgentSupervisedProjectContinuationPolicy.scopedOperation(conversation, reopened)?.id == reopened.id)
            check(AgentSupervisedProjectContinuationPolicy.scopedOperation(conversation.copy(turns = listOf(
                conversation.turns.single().copy(turnId = "new-independent-turn"))), reopened) == null)
            check(store.get("another-conversation") == null)
            return JSONObject().put("passed", true).put("cases", JSONArray(listOf(
                "observation_only_checkpoint", "reopen_preserves_identity", "legacy_failure_repaired_without_execution",
                "follow_up_checkpoint_saved", "conversation_isolation", "turn_owner_survives_reopen", "stale_turn_context_rejected")))
        } finally {
            ledger.close()
            check(context.deleteDatabase(database)) { "Fixture database cleanup failed" }
        }
    }

    private fun runGoal(context: Context, encodedGoal: String): JSONObject {
        val goal = String(Base64.decode(encodedGoal, Base64.NO_WRAP), Charsets.UTF_8)
        val started = System.currentTimeMillis()
        val state = MobileNativeAgent(
            context,
            sessionStore = SharedPreferencesAgentSessionStore(context, "debug-native-goal")
        ).submitGoal(
            goal = goal,
            conversationContext = AgentConversationContext("debug-native-goal", "Debug native goal", emptyList(), true),
            turnId = UUID.randomUUID().toString()
        )
        return JSONObject()
            .put("goal", goal)
            .put("phase", state.phase.name)
            .put("tool_id", state.lastActionResult?.metadata?.get("native_tool_id").orEmpty())
            .put("message", state.lastActionResult?.message.orEmpty())
            .put("elapsed_ms", System.currentTimeMillis() - started)
    }

    private fun runSingleTool(context: Context, toolId: String, encodedInput: String, auditScope: String): JSONObject {
        require(auditScope.isBlank() || auditScope.matches(Regex("[A-Za-z0-9_-]{1,64}"))) { "Invalid audit scope" }
        val scope = if (auditScope.isBlank()) "native-audit" else "native-audit-$auditScope"
        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(
            context = context,
            screenProvider = { ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent") }
        )
        val descriptor = registry.lookup(toolId)?.descriptor
            ?: return JSONObject().put("tool_id", toolId).put("error", "unknown_tool")
        val json = if (encodedInput.isBlank()) JSONObject() else JSONObject(
            String(Base64.decode(encodedInput, Base64.NO_WRAP), Charsets.UTF_8)
        )
        val input = json.keys().asSequence().associateWith { key -> nativeJsonValue(json.opt(key)) }
        val started = System.currentTimeMillis()
        val result = registry.invoke(
            id = toolId,
            input = input,
            context = AgentNativeToolInvocationContext(
                sessionId = scope,
                conversationId = scope,
                turnId = UUID.randomUUID().toString(),
                callerId = "galaxyssi.debug.native_audit",
                idempotencyKey = "audit-$toolId-${UUID.randomUUID()}",
                grantedPermissions = descriptor.requiredPermissions.mapTo(linkedSetOf()) { it.id },
                grantedConsents = descriptor.requiredConsents.mapTo(linkedSetOf()) { it.id },
                attributes = mapOf("execution_authority" to "galaxyssi-phone")
            )
        )
        return JSONObject(result.toJson())
            .put("tool_id", toolId)
            .put("elapsed_ms", System.currentTimeMillis() - started)
    }

    private fun nativeJsonValue(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { key -> nativeJsonValue(value.opt(key)) }
        is JSONArray -> (0 until value.length()).map { index -> nativeJsonValue(value.opt(index)) }
        else -> value
    }

    private fun runAudit(context: Context): JSONObject {
        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(
            context = context,
            screenProvider = { ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent") }
        )
        val started = System.currentTimeMillis()
        val rows = JSONArray()
        var executed = 0
        var succeeded = 0
        var protected = 0
        var unavailable = 0
        var skipped = 0

        registry.descriptors().sortedBy { it.id }.forEach { descriptor ->
            val row = JSONObject()
                .put("tool_id", descriptor.id)
                .put("risk", descriptor.risk.wireValue)
                .put("location", descriptor.location.wireValue)
                .put("availability", descriptor.availability.status.wireValue)
            val input = safeInput(descriptor.id, started)
            val safe = descriptor.id in SAFE_REAL_DEVICE_TOOLS
            when {
                !safe -> {
                    protected += 1
                    row.put("test_status", "protected_not_executed")
                }
                input == null -> {
                    skipped += 1
                    row.put("test_status", "fixture_unavailable")
                }
                else -> {
                    val invocationStarted = System.currentTimeMillis()
                    val result = registry.invoke(
                        id = descriptor.id,
                        input = input,
                        context = AgentNativeToolInvocationContext(
                            sessionId = "native-audit",
                            conversationId = "native-audit",
                            turnId = UUID.randomUUID().toString(),
                            callerId = "galaxyssi.debug.native_audit",
                            idempotencyKey = "audit-${descriptor.id}-${UUID.randomUUID()}",
                            grantedPermissions = descriptor.requiredPermissions.mapTo(linkedSetOf()) { it.id },
                            grantedConsents = descriptor.requiredConsents.mapTo(linkedSetOf()) { it.id },
                            attributes = mapOf("execution_authority" to "galaxyssi-phone")
                        )
                    )
                    val elapsed = System.currentTimeMillis() - invocationStarted
                    executed += 1
                    if (result.isSuccess) succeeded += 1
                    if (result.error?.code == "tool_unavailable" || result.error?.code == "missing_permissions") unavailable += 1
                    row.put("test_status", if (result.isSuccess) "passed" else "failed")
                        .put("elapsed_ms", elapsed)
                        .put("result_status", result.status.wireValue)
                        .put("message", result.message.take(500))
                        .put("error_code", result.error?.code.orEmpty())
                        .put("error_message", result.error?.message.orEmpty().take(500))
                        .put("error_details", JSONObject(result.error?.details.orEmpty()))
                        .put("output", JSONObject(result.output))
                }
            }
            rows.put(row)
        }
        return JSONObject()
            .put("device_epoch_ms", System.currentTimeMillis())
            .put("catalog_size", registry.descriptors().size)
            .put("executed", executed)
            .put("succeeded", succeeded)
            .put("failed", executed - succeeded)
            .put("unavailable", unavailable)
            .put("protected", protected)
            .put("skipped", skipped)
            .put("elapsed_ms", System.currentTimeMillis() - started)
            .put("results", rows)
    }

    private fun safeInput(id: String, now: Long): AgentNativeJsonObject? = when (id) {
        AgentHardwareNativeTools.BATTERY_STATUS,
        AgentHardwareNativeTools.POWER_STATUS,
        AgentHardwareNativeTools.STORAGE_STATUS,
        AgentHardwareNativeTools.NETWORK_STATUS,
        AgentHardwareNativeTools.BLUETOOTH_STATUS,
        AgentHardwareNativeTools.NFC_STATUS,
        AgentAndroidSystemNativeTools.TELEPHONY_STATUS,
        AgentAndroidSystemNativeTools.TELEPHONY_CALL_STATE,
        AgentAndroidSystemNativeTools.CALENDARS_LIST,
        AgentAndroidSystemNativeTools.WIFI_STATUS,
        AgentAndroidSystemNativeTools.WIFI_SCAN_START,
        AgentAndroidSystemNativeTools.AUDIO_STATUS,
        AgentAndroidSystemNativeTools.BIOMETRIC_STATUS,
        AgentAndroidSystemNativeTools.VPN_STATUS,
        AgentAndroidSystemNativeTools.DEVICE_POLICY_STATUS -> emptyMap()

        AgentHardwareNativeTools.LOCATION_FOREGROUND_READ -> mapOf("timeout_ms" to 5_000)
        AgentHardwareNativeTools.SENSORS_LIST -> mapOf("limit" to 16)
        AgentHardwareNativeTools.SENSOR_SAMPLE -> mapOf("type" to "accelerometer", "timeout_ms" to 3_000)
        AgentHardwareNativeTools.BLUETOOTH_DISCOVERY_FOREGROUND -> mapOf("timeout_ms" to 5_000, "limit" to 8)
        AgentHardwareNativeTools.INSTALLED_APPS_LIST -> mapOf("query" to "", "limit" to 20)
        AgentHardwareNativeTools.PACKAGE_DETAIL -> mapOf("package_name" to contextPackageName)
        AgentAndroidSystemNativeTools.TELEPHONY_CALL_STATE_OBSERVE -> mapOf("timeout_ms" to 1_000)
        AgentAndroidSystemNativeTools.SMS_LIST -> mapOf("limit" to 3)
        AgentAndroidSystemNativeTools.CONTACTS_SEARCH -> mapOf("query" to "", "limit" to 3)
        AgentAndroidSystemNativeTools.CALENDAR_EVENTS_QUERY -> mapOf(
            "start_epoch_ms" to now - 86_400_000L,
            "end_epoch_ms" to now + 604_800_000L,
            "limit" to 5
        )
        AgentAndroidSystemNativeTools.WIFI_SCAN_RESULTS -> mapOf("limit" to 8)
        AgentAndroidSystemNativeTools.DOWNLOAD_QUERY -> mapOf("download_id" to Long.MAX_VALUE)
        AgentWebMediaNativeTools.WEB_SEARCH -> mapOf("query" to "GalaxySSI", "max_results" to 2, "timeout_ms" to 10_000)
        AgentWebMediaNativeTools.WEB_OPEN,
        AgentWebMediaNativeTools.BROWSER_RENDER,
        AgentWebMediaNativeTools.WEB_FETCH -> mapOf("url" to "https://example.com", "max_bytes" to 65_536, "timeout_ms" to 5_000)
        AgentWebMediaNativeTools.WEB_HEAD -> mapOf("url" to "https://example.com", "timeout_ms" to 5_000)
        AgentWebMediaNativeTools.HTTP_REQUEST -> mapOf("url" to "https://example.com", "method" to "HEAD", "timeout_ms" to 5_000)
        AgentWebMediaNativeTools.CONTENT_EXTRACT -> mapOf("content" to "<h1>GalaxySSI</h1><p>Native audit</p>")
        else -> null
    }

    companion object {
        private const val ACTION = "com.galaxyssi.chat.DEBUG_NATIVE_TOOL_AUDIT"
        private const val REPORT_FILE = "native-tool-audit.json"
        private const val SINGLE_REPORT_FILE = "native-tool-single.json"
        private const val GOAL_REPORT_FILE = "native-goal-audit.json"
        private const val TAG = "GalaxySSI-NativeAudit"
        private const val contextPackageName = "com.galaxyssi.chat"

        private val SAFE_REAL_DEVICE_TOOLS = setOf(
            AgentHardwareNativeTools.BATTERY_STATUS,
            AgentHardwareNativeTools.POWER_STATUS,
            AgentHardwareNativeTools.STORAGE_STATUS,
            AgentHardwareNativeTools.NETWORK_STATUS,
            AgentHardwareNativeTools.LOCATION_FOREGROUND_READ,
            AgentHardwareNativeTools.SENSORS_LIST,
            AgentHardwareNativeTools.SENSOR_SAMPLE,
            AgentHardwareNativeTools.BLUETOOTH_STATUS,
            AgentHardwareNativeTools.BLUETOOTH_DISCOVERY_FOREGROUND,
            AgentHardwareNativeTools.NFC_STATUS,
            AgentHardwareNativeTools.INSTALLED_APPS_LIST,
            AgentHardwareNativeTools.PACKAGE_DETAIL,
            AgentAndroidSystemNativeTools.TELEPHONY_STATUS,
            AgentAndroidSystemNativeTools.TELEPHONY_CALL_STATE,
            AgentAndroidSystemNativeTools.TELEPHONY_CALL_STATE_OBSERVE,
            AgentAndroidSystemNativeTools.SMS_LIST,
            AgentAndroidSystemNativeTools.CONTACTS_SEARCH,
            AgentAndroidSystemNativeTools.CALENDARS_LIST,
            AgentAndroidSystemNativeTools.CALENDAR_EVENTS_QUERY,
            AgentAndroidSystemNativeTools.WIFI_STATUS,
            AgentAndroidSystemNativeTools.WIFI_SCAN_RESULTS,
            AgentAndroidSystemNativeTools.WIFI_SCAN_START,
            AgentAndroidSystemNativeTools.AUDIO_STATUS,
            AgentAndroidSystemNativeTools.DOWNLOAD_QUERY,
            AgentAndroidSystemNativeTools.BIOMETRIC_STATUS,
            AgentAndroidSystemNativeTools.VPN_STATUS,
            AgentAndroidSystemNativeTools.DEVICE_POLICY_STATUS,
            AgentWebMediaNativeTools.WEB_SEARCH,
            AgentWebMediaNativeTools.WEB_OPEN,
            AgentWebMediaNativeTools.BROWSER_RENDER,
            AgentWebMediaNativeTools.CONTENT_EXTRACT,
            AgentWebMediaNativeTools.HTTP_REQUEST,
            AgentWebMediaNativeTools.WEB_HEAD,
            AgentWebMediaNativeTools.WEB_FETCH
        )
    }
}
