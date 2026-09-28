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
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.TextView
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
                .put("kind", progress?.optString("kind").orEmpty())
                .put("title", progress?.optString("title").orEmpty())
        }
    }

    @Test fun realBusinessConversations() {
        assumeTrue(args.getString("business_live") == "true")
        assertEquals("Only the explicitly selected S26U may run this suite", "SM-S9480", Build.MODEL)
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
                    result.put("task_id", final.taskId).put("reply", final.text).put("rich_output", final.richOutputJson)
                        .put("assessment", BusinessScenarioFixtures.assess(turn, final.text))
                    val rendered = await(15000) {
                        var visible = false
                        instrumentation.runOnMainSync {
                            visible = window.agentTranscriptWindow.entries.any {
                                it.turnId == turnId && it.role == AgentTranscriptRole.ASSISTANT && it.text == final.text
                            }
                        }
                        visible
                    }
                    result.put("rendered", rendered)
                    var visibleText = ""
                    instrumentation.runOnMainSync { visibleText = texts(window.agentOutputList).joinToString("\n") }
                    result.put("visible_text", visibleText)
                        .put("timer_stopped", visibleText.contains("已处理") && !visibleText.contains("处理中"))
                        .put("within_latency_target", result.getLong("elapsed_ms") <= case.getLong("latency_target_ms"))
                    capture(directory, "$caseId-$index.png")
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

    private fun capture(directory: File, name: String) {
        val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: return
        File(directory, name).outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }

    private fun texts(view: View): List<String> = if (view is ViewGroup) {
        (0 until view.childCount).flatMap { texts(view.getChildAt(it)) }
    } else if (view is TextView && view.isShown) listOf(view.text.toString()) else emptyList()

    private fun JSONArray.containsInt(value: Int): Boolean = (0 until length()).any { optInt(it, -1) == value }
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
