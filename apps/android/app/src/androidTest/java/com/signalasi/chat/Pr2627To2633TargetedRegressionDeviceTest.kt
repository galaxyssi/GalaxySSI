package com.signalasi.chat

import android.os.Build
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class Pr2627To2633TargetedRegressionDeviceTest {
    @Test
    fun runsOneThousandTargetedCasesOnSmG9880() {
        assertEquals("This suite must run only on the requested phone", "SM-G9880", Build.MODEL)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val assets = instrumentation.context.assets
        val directory = "pr2627-pr2633-targeted-regression"
        val manifest = JSONObject(assets.open("$directory/manifest.json").bufferedReader().use { it.readText() })
        val failures = mutableListOf<String>()
        val executions = mutableListOf<Pr2627To2633CaseExecution>()

        manifest.getJSONArray("suite_files").strings().forEach { fileName ->
            val suite = JSONObject(assets.open("$directory/$fileName").bufferedReader().use { it.readText() })
            suite.getJSONArray("cases").objects().forEach { case ->
                val started = System.nanoTime()
                val failure = runCatching {
                    Pr2627To2633RegressionOracles.verify(
                        suiteId = case.getString("suite_id"),
                        profileId = case.getString("profile_id"),
                        variantIndex = case.getInt("variant_index")
                    )
                }.exceptionOrNull()
                val durationMillis = (System.nanoTime() - started) / 1_000_000L
                val passed = failure == null
                if (!passed) failures += "${case.getString("id")}: ${failure?.message ?: failure?.javaClass?.name}"
                Log.i(
                    "SignalASIRegression",
                    "case=${case.getString("id")} passed=$passed duration_ms=$durationMillis"
                )
                executions += Pr2627To2633CaseExecution(
                    case = case,
                    passed = passed,
                    durationMillis = durationMillis,
                    failure = failure?.stackTraceToString().orEmpty().take(4_000)
                )
            }
        }

        assertEquals(manifest.getInt("exact_case_count"), executions.size)
        assertEquals(manifest.getInt("exact_conversation_count"), executions.size)
        assertEquals(1_000, executions.size)
        assertEquals(1_000, executions.map { it.case.getString("risk_id") }.distinct().size)
        assertEquals(1_000, executions.map { it.case.getString("conversation_id") }.distinct().size)

        val persistence = Pr2627To2633VisibleConversationRecorder.persist(
            instrumentation.targetContext,
            executions
        )
        val records = JSONArray().apply {
            executions.forEach { execution ->
                val case = execution.case
                put(JSONObject()
                    .put("id", case.getString("id"))
                    .put("risk_id", case.getString("risk_id"))
                    .put("conversation_id", case.getString("conversation_id"))
                    .put("title_zh", case.getString("title_zh"))
                    .put("pr", case.getInt("pr"))
                    .put("suite_id", case.getString("suite_id"))
                    .put("profile_id", case.getString("profile_id"))
                    .put("oracle", case.getString("oracle"))
                    .put("passed", execution.passed)
                    .put("duration_ms", execution.durationMillis)
                    .put("conversation_persisted", true)
                    .put("failure", execution.failure))
            }
        }
        val durations = executions.map(Pr2627To2633CaseExecution::durationMillis).sorted()

        val report = JSONObject()
            .put("schema_version", 2)
            .put("benchmark_id", manifest.getString("benchmark_id"))
            .put("device_model", Build.MODEL)
            .put("device_fingerprint", Build.FINGERPRINT)
            .put("app_version", BuildConfig.VERSION_NAME)
            .put("case_count", executions.size)
            .put("passed_count", executions.size - failures.size)
            .put("failed_count", failures.size)
            .put("p50_duration_ms", percentile(durations, 50))
            .put("p95_duration_ms", percentile(durations, 95))
            .put("p99_duration_ms", percentile(durations, 99))
            .put("maximum_duration_ms", durations.lastOrNull() ?: 0L)
            .put("visible_conversation_count", persistence.requestedCount)
            .put("visible_conversation_persisted_count", persistence.persistedCount)
            .put("conversation_count_before", persistence.existingConversationCountBefore)
            .put("conversation_count_after", persistence.totalConversationCountAfter)
            .put("conversation_persistence_duration_ms", persistence.durationMillis)
            .put("records", records)
        val reportFile = File(
            instrumentation.targetContext.filesDir,
            "test-reports/pr2627-pr2633-targeted-regression.json"
        )
        reportFile.parentFile?.mkdirs()
        reportFile.writeText(report.toString(2), Charsets.UTF_8)

        assertEquals(1_000, persistence.requestedCount)
        assertEquals(1_000, persistence.persistedCount)
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    private fun percentile(sorted: List<Long>, percentile: Int): Long {
        if (sorted.isEmpty()) return 0L
        val index = ((sorted.size - 1) * percentile / 100.0).toInt()
        return sorted[index]
    }

    private fun JSONArray.strings(): List<String> = (0 until length()).map(::getString)
    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map(::getJSONObject)
}
