package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit, local diagnostics only. No prompts, credentials or private conversation content are exported. */
@RunWith(AndroidJUnit4::class)
class ProactiveAttentionDiagnosticsTest {
    @Test fun resumeExplicitlyAuthorizedLiveAttention() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_live_resume") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = ProactiveAttentionStore(context).preferences()
        assumeTrue(preferences.configured && preferences.enabled)
        ProactiveAttentionCoordinator(context).reconcile()
        AndroidCognitionScheduler.requestAttention(context, 10_000L)
    }

    @Test fun inspectLiveAttentionState() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_live_diagnostics") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = ProactiveAttentionStore(context)
        val preferences = store.preferences()
        val repository = GlobalAgentRepository(context)
        val settings = repository.settings()
        val budget = GlobalModelCallBudgetStore(context).snapshot(settings)
        val report = JSONObject().put("at", System.currentTimeMillis())
            .put("enabled", preferences.enabled).put("configured", preferences.configured)
            .put("paired", preferences.allowPairedModel).put("cloud", preferences.allowCloudModel)
            .put("mode", preferences.alertMode.name).put("global_enabled", settings.enabled)
            .put("research_enabled", settings.autonomousResearchEnabled)
            .put("notifications_enabled", settings.notificationsEnabled)
            .put("routed_resources", JSONArray(GlobalAgentResourceResolver(context).route(
                "Check public news sources", preferences.allowPairedModel, preferences.allowCloudModel)))
            .put("budget", JSONObject().put("dispatches", budget.dispatchesInWindow).put("limit", budget.dailyLimit)
                .put("attention_count_limit", 0)
                .put("attention_denial", GlobalModelCallBudgetStore(context).availability(
                    settings.copy(dailyBackgroundModelCallBudget = 0)).denial?.name.orEmpty())
                .put("active", budget.activeCalls).put("concurrent_limit", budget.concurrencyLimit)
                .put("tokens", budget.totalTokensInWindow).put("token_limit", budget.dailyTokenLimit))
            .put("tasks", JSONArray().apply {
                repository.researchTasks().filter(ProactiveAttentionPolicy::isAttention).forEach { task ->
                    put(JSONObject().put("id", task.id).put("status", task.status.name)
                        .put("updated", task.updatedAtMillis).put("attempts", task.attemptCount)
                        .put("next", task.nextAttemptAtMillis).put("lease", task.leaseExpiresAtMillis)
                        .put("completed", task.lastCompletedAtMillis).put("error", task.lastError.take(500))
                        .put("phase", task.researchPlan.phase.name).put("result_chars", task.result.length)
                        .put("verified", task.evidenceLedger.verified).put("sources", task.evidenceLedger.sources.size)
                        .put("captured_pages", ProactiveAttentionNewsEvidence(context).pages(task).length())
                        .put("source_receipts", ProactiveAttentionNewsEvidence(context).receipts(task))
                        .put("units", JSONArray().apply { task.researchPlan.units.forEach { unit ->
                            put(JSONObject().put("id", unit.id).put("status", unit.status.name)
                                .put("source_count", unit.evidenceUris.size)
                                .put("resource", unit.resourceId).put("source_message", unit.sourceMessageId))
                        } }))
                }
            }).put("findings", JSONArray().apply {
                repository.proactiveMessages().filter(ProactiveAttentionPolicy::isAttention).forEach { message ->
                    put(JSONObject().put("id", message.id).put("status", message.status.name)
                        .put("urgent", message.urgent).put("delivered", message.deliveredAtMillis)
                        .put("notified", message.notifiedAtMillis).put("content_chars", message.content.length))
                }
            })
        File(context.getExternalFilesDir(null), "attention-live-diagnostics.json").writeText(report.toString(2))
    }
}
