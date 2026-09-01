package com.signalasi.chat

import android.content.Context
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale
import java.util.UUID

enum class AgentAndroidWorldVerifierKind(val wireValue: String) {
    FOREGROUND_PACKAGE("foreground_package"),
    VISIBLE_TEXT("visible_text"),
    APP_FILE("app_file"),
    SYSTEM_SETTING("system_setting")
}

data class AgentAndroidWorldVerifier(
    val id: String = UUID.randomUUID().toString(),
    val kind: AgentAndroidWorldVerifierKind,
    val key: String,
    val expected: String,
    val operator: String = "equals"
)

data class AgentAndroidWorldTask(
    val id: String,
    val instruction: String,
    val category: String,
    val requiredPackages: List<String>,
    val verifiers: List<AgentAndroidWorldVerifier>,
    val sourceVersion: String = "androidworld-adapter-v1"
)

data class AgentAndroidWorldObservation(
    val foregroundPackage: String,
    val visibleTexts: List<String>,
    val appFiles: Map<String, Boolean>,
    val systemSettings: Map<String, String>,
    val capturedAtMillis: Long = System.currentTimeMillis()
)

data class AgentAndroidWorldVerifierResult(
    val verifierId: String,
    val passed: Boolean,
    val actual: String,
    val reason: String
)

data class AgentAndroidWorldResult(
    val id: String = UUID.randomUUID().toString(),
    val taskId: String,
    val runId: String,
    val passed: Boolean,
    val verifierResults: List<AgentAndroidWorldVerifierResult>,
    val capturedAtMillis: Long = System.currentTimeMillis()
)

object AgentAndroidWorldTaskCodec {
    fun decode(raw: String): AgentAndroidWorldTask = decode(JSONObject(raw))

    fun decode(json: JSONObject): AgentAndroidWorldTask {
        val id = json.optString("task_id").ifBlank { json.optString("id") }.trim().take(200)
        val instruction = json.optString("instruction").ifBlank { json.optString("goal") }
            .trim().take(4_000)
        val verifierArray = json.optJSONArray("verifiers") ?: json.optJSONArray("success_criteria") ?: JSONArray()
        val verifiers = buildList {
            for (index in 0 until verifierArray.length()) {
                val item = verifierArray.optJSONObject(index) ?: continue
                val kind = AgentAndroidWorldVerifierKind.entries.firstOrNull {
                    it.wireValue == item.optString("kind").trim().lowercase(Locale.ROOT)
                } ?: continue
                add(AgentAndroidWorldVerifier(
                    id = item.optString("id").trim().ifBlank { UUID.randomUUID().toString() },
                    kind = kind,
                    key = item.optString("key").trim().take(1_000),
                    expected = item.optString("expected").trim().take(2_000),
                    operator = item.optString("operator", "equals").trim().lowercase(Locale.ROOT).take(40)
                ))
            }
        }
        require(id.isNotBlank() && instruction.isNotBlank() && verifiers.isNotEmpty()) {
            "AndroidWorld task requires id, instruction, and at least one supported verifier"
        }
        return AgentAndroidWorldTask(
            id = id,
            instruction = instruction,
            category = json.optString("category", "device_control").trim().take(120),
            requiredPackages = json.optJSONArray("required_packages").strings().distinct().take(20),
            verifiers = verifiers.take(40),
            sourceVersion = json.optString("source_version", "androidworld-adapter-v1").trim().take(120)
        )
    }

    fun encode(task: AgentAndroidWorldTask): JSONObject = JSONObject()
        .put("task_id", task.id)
        .put("instruction", task.instruction)
        .put("category", task.category)
        .put("required_packages", JSONArray(task.requiredPackages))
        .put("source_version", task.sourceVersion)
        .put("verifiers", JSONArray().apply {
            task.verifiers.forEach { verifier ->
                put(JSONObject()
                    .put("id", verifier.id)
                    .put("kind", verifier.kind.wireValue)
                    .put("key", verifier.key)
                    .put("expected", verifier.expected)
                    .put("operator", verifier.operator))
            }
        })

    private fun JSONArray?.strings(): List<String> = buildList {
        if (this@strings == null) return@buildList
        for (index in 0 until length()) optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
    }
}

object AgentAndroidWorldEvaluator {
    fun evaluate(
        task: AgentAndroidWorldTask,
        observation: AgentAndroidWorldObservation,
        runId: String
    ): AgentAndroidWorldResult {
        val results = task.verifiers.map { verifier ->
            val actual = when (verifier.kind) {
                AgentAndroidWorldVerifierKind.FOREGROUND_PACKAGE -> observation.foregroundPackage
                AgentAndroidWorldVerifierKind.VISIBLE_TEXT -> observation.visibleTexts.joinToString("\n")
                AgentAndroidWorldVerifierKind.APP_FILE -> observation.appFiles[verifier.key]?.toString().orEmpty()
                AgentAndroidWorldVerifierKind.SYSTEM_SETTING -> observation.systemSettings[verifier.key].orEmpty()
            }
            val passed = compare(actual, verifier.expected, verifier.operator)
            AgentAndroidWorldVerifierResult(
                verifierId = verifier.id,
                passed = passed,
                actual = actual.take(2_000),
                reason = if (passed) "verified" else "${verifier.kind.wireValue}:${verifier.operator}"
            )
        }
        return AgentAndroidWorldResult(
            taskId = task.id,
            runId = runId,
            passed = results.isNotEmpty() && results.all(AgentAndroidWorldVerifierResult::passed),
            verifierResults = results
        )
    }

    private fun compare(actual: String, expected: String, operator: String): Boolean {
        val left = actual.trim()
        val right = expected.trim()
        return when (operator) {
            "contains" -> left.contains(right, ignoreCase = true)
            "not_contains" -> !left.contains(right, ignoreCase = true)
            "exists" -> left.equals("true", ignoreCase = true)
            "not_exists" -> left.equals("false", ignoreCase = true)
            "matches" -> runCatching { Regex(right, RegexOption.IGNORE_CASE).containsMatchIn(left) }
                .getOrDefault(false)
            else -> left.equals(right, ignoreCase = true)
        }
    }
}

class AgentAndroidWorldStore(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    fun import(raw: String): AgentAndroidWorldTask = AgentAndroidWorldTaskCodec.decode(raw).also { task ->
        database.writeString("$TASK_PREFIX${task.id}", AgentAndroidWorldTaskCodec.encode(task).toString())
    }

    @Synchronized
    fun tasks(limit: Int = 200): List<AgentAndroidWorldTask> = database.entries(TASK_PREFIX)
        .mapNotNull { runCatching { AgentAndroidWorldTaskCodec.decode(it.second) }.getOrNull() }
        .sortedBy(AgentAndroidWorldTask::id)
        .take(limit.coerceIn(1, 200))

    @Synchronized
    fun matching(goal: String): AgentAndroidWorldTask? {
        val normalized = normalize(goal)
        return tasks().firstOrNull { task ->
            normalize(task.instruction) == normalized ||
                normalized.contains("[androidworld:${task.id.lowercase(Locale.ROOT)}]")
        }
    }

    @Synchronized
    fun save(result: AgentAndroidWorldResult) {
        database.writeString("$RESULT_PREFIX${result.id}", encodeResult(result).toString())
    }

    @Synchronized
    fun results(limit: Int = 500): List<AgentAndroidWorldResult> = database.entries(RESULT_PREFIX)
        .mapNotNull { decodeResult(it.second) }
        .sortedByDescending(AgentAndroidWorldResult::capturedAtMillis)
        .take(limit.coerceIn(1, 500))

    private fun encodeResult(value: AgentAndroidWorldResult) = JSONObject()
        .put("id", value.id).put("task_id", value.taskId).put("run_id", value.runId)
        .put("passed", value.passed).put("captured_at_millis", value.capturedAtMillis)
        .put("verifier_results", JSONArray().apply {
            value.verifierResults.forEach { result ->
                put(JSONObject().put("verifier_id", result.verifierId).put("passed", result.passed)
                    .put("actual", result.actual).put("reason", result.reason))
            }
        })

    private fun decodeResult(raw: String): AgentAndroidWorldResult? = runCatching {
        val json = JSONObject(raw)
        val array = json.getJSONArray("verifier_results")
        val results = buildList {
            for (index in 0 until array.length()) array.optJSONObject(index)?.let { item ->
                add(AgentAndroidWorldVerifierResult(
                    verifierId = item.getString("verifier_id"),
                    passed = item.optBoolean("passed"),
                    actual = item.optString("actual"),
                    reason = item.optString("reason")
                ))
            }
        }
        AgentAndroidWorldResult(
            id = json.getString("id"), taskId = json.getString("task_id"), runId = json.getString("run_id"),
            passed = json.optBoolean("passed"), verifierResults = results,
            capturedAtMillis = json.optLong("captured_at_millis")
        )
    }.getOrNull()

    private fun normalize(value: String): String = value.lowercase(Locale.ROOT)
        .replace(Regex("\\s+"), " ").trim()

    private companion object {
        const val DATABASE = "signalasi_android_world_adapter_v1"
        const val TASK_PREFIX = "task:"
        const val RESULT_PREFIX = "result:"
    }
}

class AgentAndroidWorldBridge(private val context: Context) {
    private val appContext = context.applicationContext
    private val store = AgentAndroidWorldStore(appContext)

    fun evaluateMatching(run: AgentRecordedRun): AgentAndroidWorldResult? {
        val task = store.matching(run.originalRequest) ?: return null
        val screen = ScreenPerceptionState.current("SignalASI", "")
        val observation = AgentAndroidWorldObservation(
            foregroundPackage = ScreenPerceptionState.currentPackageName().ifBlank { screen.foregroundApp },
            visibleTexts = screen.visibleTexts,
            appFiles = task.verifiers.filter { it.kind == AgentAndroidWorldVerifierKind.APP_FILE }
                .associate { verifier -> verifier.key to appFileExists(verifier.key) },
            systemSettings = task.verifiers.filter { it.kind == AgentAndroidWorldVerifierKind.SYSTEM_SETTING }
                .associate { verifier -> verifier.key to readSetting(verifier.key) }
        )
        return AgentAndroidWorldEvaluator.evaluate(task, observation, run.runId).also(store::save)
    }

    private fun appFileExists(value: String): Boolean {
        val candidate = File(value).let { file -> if (file.isAbsolute) file else File(appContext.filesDir, value) }
        val canonical = runCatching { candidate.canonicalFile }.getOrNull() ?: return false
        val roots = listOfNotNull(appContext.filesDir, appContext.cacheDir, appContext.getExternalFilesDir(null))
            .mapNotNull { runCatching { it.canonicalFile }.getOrNull() }
        return roots.any { root -> canonical.path == root.path || canonical.path.startsWith(root.path + File.separator) } &&
            canonical.exists()
    }

    private fun readSetting(key: String): String {
        val namespace = key.substringBefore(':', "secure").lowercase(Locale.ROOT)
        val name = key.substringAfter(':', key).trim()
        if (name.isBlank()) return ""
        return runCatching {
            when (namespace) {
                "system" -> Settings.System.getString(appContext.contentResolver, name)
                "global" -> Settings.Global.getString(appContext.contentResolver, name)
                else -> Settings.Secure.getString(appContext.contentResolver, name)
            }.orEmpty()
        }.getOrDefault("")
    }
}
