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
        val records = JSONArray()
        val failures = mutableListOf<String>()
        var caseCount = 0

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
                records.put(JSONObject()
                    .put("id", case.getString("id"))
                    .put("pr", case.getInt("pr"))
                    .put("suite_id", case.getString("suite_id"))
                    .put("profile_id", case.getString("profile_id"))
                    .put("passed", passed)
                    .put("duration_ms", durationMillis)
                    .put("failure", failure?.stackTraceToString().orEmpty().take(4_000)))
                caseCount += 1
            }
        }

        val report = JSONObject()
            .put("schema_version", 1)
            .put("benchmark_id", manifest.getString("benchmark_id"))
            .put("device_model", Build.MODEL)
            .put("device_fingerprint", Build.FINGERPRINT)
            .put("app_version", BuildConfig.VERSION_NAME)
            .put("case_count", caseCount)
            .put("passed_count", caseCount - failures.size)
            .put("failed_count", failures.size)
            .put("records", records)
        val reportFile = File(
            instrumentation.targetContext.filesDir,
            "test-reports/pr2627-pr2633-targeted-regression.json"
        )
        reportFile.parentFile?.mkdirs()
        reportFile.writeText(report.toString(2), Charsets.UTF_8)

        assertEquals(manifest.getInt("exact_case_count"), caseCount)
        assertEquals(1000, caseCount)
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    private fun JSONArray.strings(): List<String> = (0 until length()).map(::getString)
    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map(::getJSONObject)
}
