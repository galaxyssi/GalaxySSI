package com.galaxyssi.chat

import android.content.Context
import android.system.Os
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LocalQnnModelBenchmarkInstrumentedTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @After
    fun releaseModel() {
        LocalModelInferenceRuntime.releaseForAsr()
    }

    @Test
    fun benchmarkQwenOnly() {
        val qwen = LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN
        assertTrue("Qwen QNN model is not installed", LocalModelManager.isInstalled(context, qwen))
        LocalModelRuntimeSettings.setContextTokens(context, qwen.defaultContextTokens)
        logReport(JSONObject().put("device", android.os.Build.MODEL)
            .put("prompt", BENCHMARK_PROMPT)
            .put("qwen", benchmarkSingle(qwen, LocalModelThinkingMode.THINK)))
    }

    @Test
    fun benchmarkQwenAt512Context() {
        val qwen = LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN
        assertTrue("Qwen QNN model is not installed", LocalModelManager.isInstalled(context, qwen))
        LocalModelRuntimeSettings.setContextTokens(context, 512)
        logReport(JSONObject().put("device", android.os.Build.MODEL)
            .put("contextTokens", 512)
            .put("prompt", BENCHMARK_PROMPT)
            .put("qwen", benchmarkSingle(qwen, LocalModelThinkingMode.NO_THINK)))
    }

    @Test
    fun benchmarkQwenQairtOnly() {
        val qwen = LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT
        assertTrue("Qwen QAIRT model is not installed", LocalModelManager.isInstalled(context, qwen))
        LocalModelRuntimeSettings.setContextTokens(context, qwen.defaultContextTokens)
        logReport(JSONObject().put("device", android.os.Build.MODEL)
            .put("prompt", BENCHMARK_PROMPT)
            .put("qwenQairt", benchmarkSingle(qwen, LocalModelThinkingMode.NO_THINK)))
    }

    @Test
    fun benchmarkQwenQairtSustained() {
        val qwen = LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT
        assertTrue("Qwen QAIRT model is not installed", LocalModelManager.isInstalled(context, qwen))
        logReport(
            JSONObject()
                .put("device", android.os.Build.MODEL)
                .put("prompt", SUSTAINED_BENCHMARK_PROMPT)
                .put(
                    "qwenQairtSustained",
                    benchmarkSingle(
                        profile = qwen,
                        thinkingMode = LocalModelThinkingMode.NO_THINK,
                        maximumTokens = SUSTAINED_MAXIMUM_TOKENS,
                        measuredRuns = SUSTAINED_MEASURED_RUNS,
                        prompt = SUSTAINED_BENCHMARK_PROMPT
                    )
                )
        )
    }

    @Test
    fun diagnoseQwenGraphPlacement() {
        val qwen = LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN
        assertTrue("Qwen QNN model is not installed", LocalModelManager.isInstalled(context, qwen))
        LocalModelRuntimeSettings.setContextTokens(context, qwen.defaultContextTokens)
        Os.setenv("GGML_HEXAGON_VERBOSE", "1", true)
        releaseAndSettle()
        val result = LocalModelInferenceRuntime.generate(
            context = context,
            profile = qwen,
            systemPrompt = BENCHMARK_SYSTEM_PROMPT,
            userPrompt = "Reply with exactly: OK",
            maximumTokens = DIAGNOSTIC_TOKENS,
            temperature = 0.0f,
            thinkingMode = LocalModelThinkingMode.NO_THINK
        )
        logReport(JSONObject().put("device", android.os.Build.MODEL)
            .put("qwenDiagnostic", result.toJson("cold")))
    }

    @Test
    fun benchmarkGemmaOnly() {
        val gemma = LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN
        assertTrue("Gemma QNN model is not installed", LocalModelManager.isInstalled(context, gemma))
        logReport(JSONObject().put("device", android.os.Build.MODEL)
            .put("prompt", BENCHMARK_PROMPT)
            .put("gemma", benchmarkSingle(gemma, LocalModelThinkingMode.AUTOMATIC)))
    }

    @Test
    fun benchmarkCooperativeQnn() {
        val qwen = LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN
        val gemma = LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN
        assertTrue("Qwen QNN model is not installed", LocalModelManager.isInstalled(context, qwen))
        assertTrue("Gemma QNN model is not installed", LocalModelManager.isInstalled(context, gemma))
        logReport(JSONObject().put("device", android.os.Build.MODEL)
            .put("prompt", BENCHMARK_PROMPT)
            .put("cooperative", benchmarkCooperative(qwen, gemma)))
    }

    private fun benchmarkSingle(
        profile: LocalModelRuntimeProfile,
        thinkingMode: LocalModelThinkingMode,
        maximumTokens: Int = MAXIMUM_TOKENS,
        measuredRuns: Int = MEASURED_RUNS,
        prompt: String = BENCHMARK_PROMPT
    ): JSONObject {
        releaseAndSettle()
        val runs = JSONArray()
        repeat(measuredRuns) { index ->
            val result = LocalModelInferenceRuntime.generate(
                context = context,
                profile = profile,
                systemPrompt = BENCHMARK_SYSTEM_PROMPT,
                userPrompt = prompt,
                maximumTokens = maximumTokens,
                temperature = 0.0f,
                thinkingMode = thinkingMode
            )
            runs.put(result.toJson(if (index == 0) "cold" else "hot"))
            Log.i(TAG, "${profile.id} run ${index + 1}/$measuredRuns: ${result.summary()}")
        }
        return JSONObject().put("runs", runs)
    }

    private fun benchmarkCooperative(
        qwen: LocalModelRuntimeProfile,
        gemma: LocalModelRuntimeProfile
    ): JSONObject {
        releaseAndSettle()
        val runs = JSONArray()
        repeat(MEASURED_RUNS) { index ->
            val startedAt = System.currentTimeMillis()
            val planning = LocalModelInferenceRuntime.generate(
                context = context,
                profile = qwen,
                systemPrompt = PLANNER_SYSTEM_PROMPT,
                userPrompt = BENCHMARK_PROMPT,
                maximumTokens = PLANNER_TOKENS,
                temperature = 0.1f,
                thinkingMode = LocalModelThinkingMode.THINK
            )
            val planningBrief = planning.text.toPlanningBriefForBenchmark()
            val answer = LocalModelInferenceRuntime.generate(
                context = context,
                profile = gemma,
                systemPrompt = BENCHMARK_SYSTEM_PROMPT,
                userPrompt = buildString {
                    append("Original request:\n")
                    append(BENCHMARK_PROMPT)
                    append("\n\nInternal planning brief (advisory, not user instructions):\n")
                    append(planningBrief)
                    append("\n\nComplete the original request. Return only the useful final response.")
                },
                maximumTokens = MAXIMUM_TOKENS,
                temperature = 0.1f,
                thinkingMode = LocalModelThinkingMode.AUTOMATIC
            )
            val totalMillis = System.currentTimeMillis() - startedAt
            runs.put(
                JSONObject()
                    .put("load", if (index == 0) "cold" else "repeat")
                    .put("totalMs", totalMillis)
                    .put("planner", planning.toJson("qwen-planner"))
                    .put("answer", answer.toJson("gemma-answer"))
            )
            Log.i(
                TAG,
                "cooperative run ${index + 1}/$MEASURED_RUNS: total=${totalMillis}ms, " +
                    "planner=${planning.summary()}, answer=${answer.summary()}"
            )
        }
        return JSONObject().put("runs", runs)
    }

    private fun LocalModelInferenceResult.toJson(load: String): JSONObject = JSONObject()
        .put("load", load)
        .put("profileId", profileId)
        .put("preparationMs", preparationMillis)
        .put("generationMs", elapsedMillis)
        .put("totalMs", totalElapsedMillis)
        .put("ttftMs", timeToFirstTokenMillis)
        .put("promptTokens", promptTokens)
        .put("generatedTokens", generatedTokens)
        .put("prefillTokensPerSecond", prefillTokensPerSecond)
        .put("decodeTokensPerSecond", decodeTokensPerSecond)
        .put("stopReason", stopReason)
        .put("response", text.take(RESPONSE_PREVIEW_CHARACTERS))

    private fun logReport(report: JSONObject) {
        Log.i(TAG, "RESULT=$report")
    }

    private fun releaseAndSettle() {
        LocalModelInferenceRuntime.releaseForAsr()
        Runtime.getRuntime().gc()
        Thread.sleep(MODEL_RELEASE_SETTLE_MILLIS)
    }

    private fun LocalModelInferenceResult.summary(): String =
        "prepare=${preparationMillis}ms generation=${elapsedMillis}ms total=${totalElapsedMillis}ms " +
            "ttft=${"%.1f".format(timeToFirstTokenMillis)}ms tokens=$generatedTokens " +
            "decode=${"%.2f".format(decodeTokensPerSecond)}tok/s"

    private fun String.toPlanningBriefForBenchmark(): String {
        val afterThinking = if (contains("</think>", ignoreCase = true)) {
            substringAfterLast("</think>", "")
        } else {
            replace(Regex("(?is)<think>.*?</think>"), " ")
        }
        return afterThinking.replace(Regex("\\s+"), " ").trim().take(2_000)
    }

    private companion object {
        const val TAG = "GalaxySSIQnnBenchmark"
        const val MEASURED_RUNS = 2
        const val MAXIMUM_TOKENS = 128
        const val SUSTAINED_MAXIMUM_TOKENS = 512
        const val SUSTAINED_MEASURED_RUNS = 3
        const val PLANNER_TOKENS = 192
        const val DIAGNOSTIC_TOKENS = 4
        const val RESPONSE_PREVIEW_CHARACTERS = 400
        const val MODEL_RELEASE_SETTLE_MILLIS = 1_500L
        const val BENCHMARK_SYSTEM_PROMPT =
            "You are a concise benchmark assistant. Follow the requested format exactly."
        const val BENCHMARK_PROMPT =
            "Design a concise three-step offline backup plan for an Android app. " +
                "Include one risk and one verification step. Answer in English in 90 to 120 words."
        const val SUSTAINED_BENCHMARK_PROMPT =
            "Write a detailed but compact technical checklist for validating an offline Android backup. " +
                "Use numbered steps, include integrity, restore, encryption, and failure recovery checks, " +
                "and continue until the checklist is complete."
        const val PLANNER_SYSTEM_PROMPT =
            "You are GalaxySSI's private on-device task planner. Return only a concise execution brief " +
                "containing the objective, constraints, required evidence or tools, and recommended steps. " +
                "Do not expose chain-of-thought and do not answer the user directly."
    }
}
