package com.galaxyssi.chat

import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.SystemClock
import android.view.KeyEvent
import android.view.WindowManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in real composer test. No mocked transport, model, results, or transcript injection. */
@RunWith(AndroidJUnit4::class)
class BusinessScenarioLiveDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val args = InstrumentationRegistry.getArguments()
    private val root by lazy { File(context.getExternalFilesDir(null), "business-eval").apply { mkdirs() } }
    private val events = CopyOnWriteArrayList<JSONObject>()
    @Volatile private var observedConversation = ""
    @Volatile private var background = false
    private val listener = object : GalaxySSIMqttClient.Listener {
        override fun onMessage(payload: String) {
            val envelope = runCatching { JSONObject(payload) }.getOrNull() ?: return
            if (envelope.optString("conversation_id") != observedConversation) return
            val progress = envelope.optJSONObject("progress_event")
            events += JSONObject().put("received_at", System.currentTimeMillis())
                .put("type", envelope.optString("type")).put("status", envelope.optString("task_status"))
                .put("task", envelope.optString("task_id")).put("turn", envelope.optString("turn_id"))
                .put("agent", envelope.optString("agent_id")).put("background", background)
                .put("source", envelope.optString("source_message_id"))
                .put("registered_identity", AgentTaskIdentityStore.matchesRegistered(context, envelope))
                .put("foreground", AppForegroundTracker.isForeground())
                .put("content_chars", envelope.optString("content").length)
                .put("rich_chars", AgentRichContentCodec.fromEnvelope(envelope).length)
                .put("final_decodable", AgentRemoteOutcomeCodec.decode(envelope, "probe") != null)
                .put("kind", progress?.optString("kind").orEmpty())
                .put("title", progress?.optString("title").orEmpty())
        }
    }

    @Test fun realBusinessConversations() {
        assumeTrue(args.getString("business_live") == "true")
        requireBusinessDevice(args.getString("business_device_model", "SM-S9480"))
        check(!context.getSystemService(KeyguardManager::class.java).isDeviceLocked) {
            "Unlock the test phone before running visible composer and output checks"
        }
        val runId = requireNotNull(args.getString("business_run"))
        require(runId.matches(Regex("[A-Za-z0-9_-]{1,64}")))
        val catalog = JSONObject(File(root, "plan.json").readText())
        val selected = args.getString("business_cases", "B001").split(',').toSet()
        val turnLimit = args.getString("business_turn_limit", "11").toInt().also { require(it in 1..11) }
        val timeout = args.getString("business_turn_timeout_ms", "240000").toLong().also { require(it in 30000..900000) }
        val provider = args.getString("business_provider", "codex")
        require(provider in setOf("codex", "deepseek"))
        val target = selectBusinessTarget(AppStoreAgentConnectorRegistry(context).availableTargets(), provider)
            ?: error("Configured $provider unavailable")
        val directory = File(root, runId).apply { mkdirs() }
        val snapshot = File(directory, "catalog.json")
        if (snapshot.exists()) {
            require(JSONObject(snapshot.readText()).getString("catalog_sha256") == catalog.getString("catalog_sha256"))
        } else snapshot.writeText(catalog.toString(2))
        val cases = catalog.getJSONArray("cases")
        val matched = (0 until cases.length()).map(cases::getJSONObject).filter { it.getString("id") in selected }
        require(matched.size == selected.size) { "Unknown case ID" }
        GalaxySSIMqttClient.addListener(listener)
        try {
            for (case in matched) runCase(directory, catalog, case, target, turnLimit, timeout)
        } finally {
            GalaxySSIMqttClient.removeListener(listener)
        }
    }

    @Test fun configuredTargetPreflight() {
        assumeTrue(args.getString("business_preflight") == "true")
        requireBusinessDevice(args.getString("business_device_model", "SM-S9480"))
        val provider = args.getString("business_provider", "codex")
        val target = selectBusinessTarget(AppStoreAgentConnectorRegistry(context).availableTargets(), provider)
        println("BUSINESS_PREFLIGHT device=${Build.MODEL} provider=$provider available=${target != null}")
        assertNotNull("Configure a paired $provider target before the live suite", target)
    }

    private fun runCase(directory: File, catalog: JSONObject, case: JSONObject,
                        target: AgentCallableTarget, turnLimit: Int, timeout: Long) {
        val caseId = case.getString("id")
        val file = File(directory, "$caseId.json")
        val key = "business-${directory.name}-$caseId"
        val store = AgentTranscriptStore(context, key)
        val report = if (file.exists()) JSONObject(file.readText()) else {
            val conversation = store.createConversation("业务验证 $caseId ${case.getString("name")}", privateMode = true)
            JSONObject().put("schema", 1).put("case_id", caseId).put("name", case.getString("name"))
                .put("catalog_sha256", catalog.getString("catalog_sha256")).put("device", Build.MODEL)
                .put("app_version", BuildConfig.VERSION_NAME).put("target", target.id)
                .put("app_updated_at", context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime)
                .put("requested_model", target.invocationProfile.normalizedModelId(""))
                .put("conversation", conversation.id).put("window_key", key).put("turns", JSONArray())
        }
        require(report.getString("catalog_sha256") == catalog.getString("catalog_sha256"))
        require(report.getString("target") == target.id)
        val conversation = report.getString("conversation")
        observedConversation = conversation
        AgentModelSelectionSettings.selectManual(context, conversation, target.id,
            target.invocationProfile.normalizedModelId(""), target.title, rememberAsDefault = false)
        var window = launch(key)
        var fatal = false
        try {
            val turns = case.getJSONArray("turns")
            val results = report.getJSONArray("turns")
            for (index in 0 until minOf(turnLimit, turns.length())) {
                if (index < results.length() && results.getJSONObject(index).optString("state") == "completed") continue
                if (index < results.length()) {
                    val recorded = results.getJSONObject(index)
                    if (args.getString("business_continue_after_late") == "true" &&
                        recorded.optString("state") == "observation_timeout") {
                        val receipt = JSONObject(File(directory, "$caseId-$index-late.json").readText())
                        require(receipt.getString("catalog_sha256") == catalog.getString("catalog_sha256"))
                        require(receipt.getString("conversation") == conversation)
                        require(receipt.getString("turn_id") == recorded.getString("turn_id"))
                        require(receipt.getJSONObject("assessment").getBoolean("correct"))
                        require(receipt.getBoolean("visible"))
                        val lateTurn = recorded.getString("turn_id")
                        require(EncryptedAgentWorkspaceStore(context).find(lateTurn)?.status?.isTerminal == true)
                        require(lateTurn !in AgentTaskRuntime.supervisor(context).activeTaskIds())
                        require(store.list(conversation).any { it.id == receipt.getString("entry_id") &&
                            it.turnId == lateTurn && it.role == AgentTranscriptRole.ASSISTANT &&
                            !AgentTranscriptRenderPolicy.isLiveStream(it) })
                        continue
                    }
                    error("Unresolved checkpoint $caseId/$index; inspect recorded turn before retrying with a new run ID")
                }
                if (case.getJSONArray("restore_turns").containsInt(index)) {
                    instrumentation.runOnMainSync { window.finishAndRemoveTask() }
                    window = launch(key)
                }
                val turn = turns.getJSONObject(index)
                val fixtures = if (index == 0) (0 until case.getJSONArray("fixtures").length())
                    .map { BusinessScenarioFixtures.image(directory, case, it) } else emptyList()
                val result = JSONObject().put("index", index).put("kind", turn.getString("kind"))
                    .put("driver_schema", 4).put("capture_method", "target_reply_and_process_rows_three_matching_frames")
                    .put("execution_app_version", BuildConfig.VERSION_NAME)
                    .put("execution_app_version_code", BuildConfig.VERSION_CODE)
                    .put("execution_app_updated_at", context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime)
                    .put("state", "prepared").put("prompt", turn.getString("prompt"))
                    .put("input_images", fixtures.size).put("started_at", System.currentTimeMillis())
                    .put("sample_before", sample())
                results.put(result)
                report.put("status", "running")
                save(file, report)
                events.clear()
                background = false
                var clicked = false
                val start = SystemClock.elapsedRealtime()
                instrumentation.runOnMainSync {
                    window.agentInputAttachments.addAll(fixtures)
                    window.renderAgentInputAttachments()
                    window.agentGoalInput.setText(turn.getString("prompt"))
                    clicked = window.agentSubmitButton.performClick()
                }
                check(clicked) { "Composer did not accept $caseId/$index" }
                result.put("state", "submitted")
                save(file, report)
                var user: AgentTranscriptEntry? = null
                check(await(15000) {
                    user = store.list(conversation).lastOrNull {
                        it.role == AgentTranscriptRole.USER && it.text.trim() == turn.getString("prompt").trim() &&
                            it.timestampMillis >= result.getLong("started_at") - 1000
                    }
                    user != null
                }) { "Composer did not persist the submitted user turn" }
                val turnId = requireNotNull(user).turnId
                check(turnId.isNotBlank())
                result.put("turn_id", turnId)
                save(file, report)
                if (case.getJSONArray("background_turns").containsInt(index)) {
                    instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_HOME)
                    background = true
                }
                var reply: AgentTranscriptEntry? = null
                var firstAt = 0L
                val workspaces = EncryptedAgentWorkspaceStore(context)
                val completed = await(timeout) {
                    val entries = store.list(conversation).filter { it.turnId == turnId }
                    val assistant = entries.lastOrNull {
                        it.role == AgentTranscriptRole.ASSISTANT && !AgentTranscriptRenderPolicy.isLiveStream(it) &&
                            !it.dedupeKey.startsWith("remote-approval:")
                    }
                    if (firstAt == 0L && (assistant != null || events.any { it.optString("kind").isNotBlank() })) {
                        firstAt = SystemClock.elapsedRealtime() - start
                    }
                    val workspace = workspaces.find(turnId)
                    // Receiving a child/model response is not completion of the parent run.
                    val settled = workspace?.status?.isTerminal == true &&
                        turnId !in AgentTaskRuntime.supervisor(context).activeTaskIds()
                    if (assistant != null && settled) reply = assistant
                    assistant != null && settled
                }
                result.put("elapsed_ms", SystemClock.elapsedRealtime() - start)
                    .put("first_observation_ms", firstAt).put("received_in_background", background)
                    .put("events", JSONArray(events)).put("sample_after", sample())
                    .put("workspace_status", workspaces.find(turnId)?.status?.name)
                    .put("state", if (completed) "completed" else "observation_timeout")
                val manager = context.getSystemService(ActivityManager::class.java)
                manager.appTasks.firstOrNull { it.taskInfo.taskId == window.taskId }?.moveToFront()
                background = false
                if (completed) {
                    val final = requireNotNull(reply)
                    val completedWorkspace = workspaces.find(final.turnId)
                    result.put("task_id", final.taskId).put("reply", final.text).put("rich_output", final.richOutputJson)
                        .put("initial_entry_id", final.id).put("reply_identity_schema", 1)
                    val assessmentStartedMs = SystemClock.elapsedRealtime() - start
                    val assessment = if (turn.has("artifact_expectations")) {
                        BusinessArtifactEvidence.collect(context, turn.getJSONObject("artifact_expectations"),
                            File(directory, "$caseId-$index-artifacts")) {
                            resolveBusinessReply(store.list(conversation), final, completedWorkspace)
                        }
                    } else BusinessScenarioFixtures.assess(turn, final.text)
                    val assessmentFinishedMs = SystemClock.elapsedRealtime() - start
                    result.put("assessment", assessment)
                    val rendered = await(15000) {
                        var visible = false
                        instrumentation.runOnMainSync {
                            visible = resolveBusinessReply(window.agentTranscriptWindow.entries, final,
                                completedWorkspace) != null
                        }
                        visible
                    }
                    result.put("transcript_loaded", rendered)
                    val capture = captureBusinessOutput(instrumentation, window, File(directory, "$caseId-$index.png"), final.id) {
                        resolveBusinessReply(window.agentTranscriptWindow.entries, final,
                            completedWorkspace)?.id
                    }
                    val timer = captureProcess(window, turnId, File(directory, "$caseId-$index-process.png"))
                    result.put("rendered", rendered && capture.targetVisible && capture.focused)
                    result.put("visible_text", capture.text)
                        .put("visual_capture_stable", capture.stable)
                        .put("visual_window_focused", capture.focused)
                        .put("visual_entry_id", capture.entryId)
                        .put("process_visible_text", timer?.text.orEmpty())
                        .put("timer_observed", timer?.targetVisible == true && timer.focused)
                        .put("timer_stopped", timerStopped(window, timer))
                        .put("within_latency_target", result.getLong("elapsed_ms") <= case.getLong("latency_target_ms"))
                    result.put("phase_timing", businessPhaseTiming(result.getLong("elapsed_ms"),
                        assessmentStartedMs, assessmentFinishedMs, SystemClock.elapsedRealtime() - start,
                        turn.has("artifact_expectations"), assessment))
                } else {
                    fatal = true
                    report.put("status", "blocked_on_turn")
                }
                save(file, report)
                println("BUSINESS_EVAL case=$caseId turn=$index state=${result.getString("state")} ms=${result.getLong("elapsed_ms")} correct=${result.optJSONObject("assessment")?.optBoolean("correct")}")
                if (fatal) break
            }
            if (!fatal) report.put("status", if (report.getJSONArray("turns").length() == case.getJSONArray("turns").length()) "completed" else "partial")
            save(file, report)
        } finally {
            instrumentation.runOnMainSync { if (!window.isDestroyed) window.finishAndRemoveTask() }
            observedConversation = ""
        }
        assertFalse("Test turn timed out; retained checkpoint prevents duplicate sends", fatal)
    }

    private fun captureProcess(window: MainActivity, turnId: String, file: File): BusinessVisualCapture? {
        var entryId: String? = null
        instrumentation.runOnMainSync {
            entryId = AgentTranscriptPresentationPolicy.collapseProcessGroups(
                window.renderedAgentTranscriptSourceEntries
            ).lastOrNull {
                it.turnId == turnId && it.role == AgentTranscriptRole.PROCESS &&
                    window.agentTranscriptAdapter.indexOfEntry(it.id) >= 0
            }?.id
        }
        return entryId?.let { captureBusinessOutput(instrumentation, window, file, it) }
    }

    private fun timerStopped(window: MainActivity, capture: BusinessVisualCapture?): Boolean {
        val processed = window.getString(R.string.agent_trace_processed, "", "").trim()
        val processing = window.getString(R.string.agent_trace_processing, "", "").trim()
        return capture != null && capture.stable && capture.focused && capture.targetVisible &&
            capture.text.contains(processed) && !capture.text.contains(processing)
    }

    @Test fun observeLateCompletedArtifact() {
        assumeTrue(args.getString("business_observe_late") == "true")
        requireBusinessDevice(args.getString("business_device_model", "SM-T575"))
        check(!context.getSystemService(KeyguardManager::class.java).isDeviceLocked)
        val runId = requireNotNull(args.getString("business_run"))
        val caseId = requireNotNull(args.getString("business_cases"))
        require(runId.matches(Regex("[A-Za-z0-9_-]{1,64}")) && caseId.matches(Regex("A[0-9]{3}")))
        val index = requireNotNull(args.getString("business_capture_turn")).toInt()
        val directory = File(root, runId)
        val report = JSONObject(File(directory, "$caseId.json").readText())
        val recorded = report.getJSONArray("turns").getJSONObject(index)
        require(recorded.getString("state") == "observation_timeout")
        val catalog = JSONObject(File(directory, "catalog.json").readText())
        require(catalog.getString("catalog_sha256") == report.getString("catalog_sha256"))
        val cases = catalog.getJSONArray("cases")
        val case = (0 until cases.length()).map(cases::getJSONObject).single { it.getString("id") == caseId }
        val turn = case.getJSONArray("turns").getJSONObject(index)
        val conversation = report.getString("conversation")
        val turnId = recorded.getString("turn_id")
        val store = AgentTranscriptStore(context, report.getString("window_key"))
        val window = launch(report.getString("window_key"))
        val auditDirectory = File(directory, "$caseId-$index-late-${System.currentTimeMillis()}").apply { mkdirs() }
        try {
            var reply: AgentTranscriptEntry? = null
            check(await(30000) {
                reply = store.list(conversation).lastOrNull { it.turnId == turnId &&
                    it.role == AgentTranscriptRole.ASSISTANT && !AgentTranscriptRenderPolicy.isLiveStream(it) &&
                    !it.dedupeKey.startsWith("remote-approval:") }
                reply != null && EncryptedAgentWorkspaceStore(context).find(turnId)?.status?.isTerminal == true &&
                    turnId !in AgentTaskRuntime.supervisor(context).activeTaskIds()
            }) { "Original task has not settled on the phone; no resend or continuation is allowed" }
            val final = requireNotNull(reply)
            val assessment = BusinessArtifactEvidence.collect(context, turn.getJSONObject("artifact_expectations"),
                File(auditDirectory, "artifacts")) { store.list(conversation).lastOrNull { it.id == final.id } }
            val audit = JSONObject().put("catalog_sha256", catalog.getString("catalog_sha256"))
                .put("conversation", conversation).put("turn_id", turnId).put("entry_id", final.id)
                .put("observed_at", System.currentTimeMillis()).put("original_state", recorded.getString("state"))
                .put("reply", final.text).put("rich_output", final.richOutputJson).put("assessment", assessment)
                .put("visible", false).put("timer_stopped", false).put("audit_directory", auditDirectory.name)
            File(auditDirectory, "audit.json").writeText(audit.toString(2))
            require(assessment.getBoolean("correct")) { "Late artifact delivery did not pass; original timeout retained" }
            check(await(15000) {
                var loaded = false
                instrumentation.runOnMainSync {
                    loaded = window.agentTranscriptAdapter.indexOfEntry(final.id) >= 0
                    if (!loaded) window.loadOlderAgentTranscriptEntries()
                }
                loaded
            }) { "Late final reply exists in storage but is not loaded in this conversation window" }
            val capture = captureBusinessOutput(instrumentation, window, File(auditDirectory, "reply.png"), final.id)
            val timer = captureProcess(window, turnId, File(auditDirectory, "process.png"))
            audit.put("visible", capture.targetVisible && capture.focused && capture.stable)
                .put("timer_stopped", timerStopped(window, timer))
            File(auditDirectory, "audit.json").writeText(audit.toString(2))
            require(audit.getBoolean("visible")) { "Late final reply is not visibly verified" }
            File(directory, "$caseId-$index-late.json").writeText(audit.toString(2))
            println("BUSINESS_LATE_AUDIT ${auditDirectory.absolutePath}")
        } finally {
            instrumentation.runOnMainSync { if (!window.isDestroyed) window.finishAndRemoveTask() }
        }
    }

    @Test fun recaptureCompletedTurns() {
        assumeTrue(args.getString("business_recapture") == "true")
        requireBusinessDevice(args.getString("business_device_model", "SM-S9480"))
        check(!context.getSystemService(KeyguardManager::class.java).isDeviceLocked)
        val runId = requireNotNull(args.getString("business_run"))
        require(runId.matches(Regex("[A-Za-z0-9_-]{1,64}")))
        val caseId = requireNotNull(args.getString("business_cases"))
        require(caseId.matches(Regex("[AB][0-9]{3}")))
        val directory = File(root, runId)
        val report = JSONObject(File(directory, "$caseId.json").readText())
        val turns = report.getJSONArray("turns")
        val selectedTurn = args.getString("business_capture_turn")?.toInt()
        require(selectedTurn == null || selectedTurn in 0 until turns.length()) { "Capture turn is out of range" }
        require(args.getString("business_artifact_ui") != "true" || selectedTurn != null) {
            "Artifact UI audit requires one explicit capture turn"
        }
        val auditDirectory = File(directory, "capture-audit-${System.currentTimeMillis()}").apply { mkdirs() }
        val store = AgentTranscriptStore(context, report.getString("window_key"))
        val window = launch(report.getString("window_key"))
        val audit = JSONArray()
        try {
            for (index in 0 until turns.length()) {
                val turn = turns.getJSONObject(index)
                if (turn.optString("state") != "completed") continue
                if (selectedTurn != null && index != selectedTurn) continue
                val reference = AgentTranscriptEntry(
                    id = turn.optString("initial_entry_id", turn.optString("visual_entry_id")),
                    role = AgentTranscriptRole.ASSISTANT, text = turn.getString("reply"), timestampMillis = 0L,
                    conversationId = report.getString("conversation"), turnId = turn.getString("turn_id"),
                    taskId = turn.getString("task_id"), richOutputJson = turn.optString("rich_output")
                )
                val reply = requireNotNull(resolveBusinessReply(store.list(reference.conversationId), reference,
                    EncryptedAgentWorkspaceStore(context).find(reference.turnId))) {
                    "Recorded turn/task/content identity does not match a current final reply"
                }
                check(await(15000) {
                    var loaded = false
                    instrumentation.runOnMainSync {
                        loaded = window.agentTranscriptAdapter.indexOfEntry(reply.id) >= 0
                        if (!loaded) window.loadOlderAgentTranscriptEntries()
                    }
                    loaded
                }) { "Recorded final reply is not loaded" }
                val capture = captureBusinessOutput(instrumentation, window, File(auditDirectory, "$index.png"), reply.id)
                val timer = captureProcess(window, reply.turnId, File(auditDirectory, "$index-process.png"))
                audit.put(JSONObject().put("index", index).put("entry_id", reply.id)
                    .put("original_entry_id", reference.id).put("task_id", reply.taskId).put("reply_identity_schema", 1)
                    .put("target_visible", capture.targetVisible).put("stable", capture.stable)
                    .put("focused", capture.focused).put("visible_text", capture.text)
                    .put("process_visible_text", timer?.text.orEmpty()).put("timer_stopped", timerStopped(window, timer)))
                File(auditDirectory, "audit.json").writeText(audit.toString(2))
                assertTrue("Current reply was not visible", capture.targetVisible && capture.focused && capture.stable)
                if (args.getString("business_artifact_ui") == "true") {
                    auditBusinessImageUi(instrumentation, window, reply, auditDirectory)
                }
            }
            assertTrue("No completed turn was audited", audit.length() > 0)
            println("BUSINESS_CAPTURE_AUDIT ${auditDirectory.absolutePath}")
        } finally {
            instrumentation.runOnMainSync { window.finishAndRemoveTask() }
        }
    }

    private fun launch(key: String): MainActivity {
        val monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        try {
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$key"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, key)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            val window = instrumentation.waitForMonitorWithTimeout(monitor, 60000) as? MainActivity ?: error("Window missing")
            check(await(60000) {
                var ready = false
                instrumentation.runOnMainSync {
                    window.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    ready = !window.initialAgentHydrationPending && window.conversationWindow.conversationId.isNotBlank()
                }
                ready
            }) { "Window hydration timeout" }
            return window
        } finally { instrumentation.removeMonitor(monitor) }
    }

    private fun sample(): JSONObject {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        return JSONObject().put("at", System.currentTimeMillis()).put("pss_kib", Debug.getPss())
            .put("cpu_ms", android.os.Process.getElapsedCpuTime())
            .put("temperature_tenths_c", battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1))
            .put("battery_level", battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1))
            .put("plugged", battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1))
            .put("thermal_status", context.getSystemService(PowerManager::class.java).currentThermalStatus)
    }

    private fun await(timeout: Long, predicate: () -> Boolean): Boolean {
        val deadline = SystemClock.elapsedRealtime() + timeout
        do {
            if (predicate()) return true
            SystemClock.sleep(250)
        } while (SystemClock.elapsedRealtime() < deadline)
        return false
    }

    private fun save(file: File, value: JSONObject) {
        val temporary = File(file.parentFile, file.name + ".tmp")
        temporary.writeText(value.toString(2))
        java.nio.file.Files.move(temporary.toPath(), file.toPath(),
            java.nio.file.StandardCopyOption.REPLACE_EXISTING)
    }

    private fun JSONArray.containsInt(value: Int): Boolean = (0 until length()).any { optInt(it, -1) == value }
}

internal fun requireBusinessDevice(expected: String) {
    require(expected in setOf("SM-S9480", "SM-T575")) { "Unsupported business test device" }
    assertEquals("Only the explicitly selected business test device may run this suite", expected, Build.MODEL)
}

internal fun selectBusinessTarget(targets: List<AgentCallableTarget>, provider: String): AgentCallableTarget? {
    require(provider in setOf("codex", "deepseek"))
    return targets.filter { target ->
        target.status == AgentConnectorStatus.AVAILABLE && when (provider) {
            "codex" -> target.kind == AgentConnectorKind.AGENT && target.id.endsWith(":codex")
            else -> target.kind == AgentConnectorKind.MODEL && target.adapterType == "cloud-model-api" &&
                (target.providerProfile?.providerId == "deepseek" || target.failureDomain == "cloud:deepseek")
        }
    }.sortedBy { it.id }.firstOrNull()
}
