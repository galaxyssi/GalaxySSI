package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Opt-in prompt regression: only synthetic context is sent to the already configured cloud provider. */
class HealthCareClarificationLiveTest {
    @Test fun configuredDeepSeekAcknowledgesSavedAnswersWithoutRepeatingThem() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_health_clarification") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val contacts = AppStore.contacts(context)
        val selected = requireNotNull((0 until contacts.length()).mapNotNull { contacts.optJSONObject(it) }
            .filter { !it.optBoolean("deleted", false) && it.optString("delivery_mode") == "cloud_api" }
            .map { AppStore.selectedCloudModelContact(context, it.optString("id")) ?: it }
            .firstOrNull { it.optString("cloud_model").contains("deepseek", true) && CloudModelCredentialPolicy.isAutoRoutable(it) }) {
            "No configured DeepSeek provider; do not change credentials or fall back to Desktop"
        }
        val contact = CloudModelRequestRoutingPolicy.resolve(selected, requestedModelId = "", hasImageInput = false)
        val now = System.currentTimeMillis()
        val record = HealthCareRecordRef(UUID.randomUUID().toString(), 1)
        val sample = HealthCareSample(record, HealthMetric.GLUCOSE, now, mapOf("glucose" to "5.9"), "mmol/L", "",
            "fasting", "unspecified", "manual", "", "")
        val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "synthetic",
            HealthCareAssessment(record, now, "5.9", "mmol/L", "", setOf(HealthCareSignal.GLUCOSE_CONTEXT), sample = sample))
        val complete = HealthCareContext(record, HealthCareTruth.YES, HealthCareTruth.NO, HealthCareTruth.NO,
            HealthCareSpecimen.HOME_CAPILLARY, 10, HealthCareTruth.NO, now)
        val reports = JSONArray()
        val report = File(context.cacheDir, "health-clarification-live-report.json")
        try {
            listOf("complete" to complete, "partial" to complete.copy(pregnant = HealthCareTruth.UNKNOWN, fastingHours = null))
                .forEach { (name, answers) ->
                    val snapshot = HealthCareDiscussionPolicy.snapshot(issue.copy(context = answers))
                    val prompt = HealthCareDiscussionPolicy.prompt(
                        "我已经在健康中心填写过检测背景。请先说明你已经读到哪些，再告诉我还缺什么。" +
                            "这次只核对已保存的检测背景表，不做医学判断、不联网、不创建计划，也不重新收集当前症状。", snapshot)
                    val started = SystemClock.elapsedRealtime()
                    val response = CloudModelClient.sendStructured(context, contact,
                        "Reply in Chinese using the supplied authorized Health concern context. Do not invent facts.", prompt)
                    reports.put(JSONObject().put("case", name).put("model", contact.optString("cloud_model"))
                        .put("elapsed_ms", SystemClock.elapsedRealtime() - started).put("answer", response))
                    assertTrue("The provider returned no substantive answer", response.length > 40)
                }
        } finally { report.writeText(JSONObject().put("synthetic_only", true).put("cases", reports).toString(2)) }
        assertEquals(2, reports.length())
    }
}
